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

private func temporaryFile(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "resizelint-baseline-\(UUID().uuidString)")
        .appending(path: name)
}
