import Foundation
import Testing
@testable import ResizeLintCore

@Test("Unknown configuration keys are rejected")
func rejectsUnknownConfigurationKeys() {
    let yaml = """
    version: 1
    fail_on: error
    fail_onn: warning
    """

    #expect(throws: ConfigurationError.self) {
        try ConfigurationLoader.decode(yaml)
    }
}

@Test("Configuration precedence is CLI, nearest file, repository file, defaults")
func mergesConfigurationPrecedence() throws {
    let repository = try ConfigurationLoader.decode("""
    version: 1
    fail_on: error
    rules:
      RL002:
        severity: info
    """)
    let nearest = try ConfigurationLoader.decode("""
    version: 1
    fail_on: warning
    rules:
      RL002:
        enabled: false
    """)
    let cli = ConfigurationOverrides(failOn: .info, strict: false, jobs: 3)

    let merged = ResizeLintConfiguration.resolve(
        repository: repository,
        nearest: nearest,
        cli: cli
    )

    #expect(merged.failOn == .info)
    #expect(merged.jobs == 3)
    #expect(merged.rules["RL002"]?.enabled == false)
    #expect(merged.rules["RL002"]?.severity == .info)
}

@Test("Strict mode raises the threshold to warnings")
func strictModeUsesWarningThreshold() {
    let merged = ResizeLintConfiguration.resolve(
        repository: nil,
        nearest: nil,
        cli: ConfigurationOverrides(failOn: nil, strict: true, jobs: nil)
    )

    #expect(merged.failOn == .warning)
}

@Test("Configuration jobs must be positive")
func configurationJobsMustBePositive() {
    #expect(throws: ConfigurationError.self) {
        try ConfigurationLoader.decode("version: 1\njobs: 0\n")
    }
}

@Test("Nearest configuration preserves repository fields it does not declare")
func layeredConfigurationPreservesRepositoryValues() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "resizelint-config-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repositoryURL = root.appending(path: "repository.yml")
    let nearestURL = root.appending(path: "nearest.yml")
    try "version: 1\nfail_on: info\njobs: 2\n".write(to: repositoryURL, atomically: true, encoding: .utf8)
    try "version: 1\nrules:\n  RL003:\n    severity: error\n".write(to: nearestURL, atomically: true, encoding: .utf8)

    let configuration = try ConfigurationLoader.resolve(
        repositoryAt: repositoryURL,
        nearestAt: nearestURL,
        cli: ConfigurationOverrides(failOn: nil, strict: false, jobs: nil)
    )

    #expect(configuration.failOn == .info)
    #expect(configuration.jobs == 2)
    #expect(configuration.rules["RL003"]?.severity == .error)
}
