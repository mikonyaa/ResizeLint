import Foundation

public enum Severity: String, Codable, CaseIterable, Sendable {
    case error
    case warning
    case info

    public var rank: Int {
        switch self {
        case .error: 3
        case .warning: 2
        case .info: 1
        }
    }

    public func reaches(_ threshold: Severity) -> Bool {
        rank >= threshold.rank
    }
}

public struct SourceLocation: Codable, Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public struct SourceRange: Codable, Equatable, Sendable {
    public let start: SourceLocation
    public let end: SourceLocation
    public let utf8Offset: Int
    public let utf8Length: Int

    public init(start: SourceLocation, end: SourceLocation, utf8Offset: Int, utf8Length: Int) {
        self.start = start
        self.end = end
        self.utf8Offset = utf8Offset
        self.utf8Length = utf8Length
    }
}

public struct SourceEdit: Codable, Equatable, Sendable {
    public let path: String
    public let utf8Offset: Int
    public let utf8Length: Int
    public let replacement: String

    public init(path: String, utf8Offset: Int, utf8Length: Int, replacement: String) {
        self.path = path
        self.utf8Offset = utf8Offset
        self.utf8Length = utf8Length
        self.replacement = replacement
    }
}

public enum BaselineState: String, Codable, Sendable {
    case new
    case unchanged
    case absent
}

public struct Diagnostic: Codable, Equatable, Comparable, Sendable {
    public let ruleID: String
    public let ruleName: String
    public let severity: Severity
    public let message: String
    public let path: String
    public let range: SourceRange
    public let helpURI: String
    public let fix: SourceEdit?
    public let fingerprint: String
    public let isSuppressed: Bool
    public let baselineState: BaselineState

    public init(
        ruleID: String,
        ruleName: String,
        severity: Severity,
        message: String,
        path: String,
        range: SourceRange,
        helpURI: String,
        fix: SourceEdit? = nil,
        fingerprint: String,
        isSuppressed: Bool = false,
        baselineState: BaselineState = .absent
    ) {
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.severity = severity
        self.message = message
        self.path = path
        self.range = range
        self.helpURI = helpURI
        self.fix = fix
        self.fingerprint = fingerprint
        self.isSuppressed = isSuppressed
        self.baselineState = baselineState
    }

    public static func < (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        (lhs.path, lhs.range.start.line, lhs.range.start.column, lhs.ruleID)
            < (rhs.path, rhs.range.start.line, rhs.range.start.column, rhs.ruleID)
    }

    static func fixture(ruleID: String, path: String, line: Int, column: Int) -> Diagnostic {
        let location = SourceLocation(line: line, column: column)
        return Diagnostic(
            ruleID: ruleID,
            ruleName: "fixture",
            severity: .warning,
            message: "Fixture",
            path: path,
            range: SourceRange(start: location, end: location, utf8Offset: 0, utf8Length: 0),
            helpURI: "https://example.invalid",
            fingerprint: "sha256:fixture"
        )
    }
}

public struct OperationalNotice: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case malformedSuppression
        case syntaxError
        case unreadableFile
        case ambiguousProject
    }

    public let kind: Kind
    public let path: String
    public let message: String

    public init(kind: Kind, path: String, message: String) {
        self.kind = kind
        self.path = path
        self.message = message
    }
}
