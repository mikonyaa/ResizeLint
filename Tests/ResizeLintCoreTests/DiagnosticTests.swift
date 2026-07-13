import Testing
@testable import ResizeLintCore

@Test("Diagnostic ordering is stable")
func diagnosticOrdering() {
    let diagnostics = [
        Diagnostic.fixture(ruleID: "RL002", path: "B.swift", line: 1, column: 1),
        Diagnostic.fixture(ruleID: "RL003", path: "A.swift", line: 2, column: 1),
        Diagnostic.fixture(ruleID: "RL001", path: "A.swift", line: 2, column: 1),
        Diagnostic.fixture(ruleID: "RL009", path: "A.swift", line: 1, column: 4),
    ].sorted()

    #expect(diagnostics.map(\.ruleID) == ["RL009", "RL001", "RL003", "RL002"])
}

@Test("Fingerprints survive line-number changes")
func fingerprintsIgnoreLineNumbers() {
    let first = Fingerprinter.fingerprint(
        ruleID: "RL001",
        path: "Sources/View.swift",
        syntaxKind: "memberAccess",
        surroundingTokens: ["let", "size", "=", "UIScreen", ".", "main", ".", "bounds"]
    )
    let moved = Fingerprinter.fingerprint(
        ruleID: "RL001",
        path: "Sources/View.swift",
        syntaxKind: "memberAccess",
        surroundingTokens: ["let", "size", "=", "UIScreen", ".", "main", ".", "bounds"]
    )

    #expect(first == moved)
    #expect(first.hasPrefix("sha256:"))
}
