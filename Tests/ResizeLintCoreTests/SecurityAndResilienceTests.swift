import Foundation
import Testing
@testable import ResizeLintCore

@Test("Malformed YAML is rejected without crashing")
func malformedYAMLIsRejected() {
    #expect(throws: ConfigurationError.self) {
        try ConfigurationLoader.decode("version: 1\nrules: [\n")
    }
}

@Test("Oversized unreadable configurations are rejected from metadata before reading")
func oversizedConfigurationIsRejectedBeforeRead() throws {
    let root = try resilienceTemporaryDirectory(named: "oversized-config")
    defer { try? FileManager.default.removeItem(at: root) }
    let configuration = root.appending(path: ".resizelint.yml")
    FileManager.default.createFile(atPath: configuration.path, contents: nil)
    let handle = try FileHandle(forWritingTo: configuration)
    try handle.truncate(atOffset: 1_048_577)
    try handle.close()
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: configuration.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path) }

    do {
        _ = try ConfigurationLoader.load(at: configuration)
        Issue.record("Oversized configuration unexpectedly loaded")
    } catch let error as ConfigurationError {
        #expect(error == .fileTooLarge(1_048_577))
    } catch {
        Issue.record("Oversized configuration threw unexpected error: \(error)")
    }
}

@Test("Unknown rule IDs are rejected instead of silently doing nothing")
func unknownRuleIDsAreRejected() {
    #expect(throws: ConfigurationError.self) {
        try ConfigurationLoader.decode("""
        version: 1
        rules:
          RL999:
            enabled: false
        """)
    }
}

@Test("Malformed property lists produce an audit notice without crashing")
func malformedPropertyListIsTolerated() async {
    let result = await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "Info.plist", contents: "<plist><dict><key>Broken</dict>"),
    ]))

    #expect(result.diagnostics.isEmpty)
    #expect(result.notices.contains { $0.message.localizedCaseInsensitiveContains("property list") })
}

@Test("Very long lines and Unicode identifiers remain analyzable")
func longUnicodeLineIsAnalyzable() async {
    let prefix = "let cafe\u{301} = \"" + String(repeating: "x", count: 500_000) + "\"; "
    let result = await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "Sources/Unicode.swift", contents: prefix + "let bounds = UIScreen.main.bounds"),
    ]))

    let diagnostic = result.diagnostics.first { $0.ruleID == "RL001" }
    #expect(diagnostic != nil)
    #expect(diagnostic?.range.start.column == prefix.utf8.count + 14)
}

@Test("Parallel analysis is deterministic across repeated runs")
func repeatedAnalysisIsDeterministic() async {
    let files = (0..<64).reversed().map { index in
        SourceInput(
            path: String(format: "Sources/View%03d.swift", index),
            contents: "let bounds\(index) = UIScreen.main.bounds"
        )
    }
    let request = AnalysisRequest(files: files, configuration: ResizeLintConfiguration(jobs: 8))
    let first = await ResizeAnalyzer().analyze(request)

    for _ in 0..<5 {
        let repeated = await ResizeAnalyzer().analyze(request)
        #expect(repeated.diagnostics == first.diagnostics)
        #expect(repeated.notices == first.notices)
        #expect(repeated.filesAnalyzed == first.filesAnalyzed)
    }
}

@Test("A cancelled project scan stops with CancellationError")
func cancelledScanStops() async throws {
    let root = try resilienceTemporaryDirectory(named: "cancellation")
    defer { try? FileManager.default.removeItem(at: root) }
    try resilienceWrite("let bounds = UIScreen.main.bounds", to: root.appending(path: "View.swift"))

    let task = Task {
        try await Task.sleep(for: .milliseconds(20))
        return try await ProjectScanner.scan(
            paths: [root],
            root: root,
            configuration: ResizeLintConfiguration()
        )
    }
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Cancelled scan unexpectedly completed")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Cancelled scan threw unexpected error: \(error)")
    }
}

@Test("Oversized unreadable sources are rejected from metadata before reading")
func oversizedSourceIsRejectedBeforeRead() async throws {
    let root = try resilienceTemporaryDirectory(named: "oversized-source")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "Huge.swift")
    FileManager.default.createFile(atPath: source.path, contents: nil)
    let handle = try FileHandle(forWritingTo: source)
    try handle.truncate(atOffset: UInt64(ProjectScanner.maximumSourceBytes + 1))
    try handle.close()
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: source.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path) }

    do {
        _ = try await ProjectScanner.scan(
            paths: [source],
            root: root,
            configuration: ResizeLintConfiguration()
        )
        Issue.record("Oversized source unexpectedly completed")
    } catch let error as ScanError {
        #expect(error == .sourceTooLarge(path: "Huge.swift", bytes: ProjectScanner.maximumSourceBytes + 1))
    } catch {
        Issue.record("Oversized source threw unexpected error: \(error)")
    }
}

@Test("Unreadable source files become operational notices")
func unreadableSourceBecomesNotice() async throws {
    let root = try resilienceTemporaryDirectory(named: "unreadable-source")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "Unreadable.swift")
    try resilienceWrite("let bounds = UIScreen.main.bounds", to: source)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: source.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path) }

    let result = try await ProjectScanner.scan(
        paths: [source],
        root: root,
        configuration: ResizeLintConfiguration()
    )

    #expect(result.filesAnalyzed == 0)
    #expect(result.notices.contains { $0.kind == .unreadableFile && $0.path == "Unreadable.swift" })
}

@Test("Invalid UTF-8 source fails safely")
func invalidUTF8FailsSafely() async throws {
    let root = try resilienceTemporaryDirectory(named: "invalid-utf8")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "Invalid.swift")
    try Data([0xFF, 0xFE, 0xFD]).write(to: source)

    do {
        _ = try await ProjectScanner.scan(
            paths: [source],
            root: root,
            configuration: ResizeLintConfiguration()
        )
        Issue.record("Invalid UTF-8 source unexpectedly completed")
    } catch let error as ScanError {
        #expect(error == .invalidUTF8("Invalid.swift"))
    } catch {
        Issue.record("Invalid UTF-8 source threw unexpected error: \(error)")
    }
}

private func resilienceTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "resizelint-resilience-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func resilienceWrite(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
