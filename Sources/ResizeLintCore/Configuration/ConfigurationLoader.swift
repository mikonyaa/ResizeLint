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
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else { throw ConfigurationError.fileTooLarge(data.count) }
        guard let source = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.invalidYAML("Configuration is not UTF-8")
        }
        return try decode(source)
    }

    public static func decode(_ yaml: String) throws -> ResizeLintConfiguration {
        do {
            let object = try Yams.load(yaml: yaml)
            try validateKeys(object)
            let wire = try YAMLDecoder().decode(ConfigurationWire.self, from: yaml)
            guard wire.version == 1 else { throw ConfigurationError.unsupportedVersion(wire.version) }
            return wire.configuration
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
        let defaults = ResizeLintConfiguration()
        return ResizeLintConfiguration(
            version: version,
            include: include ?? defaults.include,
            exclude: exclude ?? defaults.exclude,
            baseline: baseline ?? defaults.baseline,
            failOn: failOn ?? defaults.failOn,
            rules: rules ?? [:],
            overrides: overrides ?? [],
            jobs: jobs ?? defaults.jobs
        )
    }
}
