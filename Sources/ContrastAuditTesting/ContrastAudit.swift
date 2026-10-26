/// Namespace for the assertion helpers: `assertPasses` for XCTest and
/// `expectPasses` for Swift Testing.
///
/// Both audit a theme, record exactly one failure with the report's
/// `failureDescription` at the caller's source location when the report did
/// not pass, and return the report. They never print, and on success they
/// record nothing, even when the report lists unused waivers or outdated
/// baseline entries.
///
/// This module does not re-export ContrastCore, so a test file imports both
/// `ContrastCore` (to declare the theme) and `ContrastAuditTesting`.
public enum ContrastAudit {}
