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
    let diagnostic = makeDiagnostic(path: macHomePrefix + "example/PrivateProject/View.swift")
    let result = AnalysisResult(diagnostics: [diagnostic], notices: [], filesAnalyzed: 1)
    let output = try Reporter.render(format: .json, result: result, context: reportContext)
    #expect(output.contains(macHomePrefix) == false)
    #expect(output.contains("View.swift"))
}

@Test("Machine reporters sanitize absolute invocation paths")
func reporterInvocationPrivacy() throws {
    let context = ReportContext(
        command: "lint",
        paths: [macHomePrefix + "example/PrivateProject"],
        durationSeconds: 0.25
    )

    let output = try Reporter.render(format: .json, result: reportResult, context: context)

    #expect(output.contains(macHomePrefix) == false)
    #expect(output.contains("PrivateProject"))
}

@Test("Terminal reporters neutralize control characters")
func terminalReporterEscaping() throws {
    let diagnostic = Diagnostic(
        ruleID: "RL002",
        ruleName: "main-screen-scale",
        severity: .warning,
        message: "Warning\u{1B}[31m\nforged",
        path: "Sources/Bad\u{1B}[2J\nInjected.swift",
        range: SourceRange(
            start: SourceLocation(line: 1, column: 1),
            end: SourceLocation(line: 1, column: 2),
            utf8Offset: 0,
            utf8Length: 1
        ),
        helpURI: "https://example.invalid/rule",
        fingerprint: "sha256:control"
    )
    let result = AnalysisResult(diagnostics: [diagnostic], notices: [], filesAnalyzed: 1)

    let human = try Reporter.render(format: .human, result: result, context: reportContext)
    let xcode = try Reporter.render(format: .xcode, result: result, context: reportContext)

    #expect(human.unicodeScalars.contains { $0.value == 0x1B } == false)
    #expect(xcode.unicodeScalars.contains { $0.value == 0x1B } == false)
    #expect(human.contains("Bad\\u{001B}[2J\\nInjected.swift"))
    #expect(xcode.contains("Warning\\u{001B}[31m\\nforged"))
}

@Test("JSON and SARIF encode control characters without raw injection")
func machineReporterEscaping() throws {
    let diagnostic = makeDiagnostic(path: "Sources/Bad\u{1B}\n.swift")
    let result = AnalysisResult(diagnostics: [diagnostic], notices: [], filesAnalyzed: 1)

    for format in [ReportFormat.json, .sarif] {
        let output = try Reporter.render(format: format, result: result, context: reportContext)
        #expect(output.unicodeScalars.contains { $0.value == 0x1B } == false)
        let object = try JSONSerialization.jsonObject(with: #require(output.data(using: .utf8)))
        if format == .sarif {
            let document = try #require(object as? [String: Any])
            let runs = try #require(document["runs"] as? [[String: Any]])
            let results = try #require(runs.first?["results"] as? [[String: Any]])
            let locations = try #require(results.first?["locations"] as? [[String: Any]])
            let physical = try #require(locations.first?["physicalLocation"] as? [String: Any])
            let artifact = try #require(physical["artifactLocation"] as? [String: Any])
            let uri = try #require(artifact["uri"] as? String)
            #expect(uri == "Sources/Bad%1B%0A.swift")
        } else {
            #expect(output.contains("\\u001B") || output.contains("\\u001b"))
        }
    }
}

private let reportContext = ReportContext(
    command: "lint",
    paths: ["."],
    durationSeconds: 0.25
)

private let macHomePrefix = "/" + "Users/"

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
