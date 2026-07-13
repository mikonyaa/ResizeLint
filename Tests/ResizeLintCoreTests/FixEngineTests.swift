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

private func analyzeForFix(_ source: String) async -> AnalysisResult {
    await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "Sources/View.swift", contents: source),
    ]))
}
