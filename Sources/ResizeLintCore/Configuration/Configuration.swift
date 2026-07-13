import Foundation

public struct RuleConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var severity: Severity?

    public init(enabled: Bool? = nil, severity: Severity? = nil) {
        self.enabled = enabled
        self.severity = severity
    }

    func merging(_ newer: RuleConfiguration) -> RuleConfiguration {
        RuleConfiguration(
            enabled: newer.enabled ?? enabled,
            severity: newer.severity ?? severity
        )
    }
}

public struct FileOverride: Codable, Equatable, Sendable {
    public var files: [String]
    public var rules: [String: RuleConfiguration]

    public init(files: [String], rules: [String: RuleConfiguration]) {
        self.files = files
        self.rules = rules
    }
}

public struct ResizeLintConfiguration: Codable, Equatable, Sendable {
    public var version: Int
    public var include: [String]
    public var exclude: [String]
    public var baseline: String
    public var failOn: Severity
    public var rules: [String: RuleConfiguration]
    public var overrides: [FileOverride]
    public var jobs: Int

    public init(
        version: Int = 1,
        include: [String] = ["**/*.swift", "**/Info.plist", "**/*.xcodeproj/project.pbxproj"],
        exclude: [String] = [".git/**", ".build/**", "DerivedData/**", "Pods/**", "Carthage/**", "**/Generated/**"],
        baseline: String = ".resizelint-baseline.json",
        failOn: Severity = .error,
        rules: [String: RuleConfiguration] = [:],
        overrides: [FileOverride] = [],
        jobs: Int = ResizeLintConfiguration.defaultJobs
    ) {
        self.version = version
        self.include = include
        self.exclude = exclude
        self.baseline = baseline
        self.failOn = failOn
        self.rules = rules
        self.overrides = overrides
        self.jobs = max(1, jobs)
    }

    public static var defaultJobs: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 1), 8)
    }

    public func isRuleEnabled(_ ruleID: String, path: String) -> Bool {
        var value = rules[ruleID]?.enabled ?? true
        for override in overrides where override.files.contains(where: { Glob.matches(path, pattern: $0) }) {
            value = override.rules[ruleID]?.enabled ?? value
        }
        return value
    }

    public func severity(for ruleID: String, default defaultSeverity: Severity, path: String) -> Severity {
        var value = rules[ruleID]?.severity ?? defaultSeverity
        for override in overrides where override.files.contains(where: { Glob.matches(path, pattern: $0) }) {
            value = override.rules[ruleID]?.severity ?? value
        }
        return value
    }

    public static func resolve(
        repository: ResizeLintConfiguration?,
        nearest: ResizeLintConfiguration?,
        cli: ConfigurationOverrides
    ) -> ResizeLintConfiguration {
        var result = repository ?? ResizeLintConfiguration()
        if let nearest {
            result = result.merging(nearest)
        }
        if let failOn = cli.failOn { result.failOn = failOn }
        if cli.strict { result.failOn = .warning }
        if let jobs = cli.jobs { result.jobs = max(1, jobs) }
        return result
    }

    private func merging(_ newer: ResizeLintConfiguration) -> ResizeLintConfiguration {
        var mergedRules = rules
        for (ruleID, configuration) in newer.rules {
            mergedRules[ruleID] = mergedRules[ruleID]?.merging(configuration) ?? configuration
        }
        return ResizeLintConfiguration(
            version: newer.version,
            include: newer.include,
            exclude: newer.exclude,
            baseline: newer.baseline,
            failOn: newer.failOn,
            rules: mergedRules,
            overrides: overrides + newer.overrides,
            jobs: newer.jobs
        )
    }
}

public struct ConfigurationOverrides: Sendable {
    public let failOn: Severity?
    public let strict: Bool
    public let jobs: Int?

    public init(failOn: Severity?, strict: Bool, jobs: Int?) {
        self.failOn = failOn
        self.strict = strict
        self.jobs = jobs
    }
}

enum Glob {
    static func matches(_ path: String, pattern: String) -> Bool {
        let characters = Array(pattern)
        var expression = "^"
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "*", index + 1 < characters.count, characters[index + 1] == "*" {
                if index + 2 < characters.count, characters[index + 2] == "/" {
                    expression += "(?:.*/)?"
                    index += 3
                } else {
                    expression += ".*"
                    index += 2
                }
            } else if character == "*" {
                expression += "[^/]*"
                index += 1
            } else if character == "?" {
                expression += "[^/]"
                index += 1
            } else {
                expression += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }
        }
        expression += "$"
        return path.range(of: expression, options: .regularExpression) != nil
    }
}
