import Foundation
import Testing
@testable import ResizeLintCore

@Test("RL002 offers a fix only when traitCollection is proven available")
func rl002SafeFixContext() async throws {
    let safe = """
    final class CanvasView: UIView {
        func render() {
            let scale = UIScreen.main.scale
        }
    }
    """
    let unsafe = "func render() { let scale = UIScreen.main.scale }"
    let native = "final class CanvasView: UIView { let scale = UIScreen.main.nativeScale }"

    let safeResult = await analyzeForFix(safe)
    let unsafeResult = await analyzeForFix(unsafe)
    let nativeResult = await analyzeForFix(native)

    let edit = try #require(safeResult.diagnostics.first { $0.ruleID == "RL002" }?.fix)
    #expect(edit.replacement == "traitCollection.displayScale")
    #expect(unsafeResult.diagnostics.first { $0.ruleID == "RL002" }?.fix == nil)
    #expect(nativeResult.diagnostics.first { $0.ruleID == "RL002" }?.fix == nil)
}

@Test("Overlapping edits are rejected")
func overlappingEditsAreRejected() {
    let edits = [
        SourceEdit(path: "A.swift", utf8Offset: 0, utf8Length: 4, replacement: "one"),
        SourceEdit(path: "A.swift", utf8Offset: 3, utf8Length: 2, replacement: "two"),
    ]
    #expect(throws: FixError.overlappingEdits) {
        try FixEngine.apply(edits: edits, to: "abcdef")
    }
}

@Test("Dry run returns a unified diff and never mutates the file")
func dryRunDoesNotMutate() throws {
    let source = "let scale = UIScreen.main.scale\n"
    let edit = SourceEdit(path: "View.swift", utf8Offset: 12, utf8Length: 19, replacement: "traitCollection.displayScale")
    let result = try FixEngine.preview(source: source, edits: [edit], path: "View.swift")

    #expect(result.updatedSource == "let scale = traitCollection.displayScale\n")
    #expect(result.unifiedDiff.contains("--- a/View.swift"))
    #expect(result.unifiedDiff.contains("+++ b/View.swift"))
    #expect(source == "let scale = UIScreen.main.scale\n")
}

@Test("Safe fixes are idempotent and the result reparses")
func fixesAreIdempotent() async throws {
    let source = "final class CanvasView: UIView { func render() { let scale = UIScreen.main.scale } }"
    let analyzed = await analyzeForFix(source)
    let edits = analyzed.diagnostics.compactMap(\.fix)
    let once = try FixEngine.apply(edits: edits, to: source)
    let secondAnalysis = await analyzeForFix(once)
    let twice = try FixEngine.apply(edits: secondAnalysis.diagnostics.compactMap(\.fix), to: once)

    #expect(once == twice)
    #expect(secondAnalysis.notices.contains { $0.kind == .syntaxError } == false)
    #expect(secondAnalysis.diagnostics.contains { $0.ruleID == "RL002" } == false)
}

@Test("Atomic writes preserve permissions and CRLF line endings")
func atomicWritePreservesMetadataAndLineEndings() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "resizelint-fix-metadata-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appending(path: "View.swift")
    let source = "let scale = UIScreen.main.scale\r\nlet value = 1\r\n"
    try Data(source.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
    let match = try #require(source.utf8.firstRange(of: Array("UIScreen.main.scale".utf8)))
    let offset = source.utf8.distance(from: source.utf8.startIndex, to: match.lowerBound)
    let edit = SourceEdit(
        path: "View.swift",
        utf8Offset: offset,
        utf8Length: "UIScreen.main.scale".utf8.count,
        replacement: "traitCollection.displayScale"
    )

    try FixEngine.writeAtomically(source: source, edits: [edit], to: url)

    let updated = try String(contentsOf: url, encoding: .utf8)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(updated == "let scale = traitCollection.displayScale\r\nlet value = 1\r\n")
    #expect(attributes[.posixPermissions] as? Int == 0o640)
}

@Test("A failed atomic write leaves the original file intact and no temporary file")
func failedAtomicWriteRollsBack() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "resizelint-fix-rollback-\(UUID().uuidString)")
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appending(path: "View.swift")
    let source = "let scale = UIScreen.main.scale\n"
    try Data(source.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    let edit = SourceEdit(
        path: "View.swift",
        utf8Offset: 12,
        utf8Length: 19,
        replacement: "traitCollection.displayScale"
    )

    #expect(throws: (any Error).self) {
        try FixEngine.writeAtomically(source: source, edits: [edit], to: url)
    }

    let original = try String(contentsOf: url, encoding: .utf8)
    let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(original == source)
    #expect(entries == ["View.swift"])
}

@Test("An interrupted replacement after the temporary write preserves the destination")
func interruptedReplacementPreservesDestination() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "resizelint-fix-interruption-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let destination = root.appending(path: "View.swift")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    try Data("sentinel".utf8).write(to: destination.appending(path: "sentinel.txt"))
    let source = "let scale = UIScreen.main.scale\n"
    let edit = SourceEdit(
        path: "View.swift",
        utf8Offset: 12,
        utf8Length: 19,
        replacement: "traitCollection.displayScale"
    )

    #expect(throws: (any Error).self) {
        try FixEngine.writeAtomically(source: source, edits: [edit], to: destination)
    }

    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "sentinel.txt").path))
    let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(entries == ["View.swift"])
}

@Test("Fixes refuse symbolic-link destinations")
func fixesRejectSymbolicLinkDestination() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "resizelint-fix-symlink-\(UUID().uuidString)")
    let outside = FileManager.default.temporaryDirectory.appending(path: "resizelint-fix-outside-\(UUID().uuidString).swift")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = "let scale = UIScreen.main.scale\n"
    try Data(source.utf8).write(to: outside)
    let link = root.appending(path: "View.swift")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    let edit = SourceEdit(
        path: "View.swift",
        utf8Offset: 12,
        utf8Length: 19,
        replacement: "traitCollection.displayScale"
    )

    #expect(throws: (any Error).self) {
        try FixEngine.writeAtomically(source: source, edits: [edit], to: link)
    }

    #expect(try String(contentsOf: outside, encoding: .utf8) == source)
    #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
}

private func analyzeForFix(_ source: String) async -> AnalysisResult {
    await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "Sources/View.swift", contents: source),
    ]))
}
