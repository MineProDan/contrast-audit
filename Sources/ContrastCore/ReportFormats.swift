extension AuditReport {
    /// The report as a GitHub-flavored Markdown section (DESIGN.md 6.3), for
    /// a CI job summary or a test attachment. Cannot fail.
    ///
    /// Lists every check, including passes, waivers and known failures,
    /// which the failure message only counts. A Note column appears only
    /// when some pair has a note. Names, notes, reasons and problem texts are
    /// escaped so that a `|` or a line break cannot split a table row. Ends
    /// with a newline.
    public func markdown() -> String {
        var lines = ["## Contrast audit: \(MarkdownText.inline(themeName)) (\(level.rawValue))", ""]

        let counts = Counts(results)
        var status = (passed ? "Passed: " : "Failed: ") + countsSentence
        if counts.waived + counts.known > 0 {
            status += " \(counts.waived) waived, \(plural(counts.known, "known failure", "known failures"))."
        }
        lines.append(status)
        lines.append("")

        if !problems.isEmpty {
            lines.append("Theme problems:")
            lines.append("")
            for problem in problems {
                lines.append("- " + MarkdownText.inline(problem.description))
            }
            lines.append("")
        }

        let hasNotes = results.contains { $0.pair.note != nil }
        var header = ["Variant", "Foreground", "Background", "Role", "Ratio", "Required", "Status"]
        if hasNotes {
            header.append("Note")
        }
        lines.append(MarkdownText.row(header))
        lines.append("|" + String(repeating: "---|", count: header.count))
        for result in results {
            var cells = [
                MarkdownText.inline(result.variant),
                MarkdownText.inline(result.pair.foreground),
                MarkdownText.inline(result.pair.background),
                result.pair.role.displayName,
                result.ratio.map(\.description) ?? "n/a",
                result.required.description,
                markdownStatus(result),
            ]
            if hasNotes {
                cells.append(result.pair.note.map(MarkdownText.inline) ?? "")
            }
            lines.append(MarkdownText.row(cells))
        }

        if !unusedWaivers.isEmpty {
            lines.append("")
            lines.append("Unused waivers:")
            lines.append("")
            for waiver in unusedWaivers {
                let scope = waiver.variant.map { "[\(MarkdownText.inline($0))]" } ?? "[all variants]"
                lines.append("- \(scope) '\(MarkdownText.inline(waiver.foreground))' on "
                    + "'\(MarkdownText.inline(waiver.background))': \(MarkdownText.inline(waiver.reason))")
            }
        }
        if !outdatedBaselineEntries.isEmpty {
            lines.append("")
            lines.append("Outdated baseline entries:")
            lines.append("")
            for entry in outdatedBaselineEntries {
                let recorded = ContrastRatio(uncheckedValue: entry.ratio)
                lines.append("- [\(MarkdownText.inline(entry.variant))] '\(MarkdownText.inline(entry.foreground))' on "
                    + "'\(MarkdownText.inline(entry.background))' (recorded \(recorded))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The report as JSON (DESIGN.md 6.4): schemaVersion 1, pretty-printed,
    /// keys sorted, ratios unrounded, trailing newline. Cannot fail.
    ///
    /// Each result has `background`, `foreground`, `ratio` (null when the
    /// check is invalid), `required`, `role`, `status` and `variant`, plus
    /// `note` when the pair has one and the fields that apply to its status:
    /// `waiverReason` and `expiryNote` (waived), `baselineRatio` (known
    /// failure, regressed) and `problem` (invalid). `status` is one of
    /// `passed`, `failed`, `waived`, `knownFailure`, `regressed`, `invalid`.
    ///
    /// Written by hand rather than with JSONEncoder, like `Baseline.json()`,
    /// so that the same report gives the same bytes on every platform.
    public func json() -> String {
        let object: [String: JSONValue] = [
            "schemaVersion": .integer(AuditReport.jsonSchemaVersion),
            "theme": .string(themeName),
            "level": .string(level.rawValue),
            "passed": .bool(passed),
            "summary": .string(summary),
            "problems": .array(problems.map { .string($0.description) }),
            "results": .array(results.map(jsonResult)),
            "unusedWaivers": .array(unusedWaivers.map(jsonWaiver)),
            "outdatedBaselineEntries": .array(outdatedBaselineEntries.map(jsonEntry)),
        ]
        return JSONValue.object(object).pretty(indent: 0) + "\n"
    }

    /// Version of the report JSON written by `json()`. Internal because the
    /// approved API has no public constant for it; the value is in the JSON.
    static let jsonSchemaVersion = 1

    private func markdownStatus(_ result: CheckResult) -> String {
        switch result.status {
        case .passed:
            return "passed"
        case .failed:
            return "**failed**"
        case let .waived(waiver):
            return "waived: " + MarkdownText.inline(waiver.reason)
        case let .knownFailure(baseline):
            return "known failure (baseline \(baseline))"
        case let .regressed(baseline):
            var text = "**regressed** (baseline \(baseline)"
            if let ratio = result.ratio {
                text += ", -" + DecimalText.truncated(baseline.value - ratio.value, decimals: 6)
            }
            return text + ")"
        case let .invalid(problem):
            return "**invalid**: " + MarkdownText.inline(problem.description)
        }
    }

    private func jsonResult(_ result: CheckResult) -> JSONValue {
        var object: [String: JSONValue] = [
            "variant": .string(result.variant),
            "foreground": .string(result.pair.foreground),
            "background": .string(result.pair.background),
            "role": .string(result.pair.role.rawValue),
            "required": .number(result.required.value),
            "ratio": result.ratio.map { .number($0.value) } ?? .null,
        ]
        if let note = result.pair.note {
            object["note"] = .string(note)
        }
        switch result.status {
        case .passed:
            object["status"] = .string("passed")
        case .failed:
            object["status"] = .string("failed")
        case let .waived(waiver):
            object["status"] = .string("waived")
            object["waiverReason"] = .string(waiver.reason)
            if let expiryNote = waiver.expiryNote {
                object["expiryNote"] = .string(expiryNote)
            }
        case let .knownFailure(baseline):
            object["status"] = .string("knownFailure")
            object["baselineRatio"] = .number(baseline.value)
        case let .regressed(baseline):
            object["status"] = .string("regressed")
            object["baselineRatio"] = .number(baseline.value)
        case let .invalid(problem):
            object["status"] = .string("invalid")
            object["problem"] = .string(problem.description)
        }
        return .object(object)
    }

    private func jsonWaiver(_ waiver: Waiver) -> JSONValue {
        var object: [String: JSONValue] = [
            "foreground": .string(waiver.foreground),
            "background": .string(waiver.background),
            // null rather than a missing key: a waiver for every variant is
            // a deliberate choice, and an explicit null says so.
            "variant": waiver.variant.map { .string($0) } ?? .null,
            "reason": .string(waiver.reason),
        ]
        if let expiryNote = waiver.expiryNote {
            object["expiryNote"] = .string(expiryNote)
        }
        return .object(object)
    }

    private func jsonEntry(_ entry: Baseline.Entry) -> JSONValue {
        .object([
            "variant": .string(entry.variant),
            "foreground": .string(entry.foreground),
            "background": .string(entry.background),
            "ratio": .number(entry.ratio),
        ])
    }
}

/// Escaping for text placed in a Markdown table or heading.
enum MarkdownText {
    /// `text` with `|` escaped and every line break replaced by `<br>`, so
    /// it stays inside one table cell or one heading line.
    static func inline(_ text: String) -> String {
        var result = ""
        for character in text {
            if character == "|" {
                result += "\\|"
            } else if character.isNewline {
                result += "<br>"
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// One table row from already escaped cells.
    static func row(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }
}

/// A JSON value for the hand-written report output.
enum JSONValue {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    /// Pretty-printed in the layout JSONEncoder uses with `.prettyPrinted`
    /// and `.sortedKeys` (two-space indent, `"key" : value`), without a
    /// trailing newline. Keys contain only ASCII here, so `<` sorts them the
    /// same way everywhere.
    func pretty(indent: Int) -> String {
        let inner = String(repeating: " ", count: indent + 2)
        let outer = String(repeating: " ", count: indent)
        switch self {
        case let .string(text):
            return JSONText.quoted(text)
        case let .number(value):
            return JSONValue.format(value)
        case let .integer(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case let .array(items):
            guard !items.isEmpty else {
                return "[]"
            }
            let body = items.map { inner + $0.pretty(indent: indent + 2) }
            return "[\n" + body.joined(separator: ",\n") + "\n" + outer + "]"
        case let .object(fields):
            guard !fields.isEmpty else {
                return "{}"
            }
            let body = fields.keys.sorted().map { key in
                inner + JSONText.quoted(key) + " : " + (fields[key] ?? .null).pretty(indent: indent + 2)
            }
            return "{\n" + body.joined(separator: ",\n") + "\n" + outer + "}"
        }
    }

    private static func format(_ value: Double) -> String {
        JSONText.number(value)
    }
}
