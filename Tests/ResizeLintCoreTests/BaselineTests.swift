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
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 10 * 1_048_576 + 1)
    try handle.close()
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }

    #expect(throws: BaselineError.self) {
        try BaselineStore.load(from: url)
    }
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
