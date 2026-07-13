import Foundation
import Testing
@testable import ResizeLintCore

@Test("Xcode reporter uses the documented one-line format")
func xcodeReporterFormat() throws {
    let output = try Reporter.render(
        format: .xcode,
        result: reportResult,
        context: reportContext
    )
    #expect(output == "Sources/View.swift:1:13: warning: [RL002] Use traitCollection.displayScale or a scene-local screen instead of the main screen scale.\n")
}

@Test("Human reporter includes actionable guidance and summary")
func humanReporterFormat() throws {
    let output = try Reporter.render(
        format: .human,
        result: reportResult,
        context: reportContext,
        color: false
    )
    #expect(output.contains("Sources/View.swift:1:13  warning  RL002"))
    #expect(output.contains("1 warning, 1 file analyzed in 0.25s"))
    #expect(output.contains("https://github.com/mikonyaa/ResizeLint/blob/v1/Docs/Rules/RL002.md"))
}

@Test("JSON reporter matches the versioned golden contract")
func jsonReporterGolden() throws {
    let output = try Reporter.render(format: .json, result: reportResult, context: reportContext)
    try expectJSON(output, equalsGolden: "report.json")
}

@Test("SARIF reporter matches the complete 2.1.0 golden contract")
func sarifReporterGolden() throws {
    let output = try Reporter.render(format: .sarif, result: reportResult, context: reportContext)
    try expectJSON(output, equalsGolden: "report.sarif")
}

@Test("Machine reporters never expose absolute home paths")
func reporterPathPrivacy() throws {
    let diagnostic = makeDiagnostic(path: "/Users/example/PrivateProject/View.swift")
    let result = AnalysisResult(diagnostics: [diagnostic], notices: [], filesAnalyzed: 1)
    let output = try Reporter.render(format: .json, result: result, context: reportContext)
    #expect(output.contains("/Users/") == false)
    #expect(output.contains("View.swift"))
}

private let reportContext = ReportContext(
    command: "lint",
    paths: ["."],
    durationSeconds: 0.25
)

private let reportResult = AnalysisResult(
    diagnostics: [makeDiagnostic(path: "Sources/View.swift")],
    notices: [],
    filesAnalyzed: 1
)

private func makeDiagnostic(path: String) -> Diagnostic {
    Diagnostic(
        ruleID: "RL002",
        ruleName: "main-screen-scale",
        severity: .warning,
        message: "Use traitCollection.displayScale or a scene-local screen instead of the main screen scale.",
        path: path,
        range: SourceRange(
            start: SourceLocation(line: 1, column: 13),
            end: SourceLocation(line: 1, column: 32),
            utf8Offset: 12,
            utf8Length: 19
        ),
        helpURI: "https://github.com/mikonyaa/ResizeLint/blob/v1/Docs/Rules/RL002.md",
        fingerprint: "sha256:fixture",
        baselineState: .absent
    )
}

private func expectJSON(_ actual: String, equalsGolden name: String) throws {
    let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let expectedData = try Data(contentsOf: testsDirectory.appending(path: "Golden/\(name)"))
    let actualData = try #require(actual.data(using: .utf8))
    let expected = try JSONSerialization.jsonObject(with: expectedData) as? NSDictionary
    let value = try JSONSerialization.jsonObject(with: actualData) as? NSDictionary
    #expect(value == expected)
}
