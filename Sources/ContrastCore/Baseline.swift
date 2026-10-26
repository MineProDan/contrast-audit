import Foundation

/// Known failures recorded at one level, which may not get worse.
///
/// A baseline lets an existing project adopt the audit without a red build:
/// recorded failures become known failures, while new failures and
/// regressions beyond `tolerance` still fail. See DESIGN.md 5.5.
public struct Baseline: Sendable, Equatable {
    /// The only file format version this library reads and writes.
    public static let currentSchemaVersion: Int = 1
    /// Ratios within this distance of the recorded value count as unchanged.
    ///
    /// Large enough to absorb last-bit differences between platform `pow`
    /// implementations, small enough to catch a one-step change of one 8-bit
    /// channel (about 2e-5 or more).
    public static let tolerance: Double = 1e-6

    /// One recorded failing check.
    public struct Entry: Sendable, Hashable {
        /// Variant name of the recorded check.
        public let variant: String
        /// Foreground color name of the recorded check.
        public let foreground: String
        /// Background color name of the recorded check.
        public let background: String
        /// Unrounded ratio at recording time.
        public let ratio: Double

        init(variant: String, foreground: String, background: String, ratio: Double) {
            self.variant = variant
            self.foreground = foreground
            self.background = background
            self.ratio = ratio
        }
    }

    /// The level the baseline was recorded at. An audit at another level
    /// ignores the baseline and fails with `baselineLevelMismatch`.
    public let level: ConformanceLevel
    /// Sorted by variant, foreground, background, so diffs stay small.
    public let entries: [Entry]

    /// Records every check whose status is failed, knownFailure or regressed,
    /// at its current ratio. Waived and invalid checks are not recorded.
    /// Cannot fail.
    public init(recording report: AuditReport) {
        var recorded: [Entry] = []
        for result in report.results {
            switch result.status {
            case .failed, .knownFailure, .regressed:
                if let ratio = result.ratio {
                    recorded.append(Entry(variant: result.variant, foreground: result.pair.foreground,
                                          background: result.pair.background, ratio: ratio.value))
                }
            case .passed, .waived, .invalid:
                break
            }
        }
        self.level = report.level
        self.entries = Baseline.sorted(recorded)
    }

    /// Parses the JSON written by `json()`.
    ///
    /// - Throws: `ContrastError.unsupportedBaselineVersion` for any
    ///   schemaVersion other than 1; `ContrastError.malformedBaseline` for
    ///   invalid JSON, missing fields, an unknown level, duplicate entries,
    ///   or a ratio that is non-finite or outside 1...21.
    public init(json: String) throws {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        // The version is checked before anything else, so a future format
        // with a different shape reports its version instead of a vague
        // decoding error.
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw ContrastError.malformedBaseline(Baseline.explain(error))
        }
        guard probe.schemaVersion == Baseline.currentSchemaVersion else {
            throw ContrastError.unsupportedBaselineVersion(probe.schemaVersion)
        }

        let file: FileFormat
        do {
            file = try decoder.decode(FileFormat.self, from: data)
        } catch {
            throw ContrastError.malformedBaseline(Baseline.explain(error))
        }
        guard let level = ConformanceLevel(rawValue: file.level) else {
            throw ContrastError.malformedBaseline("unknown level '\(file.level)'; expected 'AA' or 'AAA'")
        }

        var seen: Set<CheckKey> = []
        var parsed: [Entry] = []
        for (index, item) in file.entries.enumerated() {
            guard item.ratio.isFinite, (1.0...21.0).contains(item.ratio) else {
                throw ContrastError.malformedBaseline(
                    "entry \(index) has ratio \(item.ratio); ratios must be within 1...21")
            }
            let entry = Entry(variant: item.variant, foreground: item.foreground,
                              background: item.background, ratio: item.ratio)
            guard seen.insert(CheckKey(entry)).inserted else {
                throw ContrastError.malformedBaseline(
                    "duplicate entry for [\(item.variant)] '\(item.foreground)' on '\(item.background)'")
            }
            parsed.append(entry)
        }
        self.level = level
        self.entries = Baseline.sorted(parsed)
    }

    /// The baseline as JSON: pretty-printed, keys sorted, trailing newline.
    /// Cannot fail.
    ///
    /// Written by hand rather than with JSONEncoder so that the bytes are the
    /// same on every platform; Double's `description` is the shortest string
    /// that reads back as the same value.
    public func json() -> String {
        var lines = ["{"]
        if entries.isEmpty {
            lines.append("  \"entries\" : [],")
        } else {
            lines.append("  \"entries\" : [")
            for (index, entry) in entries.enumerated() {
                lines.append("    {")
                lines.append("      \"background\" : \(JSONText.quoted(entry.background)),")
                lines.append("      \"foreground\" : \(JSONText.quoted(entry.foreground)),")
                lines.append("      \"ratio\" : \(JSONText.number(entry.ratio)),")
                lines.append("      \"variant\" : \(JSONText.quoted(entry.variant))")
                lines.append(index == entries.count - 1 ? "    }" : "    },")
            }
            lines.append("  ],")
        }
        lines.append("  \"level\" : \(JSONText.quoted(level.rawValue)),")
        lines.append("  \"schemaVersion\" : \(Baseline.currentSchemaVersion)")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { lhs, rhs in
            if lhs.variant != rhs.variant { return lhs.variant < rhs.variant }
            if lhs.foreground != rhs.foreground { return lhs.foreground < rhs.foreground }
            return lhs.background < rhs.background
        }
    }

    private static func explain(_ error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "missing field '\(key.stringValue)'" + location(context)
        case let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context):
            return "wrong type or null value" + location(context)
        case DecodingError.dataCorrupted:
            return "not valid JSON"
        default:
            return "could not be decoded"
        }
    }

    private static func location(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { key in
            key.intValue.map(String.init) ?? key.stringValue
        }
        return path.isEmpty ? "" : " at " + path.joined(separator: ".")
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct FileFormat: Decodable {
        let schemaVersion: Int
        let level: String
        let entries: [EntryFormat]
    }

    private struct EntryFormat: Decodable {
        let variant: String
        let foreground: String
        let background: String
        let ratio: Double
    }
}

/// Minimal JSON string escaping for the hand-written JSON outputs.
enum JSONText {
    /// `value` as a JSON number, shared by the baseline and report formats so
    /// they never write the same number differently. Swift's `description` is
    /// the shortest text that reads back as the same Double and does not
    /// depend on the platform's C library. Whole numbers drop the ".0" to match
    /// JSONEncoder (a requirement of 3 prints as `3`).
    static func number(_ value: Double) -> String {
        guard value.isFinite else {
            // Unreachable for library-computed ratios; JSON has no NaN.
            return "null"
        }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return value.description
    }

    /// `text` as a JSON string literal, with quotes, backslashes and control
    /// characters escaped. Other characters are written as UTF-8.
    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16, uppercase: true)
                    result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
