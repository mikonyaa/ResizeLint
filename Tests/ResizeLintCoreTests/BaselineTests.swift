import Foundation
import Testing
@testable import ResizeLintCore

@Test("Baseline creation is deterministic and refuses overwrite")
func baselineCreateRefusesOverwrite() throws {
    let url = temporaryFile(named: "baseline-create.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let findings = [BaselineEntry(ruleID: "RL002", path: "B.swift", fingerprint: "sha256:b"),
                    BaselineEntry(ruleID: "RL001", path: "A.swift", fingerprint: "sha256:a")]

    try BaselineStore.create(findings: findings, at: url, force: false)
    #expect(throws: BaselineError.alreadyExists) {
        try BaselineStore.create(findings: findings, at: url, force: false)
    }
    let decoded = try BaselineStore.load(from: url)
    #expect(decoded.findings.map(\.ruleID) == ["RL001", "RL002"])
}

@Test("Baseline update drops stale entries and adds current findings")
func baselineUpdate() throws {
    let url = temporaryFile(named: "baseline-update.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try BaselineStore.create(
        findings: [BaselineEntry(ruleID: "RL001", path: "Old.swift", fingerprint: "sha256:old")],
        at: url,
        force: false
    )

    try BaselineStore.update(
        findings: [BaselineEntry(ruleID: "RL002", path: "Current.swift", fingerprint: "sha256:new")],
        at: url
    )

    let decoded = try BaselineStore.load(from: url)
    #expect(decoded.findings == [BaselineEntry(ruleID: "RL002", path: "Current.swift", fingerprint: "sha256:new")])
}

@Test("Baseline check reports duplicates, stale entries, and unsafe paths")
func baselineCheck() {
    let document = BaselineDocument(findings: [
        BaselineEntry(ruleID: "RL001", path: "../Escape.swift", fingerprint: "sha256:a"),
        BaselineEntry(ruleID: "RL001", path: "../Escape.swift", fingerprint: "sha256:a"),
        BaselineEntry(ruleID: "RL002", path: "Stale.swift", fingerprint: "sha256:stale"),
    ])
    let issues = BaselineStore.check(
        document,
        current: [BaselineEntry(ruleID: "RL003", path: "Current.swift", fingerprint: "sha256:current")]
    )

    #expect(issues.contains { $0.kind == .duplicate })
    #expect(issues.contains { $0.kind == .stale })
    #expect(issues.contains { $0.kind == .unsafePath })
}

@Test("Malformed baseline JSON is reported as a baseline error")
func malformedBaselineJSON() throws {
    let url = temporaryFile(named: "malformed.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: url)

    #expect(throws: BaselineError.self) {
        try BaselineStore.load(from: url)
    }
}

@Test("Oversized unreadable baseline is rejected before reading")
func oversizedBaselineIsRejectedBeforeRead() throws {
    let url = temporaryFile(named: "oversized.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 10 * 1_048_576 + 1)
    try handle.close()
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }

    #expect(throws: BaselineError.self) {
        try BaselineStore.load(from: url)
    }
}

@Test("Baseline v2 requires an explicit occurrence count while v1 remains readable")
func baselineCountIsRequiredOnlyForV2() throws {
    let url = temporaryFile(named: "count.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let entry = #"{"ruleID":"RL001","path":"Canvas.swift","fingerprint":"sha256:example"}"#
    let legacy = "{\"schemaVersion\":1,\"toolVersion\":\"1.0.0\",\"findings\":[\(entry)]}"
    try Data(legacy.utf8).write(to: url)
    #expect(try BaselineStore.load(from: url).findings.first?.occurrences == 1)
    let current = "{\"schemaVersion\":2,\"fingerprintVersion\":2,\"toolVersion\":\"1.0.1-rc.1\",\"findings\":[\(entry)]}"
    try Data(current.utf8).write(to: url)
    #expect(throws: BaselineError.invalidDocument) { try BaselineStore.load(from: url) }
}

@Test("Baseline writes refuse symbolic-link destinations")
func baselineWriteRejectsSymlink() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "resizelint-baseline-symlink-\(UUID().uuidString)")
    let outside = FileManager.default.temporaryDirectory.appending(path: "resizelint-baseline-outside-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("sentinel".utf8).write(to: outside)
    let link = root.appending(path: "baseline.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

    #expect(throws: BaselineError.self) {
        try BaselineStore.update(findings: [], at: link)
    }

    #expect(try String(contentsOf: outside, encoding: .utf8) == "sentinel")
    #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
}

private func temporaryFile(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "resizelint-baseline-\(UUID().uuidString)")
        .appending(path: name)
}

@Test("A baseline never hides an identical expression added to another declaration")
func baselineDetectsAddedDeclarationAndLineMovement() async throws {
    let source = "func first() { let width = UIScreen.main.bounds.width }"
    let first = await baselineAnalysis(source)
    let document = BaselineDocument(findings: BaselineStore.entries(from: first.diagnostics))
    let moved = await baselineAnalysis("// shifted\n\n" + source)
    #expect(!moved.applying(baseline: document).reachesFailureThreshold(.error))
    let added = await baselineAnalysis(source + "\nfunc second() { let width = UIScreen.main.bounds.width }")
    let marked = added.applying(baseline: document)
    #expect(marked.diagnostics.count { $0.baselineState == .unchanged } == 1)
    #expect(marked.diagnostics.count { $0.baselineState == .new } == 1)
    #expect(marked.reachesFailureThreshold(.error))
    #expect(BaselineStore.check(document, diagnostics: added.diagnostics).contains { $0.kind == .new })
}

@Test("Truly identical occurrences use a budget and update/check round trip is valid")
func baselineCountsOccurrences() async throws {
    let one = await baselineAnalysis("func render() { _ = UIScreen.main.bounds }")
    let two = await baselineAnalysis("func render() { _ = UIScreen.main.bounds; _ = UIScreen.main.bounds }")
    let document = BaselineDocument(findings: BaselineStore.entries(from: one.diagnostics))
    #expect(two.applying(baseline: document).diagnostics.count { $0.baselineState == .new } == 1)
    let url = temporaryFile(named: "occurrences.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try BaselineStore.update(findings: BaselineStore.entries(from: two.diagnostics), at: url)
    let written = try BaselineStore.load(from: url)
    #expect(written.schemaVersion == 2)
    #expect(written.findings.count == 1)
    #expect(written.findings.first?.occurrences == 2)
    #expect(BaselineStore.check(written, diagnostics: two.diagnostics).isEmpty)
    #expect(BaselineStore.check(written, diagnostics: one.diagnostics).contains { $0.kind == .stale })
}

@Test("Legacy migration preserves only unique accepted findings and refuses ambiguity")
func legacyMigrationIsConservative() async throws {
    let first = await baselineAnalysis("func first() { _ = UIScreen.main.bounds }")
    let old = BaselineDocument(schemaVersion: 1, findings: first.diagnostics.map(BaselineStore.legacyEntry))
    let migrated = try BaselineStore.migrate(old, current: first.diagnostics)
    #expect(migrated.schemaVersion == 2)
    #expect(!first.applying(baseline: migrated).reachesFailureThreshold(.error))
    let added = await baselineAnalysis("func first() { _ = UIScreen.main.bounds }; func second() { _ = UIScreen.main.bounds }")
    #expect(added.applying(baseline: old).diagnostics.allSatisfy { $0.baselineState == .new })
    #expect(throws: BaselineError.self) { try BaselineStore.migrate(old, current: added.diagnostics) }
    #expect(throws: BaselineError.self) { try BaselineStore.migrate(old, current: []) }
}

@Test("The writer aggregates repeated identities rather than writing invalid duplicates")
func baselineWriterAggregatesDuplicates() throws {
    let url = temporaryFile(named: "duplicates.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let entry = BaselineEntry(ruleID: "RL001", path: "View.swift", fingerprint: "sha256:fixture")
    try BaselineStore.create(findings: [entry, entry], at: url, force: false)
    let written = try BaselineStore.load(from: url)
    #expect(written.findings.first?.occurrences == 2)
    #expect(BaselineStore.check(written, current: written.findings).isEmpty)
}

private func baselineAnalysis(_ source: String) async -> AnalysisResult {
    await ResizeAnalyzer().analyze(AnalysisRequest(files: [SourceInput(path: "View.swift", contents: source)]))
}
