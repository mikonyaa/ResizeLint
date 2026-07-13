import Foundation

public struct BaselineEntry: Codable, Equatable, Hashable, Comparable, Sendable {
    public let ruleID: String
    public let path: String
    public let fingerprint: String

    public init(ruleID: String, path: String, fingerprint: String) {
        self.ruleID = ruleID
        self.path = path
        self.fingerprint = fingerprint
    }

    public static func < (lhs: BaselineEntry, rhs: BaselineEntry) -> Bool {
        (lhs.path, lhs.ruleID, lhs.fingerprint) < (rhs.path, rhs.ruleID, rhs.fingerprint)
    }
}

public struct BaselineDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let toolVersion: String
    public let findings: [BaselineEntry]

    public init(
        schemaVersion: Int = 1,
        toolVersion: String = ResizeLintVersion.current,
        findings: [BaselineEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.toolVersion = toolVersion
        self.findings = findings.sorted()
    }
}

public enum BaselineError: Error, Equatable {
    case alreadyExists
    case unsupportedSchema(Int)
    case duplicateEntry(BaselineEntry)
}

public struct BaselineIssue: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case duplicate
        case stale
        case unsafePath
    }

    public let kind: Kind
    public let entry: BaselineEntry

    public init(kind: Kind, entry: BaselineEntry) {
        self.kind = kind
        self.entry = entry
    }
}

public enum BaselineStore {
    public static func create(findings: [BaselineEntry], at url: URL, force: Bool) throws {
        if FileManager.default.fileExists(atPath: url.path), !force { throw BaselineError.alreadyExists }
        try write(BaselineDocument(findings: findings), to: url)
    }

    public static func update(findings: [BaselineEntry], at url: URL) throws {
        try write(BaselineDocument(findings: findings), to: url)
    }

    public static func load(from url: URL) throws -> BaselineDocument {
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(BaselineDocument.self, from: data)
        guard document.schemaVersion == 1 else { throw BaselineError.unsupportedSchema(document.schemaVersion) }
        return document
    }

    public static func check(_ document: BaselineDocument, current: [BaselineEntry]) -> [BaselineIssue] {
        var issues: [BaselineIssue] = []
        var seen: Set<BaselineEntry> = []
        let currentSet = Set(current)
        for entry in document.findings {
            if !seen.insert(entry).inserted { issues.append(BaselineIssue(kind: .duplicate, entry: entry)) }
            if !currentSet.contains(entry) { issues.append(BaselineIssue(kind: .stale, entry: entry)) }
            if isUnsafe(entry.path) { issues.append(BaselineIssue(kind: .unsafePath, entry: entry)) }
        }
        return issues
    }

    public static func entries(from diagnostics: [Diagnostic]) -> [BaselineEntry] {
        diagnostics
            .filter { !$0.isSuppressed }
            .map { BaselineEntry(ruleID: $0.ruleID, path: $0.path, fingerprint: $0.fingerprint) }
            .sorted()
    }

    public static func contains(_ diagnostic: Diagnostic, in document: BaselineDocument) -> Bool {
        document.findings.contains(BaselineEntry(
            ruleID: diagnostic.ruleID,
            path: diagnostic.path,
            fingerprint: diagnostic.fingerprint
        ))
    }

    private static func isUnsafe(_ path: String) -> Bool {
        path.hasPrefix("/") || path.split(separator: "/").contains("..")
    }

    private static func write(_ document: BaselineDocument, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(10)
        try data.write(to: url, options: .atomic)
    }
}

public extension AnalysisResult {
    func applying(baseline: BaselineDocument) -> AnalysisResult {
        AnalysisResult(
            diagnostics: diagnostics.map { diagnostic in
                guard BaselineStore.contains(diagnostic, in: baseline) else { return diagnostic }
                return Diagnostic(
                    ruleID: diagnostic.ruleID,
                    ruleName: diagnostic.ruleName,
                    severity: diagnostic.severity,
                    message: diagnostic.message,
                    path: diagnostic.path,
                    range: diagnostic.range,
                    helpURI: diagnostic.helpURI,
                    fix: diagnostic.fix,
                    fingerprint: diagnostic.fingerprint,
                    isSuppressed: diagnostic.isSuppressed,
                    baselineState: .unchanged
                )
            },
            notices: notices,
            filesAnalyzed: filesAnalyzed
        )
    }

    func reachesFailureThreshold(_ severity: Severity) -> Bool {
        diagnostics.contains {
            !$0.isSuppressed && $0.baselineState != .unchanged && $0.severity.reaches(severity)
        }
    }
}
