import Foundation

public struct BaselineEntry: Codable, Equatable, Hashable, Comparable, Sendable {
    public let ruleID: String
    public let path: String
    public let fingerprint: String
    public let occurrences: Int

    public init(ruleID: String, path: String, fingerprint: String, occurrences: Int = 1) {
        self.ruleID = ruleID
        self.path = path
        self.fingerprint = fingerprint
        self.occurrences = occurrences
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ruleID = try values.decode(String.self, forKey: .ruleID)
        path = try values.decode(String.self, forKey: .path)
        fingerprint = try values.decode(String.self, forKey: .fingerprint)
        occurrences = try values.decodeIfPresent(Int.self, forKey: .occurrences) ?? 1
    }

    var identity: BaselineEntry { BaselineEntry(ruleID: ruleID, path: path, fingerprint: fingerprint) }

    public static func < (lhs: BaselineEntry, rhs: BaselineEntry) -> Bool {
        (lhs.path, lhs.ruleID, lhs.fingerprint, lhs.occurrences)
            < (rhs.path, rhs.ruleID, rhs.fingerprint, rhs.occurrences)
    }
}

public struct BaselineDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let fingerprintVersion: Int
    public let toolVersion: String
    public let findings: [BaselineEntry]

    public init(
        schemaVersion: Int = 2, fingerprintVersion: Int? = nil,
        toolVersion: String = ResizeLintVersion.current, findings: [BaselineEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.fingerprintVersion = fingerprintVersion ?? schemaVersion
        self.toolVersion = toolVersion
        self.findings = findings.sorted()
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        fingerprintVersion = try values.decodeIfPresent(Int.self, forKey: .fingerprintVersion) ?? 1
        toolVersion = try values.decode(String.self, forKey: .toolVersion)
        if schemaVersion == 2 {
            findings = try values.decode([CountedBaselineEntry].self, forKey: .findings).map(\.entry)
        } else {
            findings = try values.decode([BaselineEntry].self, forKey: .findings)
        }
    }
}

private struct CountedBaselineEntry: Decodable {
    private enum CodingKeys: String, CodingKey { case occurrences }
    let entry: BaselineEntry

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        _ = try values.decode(Int.self, forKey: .occurrences)
        entry = try BaselineEntry(from: decoder)
    }
}

public enum BaselineError: Error, Equatable {
    case alreadyExists
    case unsupportedSchema(Int)
    case duplicateEntry(BaselineEntry)
    case ambiguousLegacyEntry(BaselineEntry)
    case staleLegacyEntry(BaselineEntry)
    case invalidDocument
    case fileTooLarge(Int)
    case unsafeDestination
}

public struct BaselineIssue: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case duplicate, stale, unsafePath, invalidCount, new
    }
    public let kind: Kind
    public let entry: BaselineEntry
    public init(kind: Kind, entry: BaselineEntry) {
        self.kind = kind
        self.entry = entry
    }
}

public enum BaselineStore {
    private static let maximumBytes = 10 * 1_048_576

    public static func create(findings: [BaselineEntry], at url: URL, force: Bool) throws {
        if FileManager.default.fileExists(atPath: url.path), !force { throw BaselineError.alreadyExists }
        try write(BaselineDocument(findings: aggregate(findings)), to: url)
    }

    public static func update(findings: [BaselineEntry], at url: URL) throws {
        try write(BaselineDocument(findings: aggregate(findings)), to: url)
    }

    public static func load(from url: URL) throws -> BaselineDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let bytes = values.fileSize, bytes > maximumBytes { throw BaselineError.fileTooLarge(bytes) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else { throw BaselineError.fileTooLarge(data.count) }
        let document: BaselineDocument
        do { document = try JSONDecoder().decode(BaselineDocument.self, from: data) }
        catch { throw BaselineError.invalidDocument }
        guard document.schemaVersion == 1 || document.schemaVersion == 2 else {
            throw BaselineError.unsupportedSchema(document.schemaVersion)
        }
        guard document.fingerprintVersion == document.schemaVersion,
              document.findings.allSatisfy({ $0.occurrences > 0 && (document.schemaVersion != 1 || $0.occurrences == 1) }) else {
            throw BaselineError.invalidDocument
        }
        return document
    }

    public static func check(_ document: BaselineDocument, current: [BaselineEntry]) -> [BaselineIssue] {
        var issues = validationIssues(document)
        let currentCounts = counts(current)
        let recordedCounts = counts(document.findings)
        for entry in document.findings where currentCounts[entry.identity, default: 0] < entry.occurrences {
            issues.append(BaselineIssue(kind: .stale, entry: entry))
        }
        for entry in current where entry.occurrences > recordedCounts[entry.identity, default: 0] {
            issues.append(BaselineIssue(kind: .new, entry: entry))
        }
        return issues.sorted { $0.entry == $1.entry ? $0.kind.rawValue < $1.kind.rawValue : $0.entry < $1.entry }
    }

    public static func check(_ document: BaselineDocument, diagnostics: [Diagnostic]) -> [BaselineIssue] {
        let current = document.schemaVersion == 1
            ? aggregate(diagnostics.filter { !$0.isSuppressed }.map(legacyEntry)) : entries(from: diagnostics)
        return check(document, current: current)
    }

    public static func validateForMatching(_ document: BaselineDocument) throws {
        guard validationIssues(document).isEmpty else { throw BaselineError.invalidDocument }
    }

    static func validationIssues(_ document: BaselineDocument) -> [BaselineIssue] {
        var seen: Set<BaselineEntry> = []
        var issues: [BaselineIssue] = []
        for entry in document.findings {
            if !seen.insert(entry.identity).inserted { issues.append(BaselineIssue(kind: .duplicate, entry: entry)) }
            if isUnsafe(entry.path) { issues.append(BaselineIssue(kind: .unsafePath, entry: entry)) }
            if entry.occurrences <= 0 { issues.append(BaselineIssue(kind: .invalidCount, entry: entry)) }
        }
        return issues
    }

    public static func entries(from diagnostics: [Diagnostic]) -> [BaselineEntry] {
        aggregate(diagnostics.filter { !$0.isSuppressed }.map {
            BaselineEntry(ruleID: $0.ruleID, path: $0.path, fingerprint: $0.fingerprint)
        })
    }

    /// Migration maps accepted entries, never captures additional current debt.
    public static func migrate(_ document: BaselineDocument, current: [Diagnostic]) throws -> BaselineDocument {
        guard validationIssues(document).isEmpty else { throw BaselineError.invalidDocument }
        if document.schemaVersion == 2 { return document }
        let groups = Dictionary(grouping: current.filter { !$0.isSuppressed }, by: legacyEntry)
        var migrated: [Diagnostic] = []
        for entry in document.findings {
            let candidates = groups[entry.identity, default: []]
            guard !candidates.isEmpty else { throw BaselineError.staleLegacyEntry(entry) }
            guard candidates.count == 1 else { throw BaselineError.ambiguousLegacyEntry(entry) }
            migrated.append(contentsOf: candidates)
        }
        return BaselineDocument(findings: entries(from: migrated))
    }

    static func legacyEntry(_ diagnostic: Diagnostic) -> BaselineEntry {
        BaselineEntry(ruleID: diagnostic.ruleID, path: diagnostic.path,
                      fingerprint: diagnostic.legacyFingerprint ?? diagnostic.fingerprint)
    }

    static func counts(_ entries: [BaselineEntry]) -> [BaselineEntry: Int] {
        var result: [BaselineEntry: Int] = [:]
        for entry in entries {
            let (total, overflow) = result[entry.identity, default: 0].addingReportingOverflow(entry.occurrences)
            result[entry.identity] = overflow ? Int.max : total
        }
        return result
    }

    private static func aggregate(_ entries: [BaselineEntry]) -> [BaselineEntry] {
        counts(entries).map { key, count in
            BaselineEntry(ruleID: key.ruleID, path: key.path, fingerprint: key.fingerprint, occurrences: count)
        }.sorted()
    }

    private static func isUnsafe(_ path: String) -> Bool {
        path.hasPrefix("/") || path.split(separator: "/").contains("..")
            || path.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }
    }

    private static func write(_ document: BaselineDocument, to url: URL) throws {
        guard validationIssues(document).isEmpty else { throw BaselineError.invalidDocument }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil { throw BaselineError.unsafeDestination }
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw BaselineError.unsafeDestination }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(10)
        guard data.count <= maximumBytes else { throw BaselineError.fileTooLarge(data.count) }
        try data.write(to: url, options: .atomic)
    }
}

public extension AnalysisResult {
    func applying(baseline: BaselineDocument) -> AnalysisResult {
        var remaining = BaselineStore.counts(baseline.findings)
        let legacyGroups = baseline.schemaVersion == 1
            ? Dictionary(grouping: diagnostics.filter { !$0.isSuppressed }, by: BaselineStore.legacyEntry) : [:]
        let marked = diagnostics.sorted().map { diagnostic in
            let entry = baseline.schemaVersion == 1 ? BaselineStore.legacyEntry(diagnostic)
                : BaselineEntry(ruleID: diagnostic.ruleID, path: diagnostic.path, fingerprint: diagnostic.fingerprint)
            let uniqueLegacy = baseline.schemaVersion != 1 || legacyGroups[entry]?.count == 1
            let accepted = !diagnostic.isSuppressed && uniqueLegacy && remaining[entry, default: 0] > 0
            if accepted { remaining[entry, default: 0] -= 1 }
            return Diagnostic(
                ruleID: diagnostic.ruleID, ruleName: diagnostic.ruleName, severity: diagnostic.severity,
                message: diagnostic.message, path: diagnostic.path, range: diagnostic.range,
                helpURI: diagnostic.helpURI, fix: diagnostic.fix, fingerprint: diagnostic.fingerprint,
                isSuppressed: diagnostic.isSuppressed, baselineState: accepted ? .unchanged : .new,
                legacyFingerprint: diagnostic.legacyFingerprint
            )
        }
        var baselineNotices = notices
        if baseline.schemaVersion == 1 {
            baselineNotices.append(OperationalNotice(kind: .baselineMigration, path: "",
                message: "Baseline v1: migrate with 'resizelint baseline migrate'. Ambiguous repeated fingerprints stay new; migration refuses ambiguous or stale entries."))
        }
        return AnalysisResult(diagnostics: marked, notices: baselineNotices, filesAnalyzed: filesAnalyzed)
    }

    func reachesFailureThreshold(_ severity: Severity) -> Bool {
        diagnostics.contains { !$0.isSuppressed && $0.baselineState != .unchanged && $0.severity.reaches(severity) }
    }
}
