import Foundation
import Testing
@testable import ResizeLintCore

@Test("Discovery is deterministic and excludes build products")
func discoveryOrderingAndExclusions() throws {
    let root = try temporaryDirectory(named: "discovery")
    defer { try? FileManager.default.removeItem(at: root) }
    try write("let b = 2", to: root.appending(path: "Sources/B.swift"))
    try write("let a = 1", to: root.appending(path: "Sources/A.swift"))
    try write("let ignored = true", to: root.appending(path: ".build/Ignored.swift"))
    try write("<plist><dict></dict></plist>", to: root.appending(path: "Info.plist"))

    let files = try SourceDiscovery().discover(paths: [root], scanRoot: root)

    #expect(files.map(\.relativePath) == ["Info.plist", "Sources/A.swift", "Sources/B.swift"])
}

@Test("Discovery never follows a directory symlink outside the root")
func discoveryRejectsSymlinkEscape() throws {
    let root = try temporaryDirectory(named: "symlink-root")
    let outside = try temporaryDirectory(named: "symlink-outside")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try write("let escaped = UIScreen.main.bounds", to: outside.appending(path: "Escaped.swift"))
    try FileManager.default.createSymbolicLink(
        at: root.appending(path: "Linked"),
        withDestinationURL: outside
    )

    let files = try SourceDiscovery().discover(paths: [root], scanRoot: root)

    #expect(files.isEmpty)
}

@Test("Project scanner applies configured include and exclude globs")
func scannerAppliesConfiguredGlobs() async throws {
    let root = try temporaryDirectory(named: "configured-globs")
    defer { try? FileManager.default.removeItem(at: root) }
    try write("let included = UIScreen.main.bounds", to: root.appending(path: "Sources/Included.swift"))
    try write("let excluded = UIScreen.main.bounds", to: root.appending(path: "Examples/Legacy/Excluded.swift"))
    let configuration = ResizeLintConfiguration(
        include: ["**/*.swift"],
        exclude: ["Examples/Legacy/**"]
    )

    let result = try await ProjectScanner.scan(paths: [root], root: root, configuration: configuration)

    #expect(result.filesAnalyzed == 1)
    #expect(result.diagnostics.map(\.path) == ["Sources/Included.swift"])
}

private func temporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "resizelint-tests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
