import Foundation
import ResizeLintCore
import Testing
@testable import ResizeLintCLI

@Test("Version command prints the public version")
func versionCommand() async throws {
    let result = try await ResizeLintCommand.runForTesting(arguments: ["version"])

    #expect(result.exitCode == 0)
    #expect(result.standardOutput == "1.0.0\n")
    #expect(result.standardError.isEmpty)
}

@Test("No subcommand is equivalent to linting the working directory")
func defaultCommandLintsWorkingDirectory() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeCLI("let bounds = UIScreen.main.bounds", to: root.appending(path: "View.swift"))

    let result = try await ResizeLintCommand.runForTesting(arguments: [], currentDirectory: root)

    #expect(result.exitCode == 1)
    #expect(result.standardOutput.contains("RL001"))
}

@Test("Default error threshold does not fail on warnings, while strict does")
func warningThresholds() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeCLI("let screen = UIScreen.main", to: root.appending(path: "View.swift"))

    let normal = try await ResizeLintCommand.runForTesting(
        arguments: ["lint", ".", "--format", "xcode"],
        currentDirectory: root
    )
    let strict = try await ResizeLintCommand.runForTesting(
        arguments: ["lint", ".", "--format", "xcode", "--strict"],
        currentDirectory: root
    )

    #expect(normal.exitCode == 0)
    #expect(strict.exitCode == 1)
    #expect(strict.standardOutput.contains("warning: [RL003]"))
}

@Test("Invalid configuration maps to exit code 2")
func invalidConfigurationExitCode() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeCLI("version: 1\nfail_onn: warning\n", to: root.appending(path: ".resizelint.yml"))

    let result = try await ResizeLintCommand.runForTesting(arguments: ["lint", "."], currentDirectory: root)

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("Unknown configuration key"))
}

@Test("Rules command lists all stable rule IDs")
func rulesCommand() async throws {
    let result = try await ResizeLintCommand.runForTesting(arguments: ["rules"])
    for number in 1...9 {
        #expect(result.standardOutput.contains(String(format: "RL%03d", number)))
    }
}

@Test("Init writes a strict starter configuration and refuses overwrite")
func initCommand() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let created = try await ResizeLintCommand.runForTesting(arguments: ["init"], currentDirectory: root)
    let repeated = try await ResizeLintCommand.runForTesting(arguments: ["init"], currentDirectory: root)
    let contents = try String(contentsOf: root.appending(path: ".resizelint.yml"), encoding: .utf8)

    #expect(created.exitCode == 0)
    #expect(contents.contains("version: 1"))
    #expect(repeated.exitCode == 2)
}

@Test("Baseline create hides only exact existing fingerprints")
func baselineCreateAndLint() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeCLI("let bounds = UIScreen.main.bounds", to: root.appending(path: "View.swift"))

    let created = try await ResizeLintCommand.runForTesting(
        arguments: ["baseline", "create", ".", "--baseline", "baseline.json"],
        currentDirectory: root
    )
    let linted = try await ResizeLintCommand.runForTesting(
        arguments: ["lint", ".", "--baseline", "baseline.json"],
        currentDirectory: root
    )

    #expect(created.exitCode == 0)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "baseline.json").path))
    #expect(linted.exitCode == 0)
}

@Test("Fix dry-run is read-only and explicit fix is idempotent")
func fixCommandDryRunAndWrite() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appending(path: "View.swift")
    let source = "final class CanvasView: UIView { func render() { let scale = UIScreen.main.scale } }\n"
    try writeCLI(source, to: sourceURL)

    let preview = try await ResizeLintCommand.runForTesting(
        arguments: ["fix", "View.swift", "--dry-run"],
        currentDirectory: root
    )
    #expect(preview.standardOutput.contains("--- a/View.swift"))
    #expect(try String(contentsOf: sourceURL, encoding: .utf8) == source)

    let fixed = try await ResizeLintCommand.runForTesting(arguments: ["fix", "View.swift"], currentDirectory: root)
    let repeated = try await ResizeLintCommand.runForTesting(arguments: ["fix", "View.swift"], currentDirectory: root)
    let updated = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(fixed.exitCode == 0)
    #expect(repeated.exitCode == 0)
    #expect(updated.contains("traitCollection.displayScale"))
    #expect(updated.contains("UIScreen.main.scale") == false)
}

@Test("Output option writes the report instead of standard output")
func outputFile() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeCLI("let screen = UIScreen.main", to: root.appending(path: "View.swift"))

    let result = try await ResizeLintCommand.runForTesting(
        arguments: ["lint", ".", "--format", "json", "--output", "report.json"],
        currentDirectory: root
    )

    #expect(result.standardOutput.isEmpty)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "report.json").path))
}

@Test("Terminal errors neutralize control characters from arguments")
func terminalErrorEscaping() async throws {
    let result = try await ResizeLintCommand.runForTesting(arguments: ["--bad\u{1B}[31m\noption"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.unicodeScalars.contains { $0.value == 0x1B } == false)
    #expect(result.standardError.contains("--bad\\u{001B}[31m\\noption"))
}

@Test("Baseline writes cannot escape the project root")
func baselineWriteCannotEscapeRoot() async throws {
    let parent = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "Project")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeCLI("let bounds = UIScreen.main.bounds", to: root.appending(path: "View.swift"))
    let escaped = parent.appending(path: "outside.json")

    let result = try await ResizeLintCommand.runForTesting(
        arguments: ["baseline", "create", ".", "--baseline", "../outside.json"],
        currentDirectory: root
    )

    #expect(result.exitCode == 2)
    #expect(FileManager.default.fileExists(atPath: escaped.path) == false)
}

@Test("Report writes cannot traverse a symlinked parent outside the project root")
func reportWriteCannotEscapeThroughSymlink() async throws {
    let parent = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "Project")
    let outside = parent.appending(path: "Outside")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: root.appending(path: "Reports"), withDestinationURL: outside)
    try writeCLI("let screen = UIScreen.main", to: root.appending(path: "View.swift"))

    let result = try await ResizeLintCommand.runForTesting(
        arguments: ["lint", ".", "--format", "json", "--output", "Reports/report.json"],
        currentDirectory: root
    )

    #expect(result.exitCode == 2)
    #expect(FileManager.default.fileExists(atPath: outside.appending(path: "report.json").path) == false)
}

@Test("Baseline check output neutralizes control characters from the document")
func baselineCheckEscapesUntrustedPaths() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeCLI("let bounds = UIScreen.main.bounds", to: root.appending(path: "View.swift"))
    let baseline: [String: Any] = [
        "schemaVersion": 1,
        "toolVersion": "1.0.0",
        "findings": [[
            "ruleID": "RL001",
            "path": "Bad\u{1B}[31m\nInjected.swift",
            "fingerprint": "sha256:stale",
        ]],
    ]
    let data = try JSONSerialization.data(withJSONObject: baseline)
    try data.write(to: root.appending(path: "baseline.json"))

    let result = try await ResizeLintCommand.runForTesting(
        arguments: ["baseline", "check", ".", "--baseline", "baseline.json"],
        currentDirectory: root
    )

    #expect(result.exitCode == 1)
    #expect(result.standardOutput.unicodeScalars.contains { $0.value == 0x1B } == false)
    #expect(result.standardOutput.contains("Bad\\u{001B}[31m\\nInjected.swift"))
}

@Test("Nested invocation discovers the repository root and nearest configuration")
func nestedInvocationUsesRepositoryRootAndNearestConfiguration() async throws {
    let root = try cliTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
    let feature = root.appending(path: "Features/Gallery")
    try FileManager.default.createDirectory(at: feature, withIntermediateDirectories: true)
    try writeCLI("version: 1\nfail_on: info\njobs: 2\n", to: root.appending(path: ".resizelint.yml"))
    try writeCLI(
        "version: 1\nrules:\n  RL003:\n    severity: error\n",
        to: feature.appending(path: ".resizelint.yml")
    )
    try writeCLI("let screen = UIScreen.main", to: feature.appending(path: "View.swift"))

    let result = try await ResizeLintCommand.runForTesting(
        arguments: ["lint", ".", "--format", "xcode"],
        currentDirectory: feature
    )

    #expect(result.exitCode == 1)
    #expect(result.standardOutput.contains("Features/Gallery/View.swift"))
    #expect(result.standardOutput.contains("error: [RL003]"))
}

private func cliTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "resizelint-cli-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeCLI(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
