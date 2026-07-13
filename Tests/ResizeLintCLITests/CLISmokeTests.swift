import Testing
@testable import ResizeLintCLI

@Test("Version command prints the public version")
func versionCommand() throws {
    let result = try ResizeLintCommand.runForTesting(arguments: ["version"])

    #expect(result.exitCode == 0)
    #expect(result.standardOutput == "1.0.0\n")
    #expect(result.standardError.isEmpty)
}
