import Foundation
import Yams

public enum ConfigurationError: Error, Equatable, CustomStringConvertible {
    case invalidYAML(String)
    case unknownKey(String)
    case unsupportedVersion(Int)
    case fileTooLarge(Int)

    public var description: String {
        switch self {
        case let .invalidYAML(message): "Invalid configuration: \(message)"
        case let .unknownKey(key): "Unknown configuration key: \(key)"
        case let .unsupportedVersion(version): "Unsupported configuration version: \(version)"
        case let .fileTooLarge(bytes): "Configuration exceeds the 1 MiB limit (\(bytes) bytes)"
        }
    }
}

public enum ConfigurationLoader {
    private static let maximumBytes = 1_048_576

    public static func load(at url: URL) throws -> ResizeLintConfiguration {
        try decode(try source(at: url))
    }

    public static func resolve(
        repositoryAt repositoryURL: URL?,
        nearestAt nearestURL: URL?,
        cli: ConfigurationOverrides
    ) throws -> ResizeLintConfiguration {
        var result = ResizeLintConfiguration()
        if let repositoryURL {
            result = try decodeWire(try source(at: repositoryURL)).applying(to: result)
        }
        if let nearestURL {
            result = try decodeWire(try source(at: nearestURL)).applying(to: result)
        }
        return ResizeLintConfiguration.resolve(repository: result, nearest: nil, cli: cli)
    }

    private static func source(at url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let bytes = values.fileSize, bytes > maximumBytes {
            throw ConfigurationError.fileTooLarge(bytes)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else { throw ConfigurationError.fileTooLarge(data.count) }
        guard let source = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.invalidYAML("Configuration is not UTF-8")
        }
        return source
    }

    public static func decode(_ yaml: String) throws -> ResizeLintConfiguration {
        try decodeWire(yaml).configuration
    }

    private static func decodeWire(_ yaml: String) throws -> ConfigurationWire {
        do {
            let object = try Yams.load(yaml: yaml)
            try validateKeys(object)
            let wire = try YAMLDecoder().decode(ConfigurationWire.self, from: yaml)
            guard wire.version == 1 else { throw ConfigurationError.unsupportedVersion(wire.version) }
            if let jobs = wire.jobs, jobs < 1 {
                throw ConfigurationError.invalidYAML("jobs must be positive")
            }
            return wire
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.invalidYAML(String(describing: error))
        }
    }

    private static func validateKeys(_ object: Any?) throws {
        guard let mapping = object as? [String: Any] else {
            throw ConfigurationError.invalidYAML("The root must be a mapping")
        }
        let topLevel = Set(["version", "include", "exclude", "baseline", "fail_on", "rules", "overrides", "jobs"])
        for key in mapping.keys where !topLevel.contains(key) { throw ConfigurationError.unknownKey(key) }

        if let rules = mapping["rules"] as? [String: Any] {
            for (ruleID, value) in rules {
                try validateRuleID(ruleID, prefix: "rules")
                try validateRule(value, prefix: "rules.\(ruleID)")
            }
        }
        if let overrides = mapping["overrides"] as? [[String: Any]] {
            for (index, override) in overrides.enumerated() {
                for key in override.keys where !["files", "rules"].contains(key) {
                    throw ConfigurationError.unknownKey("overrides[\(index)].\(key)")
                }
                if let rules = override["rules"] as? [String: Any] {
                    for (ruleID, value) in rules {
                        try validateRuleID(ruleID, prefix: "overrides[\(index)].rules")
                        try validateRule(value, prefix: "overrides[\(index)].rules.\(ruleID)")
                    }
                }
            }
        }
    }

    private static func validateRule(_ value: Any, prefix: String) throws {
        guard let mapping = value as? [String: Any] else {
            throw ConfigurationError.invalidYAML("\(prefix) must be a mapping")
        }
        for key in mapping.keys where !["enabled", "severity"].contains(key) {
            throw ConfigurationError.unknownKey("\(prefix).\(key)")
        }
    }

    private static func validateRuleID(_ ruleID: String, prefix: String) throws {
        guard RuleCatalog.all.contains(where: { $0.id == ruleID }) else {
            throw ConfigurationError.unknownKey("\(prefix).\(ruleID)")
        }
    }
}

private struct ConfigurationWire: Decodable {
    let version: Int
    var include: [String]?
    var exclude: [String]?
    var baseline: String?
    var failOn: Severity?
    var rules: [String: RuleConfiguration]?
    var overrides: [FileOverride]?
    var jobs: Int?

    enum CodingKeys: String, CodingKey {
        case version, include, exclude, baseline, rules, overrides, jobs
        case failOn = "fail_on"
    }

    var configuration: ResizeLintConfiguration {
        applying(to: ResizeLintConfiguration())
    }

    func applying(to base: ResizeLintConfiguration) -> ResizeLintConfiguration {
        var mergedRules = base.rules
        for (ruleID, configuration) in rules ?? [:] {
            mergedRules[ruleID] = mergedRules[ruleID]?.merging(configuration) ?? configuration
        }
        return ResizeLintConfiguration(
            version: version,
            include: include ?? base.include,
            exclude: exclude ?? base.exclude,
            baseline: baseline ?? base.baseline,
            failOn: failOn ?? base.failOn,
            rules: mergedRules,
            overrides: base.overrides + (overrides ?? []),
            jobs: jobs ?? base.jobs
        )
    }
}
