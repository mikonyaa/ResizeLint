import Foundation
import Testing
@testable import ResizeLintCore

@Test("RL001 specification") func rl001Specification() async throws { try await assertRuleFixture("RL001") }
@Test("RL002 specification") func rl002Specification() async throws { try await assertRuleFixture("RL002") }
@Test("RL003 specification") func rl003Specification() async throws { try await assertRuleFixture("RL003") }
@Test("RL004 specification") func rl004Specification() async throws { try await assertRuleFixture("RL004") }
@Test("RL005 specification") func rl005Specification() async throws { try await assertRuleFixture("RL005") }
@Test("RL006 specification") func rl006Specification() async throws { try await assertRuleFixture("RL006") }
@Test("RL007 specification") func rl007Specification() async throws { try await assertRuleFixture("RL007") }
@Test("RL008 specification") func rl008Specification() async throws { try await assertRuleFixture("RL008") }
@Test("RL009 specification") func rl009Specification() async throws { try await assertRuleFixture("RL009") }

private struct RuleFixture: Decodable {
    struct Expected: Decodable {
        let severity: Severity
        let messageContains: String
        let count: Int
    }

    let ruleID: String
    let positive: String
    let adaptiveNegative: String
    let commentsAndStrings: String
    let multiline: String
    let conditional: String
    let suppression: String
    let projectFiles: [String: String]?
    let expected: Expected
}

private func assertRuleFixture(_ ruleID: String) async throws {
    let fixture = try loadFixture(ruleID)
    let analyzer = ResizeAnalyzer()

    let positive = await analyzer.analyze(request(for: fixture, source: fixture.positive))
    let adaptive = await analyzer.analyze(request(for: fixture, source: fixture.adaptiveNegative))
    let comments = await analyzer.analyze(request(for: fixture, source: fixture.commentsAndStrings))
    let multiline = await analyzer.analyze(request(for: fixture, source: fixture.multiline))
    let conditional = await analyzer.analyze(request(for: fixture, source: fixture.conditional))
    let suppression = await analyzer.analyze(suppressedRequest(for: fixture))

    let positiveMatches = positive.diagnostics.filter { $0.ruleID == ruleID && !$0.isSuppressed }
    #expect(positiveMatches.count == fixture.expected.count)
    #expect(positiveMatches.first?.severity == fixture.expected.severity)
    #expect(positiveMatches.first?.message.localizedCaseInsensitiveContains(fixture.expected.messageContains) == true)
    #expect(adaptive.diagnostics.contains { $0.ruleID == ruleID && !$0.isSuppressed } == false)
    #expect(comments.diagnostics.contains { $0.ruleID == ruleID && !$0.isSuppressed } == false)
    #expect(multiline.diagnostics.contains { $0.ruleID == ruleID && !$0.isSuppressed })
    #expect(conditional.diagnostics.contains { $0.ruleID == ruleID && !$0.isSuppressed })
    if ruleID == "RL009" {
        #expect(suppression.diagnostics.contains { $0.ruleID == ruleID && !$0.isSuppressed } == false)
    } else {
        #expect(suppression.diagnostics.contains { $0.ruleID == ruleID && $0.isSuppressed })
    }
}

private func request(for fixture: RuleFixture, source: String) -> AnalysisRequest {
    var files = fixture.projectFiles?.map { SourceInput(path: $0.key, contents: $0.value) } ?? []
    let path: String
    switch fixture.ruleID {
    case "RL009": path = source.contains("<key>") ? "Info.plist" : "project.pbxproj"
    default: path = "Sources/Sample.swift"
    }
    files.append(SourceInput(path: path, contents: source))
    return AnalysisRequest(files: files)
}

private func suppressedRequest(for fixture: RuleFixture) -> AnalysisRequest {
    if fixture.ruleID == "RL009" {
        return AnalysisRequest(
            files: [SourceInput(path: "project.pbxproj", contents: fixture.positive)],
            configuration: ResizeLintConfiguration(
                rules: ["RL009": RuleConfiguration(enabled: false)]
            )
        )
    }
    return request(for: fixture, source: fixture.suppression)
}

private func loadFixture(_ ruleID: String) throws -> RuleFixture {
    let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let url = testsDirectory.appending(path: "Fixtures/Rules/\(ruleID)/cases.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(RuleFixture.self, from: data)
}
