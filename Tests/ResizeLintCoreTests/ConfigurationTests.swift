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
