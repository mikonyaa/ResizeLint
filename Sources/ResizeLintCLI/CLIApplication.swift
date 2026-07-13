import Foundation
import ResizeLintCore

enum CLIOperation: Sendable {
    case lint
    case fix(dryRun: Bool)
    case baselineCreate(force: Bool)
    case baselineUpdate
    case baselineCheck
    case rules
    case initialize(force: Bool)
    case version
}

struct CLIInvocation: Sendable {
    var operation: CLIOperation
    var paths: [String] = []
    var config: String?
    var baseline: String?
    var format: ReportFormat? = .human
    var output: String?
    var failOn: Severity?
    var strict = false
    var jobs: Int?
    var noColor = false
    var quiet = false
    var verbose = false

    init(operation: CLIOperation, paths: [String] = []) {
        self.operation = operation
        self.paths = paths
    }
}

private enum CLIUserError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self { case let .message(message): message }
    }
}

enum CLIApplication {
    static func run(arguments: [String], currentDirectory: URL) async -> CLIResult {
        do {
            let invocation = try parse(arguments)
            return await run(invocation: invocation, currentDirectory: currentDirectory)
        } catch {
            return CLIResult(
                exitCode: 2,
                standardOutput: "",
                standardError: TerminalEscaping.escape("\(error)") + "\n"
            )
        }
    }

    static func run(invocation: CLIInvocation, currentDirectory: URL) async -> CLIResult {
        do {
            switch invocation.operation {
            case .version:
                return CLIResult(exitCode: 0, standardOutput: "\(ResizeLintVersion.current)\n", standardError: "")
            case .rules:
                let output = ResizeLintRules.all.map {
                    "\($0.id)  \($0.severity.rawValue)  \($0.name)\n    \($0.message)"
                }.joined(separator: "\n") + "\n"
                return CLIResult(exitCode: 0, standardOutput: output, standardError: "")
            case let .initialize(force):
                return try initialize(force: force, root: currentDirectory)
            case .lint, .fix, .baselineCreate, .baselineUpdate, .baselineCheck:
                return try await runProject(invocation, currentDirectory: currentDirectory)
            }
        } catch let error as ConfigurationError {
            return invalid(error)
        } catch let error as DiscoveryError {
            return invalid(error)
        } catch let error as BaselineError {
            return invalid(error)
        } catch let error as CLIUserError {
            return invalid(error)
        } catch let error as ScanError {
            return operational("\(error)")
        } catch is CancellationError {
            return CLIResult(exitCode: 3, standardOutput: "", standardError: "Analysis cancelled.\n")
        } catch {
            return operational("Operational failure: \(error)")
        }
    }

    private static func runProject(_ invocation: CLIInvocation, currentDirectory: URL) async throws -> CLIResult {
        let root = projectRoot(from: currentDirectory)
        let configuration = try loadConfiguration(invocation, root: root, currentDirectory: currentDirectory)
        let pathStrings = invocation.paths.isEmpty ? ["."] : invocation.paths
        let urls = pathStrings.map { resolve($0, relativeTo: currentDirectory) }
        let start = ContinuousClock.now
        var result = try await ProjectScanner.scan(paths: urls, root: root, configuration: configuration)
        let elapsed = start.duration(to: .now)
        let duration = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        switch invocation.operation {
        case let .baselineCreate(force):
            let url = try baselineURL(invocation, configuration: configuration, root: root)
            try BaselineStore.create(findings: BaselineStore.entries(from: result.diagnostics), at: url, force: force)
            return CLIResult(
                exitCode: 0,
                standardOutput: "Created \(TerminalEscaping.escape(relative(url, root: root))).\n",
                standardError: notices(result, verbose: invocation.verbose)
            )
        case .baselineUpdate:
            let url = try baselineURL(invocation, configuration: configuration, root: root)
            try BaselineStore.update(findings: BaselineStore.entries(from: result.diagnostics), at: url)
            return CLIResult(
                exitCode: 0,
                standardOutput: "Updated \(TerminalEscaping.escape(relative(url, root: root))).\n",
                standardError: notices(result, verbose: invocation.verbose)
            )
        case .baselineCheck:
            let url = try baselineURL(invocation, configuration: configuration, root: root)
            let document = try BaselineStore.load(from: url)
            let issues = BaselineStore.check(document, current: BaselineStore.entries(from: result.diagnostics))
            let output = issues.isEmpty
                ? "Baseline is current.\n"
                : issues.map {
                    "\($0.kind.rawValue): \(TerminalEscaping.escape($0.entry.ruleID)) \(TerminalEscaping.escape($0.entry.path))"
                }.joined(separator: "\n") + "\n"
            return CLIResult(exitCode: issues.isEmpty ? 0 : 1, standardOutput: output, standardError: notices(result, verbose: invocation.verbose))
        case let .fix(dryRun):
            return try await fix(
                result: result,
                dryRun: dryRun,
                invocation: invocation,
                configuration: configuration,
                root: root,
                outputBase: currentDirectory,
                urls: urls,
                paths: pathStrings,
                duration: duration
            )
        case .lint:
            if let baseline = try loadBaselineIfPresent(invocation, configuration: configuration, root: root) {
                result = result.applying(baseline: baseline)
            }
            return try report(
                result: result,
                invocation: invocation,
                configuration: configuration,
                root: root,
                outputBase: currentDirectory,
                command: "lint",
                paths: pathStrings,
                duration: duration
            )
        case .rules, .initialize, .version:
            throw CLIUserError.message("Unsupported project operation")
        }
    }

    private static func fix(
        result: AnalysisResult,
        dryRun: Bool,
        invocation: CLIInvocation,
        configuration: ResizeLintConfiguration,
        root: URL,
        outputBase: URL,
        urls: [URL],
        paths: [String],
        duration: Double
    ) async throws -> CLIResult {
        let editsByPath = Dictionary(grouping: result.diagnostics.compactMap(\.fix), by: \.path)
        var diffs = ""
        for path in editsByPath.keys.sorted() {
            guard let edits = editsByPath[path] else { continue }
            let url = try resolveInsideRoot(path, relativeTo: root, root: root)
            let source = try String(contentsOf: url, encoding: .utf8)
            if dryRun {
                diffs += try FixEngine.preview(source: source, edits: edits, path: path).unifiedDiff
            } else {
                try FixEngine.writeAtomically(source: source, edits: edits, to: url)
            }
        }
        if dryRun {
            return CLIResult(exitCode: 0, standardOutput: invocation.quiet ? "" : diffs, standardError: notices(result, verbose: invocation.verbose))
        }
        var rescanned = try await ProjectScanner.scan(paths: urls, root: root, configuration: configuration)
        if let baseline = try loadBaselineIfPresent(invocation, configuration: configuration, root: root) {
            rescanned = rescanned.applying(baseline: baseline)
        }
        return try report(
            result: rescanned,
            invocation: invocation,
            configuration: configuration,
            root: root,
            outputBase: outputBase,
            command: "fix",
            paths: paths,
            duration: duration
        )
    }

    private static func report(
        result: AnalysisResult,
        invocation: CLIInvocation,
        configuration: ResizeLintConfiguration,
        root: URL,
        outputBase: URL,
        command: String,
        paths: [String],
        duration: Double
    ) throws -> CLIResult {
        guard let format = invocation.format else { throw CLIUserError.message("Invalid report format") }
        let output = try Reporter.render(
            format: format,
            result: result,
            context: ReportContext(command: command, paths: paths, durationSeconds: duration),
            color: !invocation.noColor && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        )
        var standardOutput = invocation.quiet ? "" : output
        if let path = invocation.output {
            let url = try resolveInsideRoot(path, relativeTo: outputBase, root: root)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(output.utf8).write(to: url, options: .atomic)
            standardOutput = ""
        }
        let threshold = invocation.strict ? Severity.warning : (invocation.failOn ?? configuration.failOn)
        return CLIResult(
            exitCode: result.reachesFailureThreshold(threshold) ? 1 : 0,
            standardOutput: standardOutput,
            standardError: notices(result, verbose: invocation.verbose)
        )
    }

    private static func loadConfiguration(
        _ invocation: CLIInvocation,
        root: URL,
        currentDirectory: URL
    ) throws -> ResizeLintConfiguration {
        let repositoryURL = root.appending(path: ".resizelint.yml")
        let cli = ConfigurationOverrides(failOn: invocation.failOn, strict: invocation.strict, jobs: invocation.jobs)
        if let explicit = invocation.config {
            let url = try resolveInsideRoot(explicit, relativeTo: currentDirectory, root: root)
            return ResizeLintConfiguration.resolve(
                repository: try ConfigurationLoader.load(at: url),
                nearest: nil,
                cli: cli
            )
        }
        let repository = FileManager.default.fileExists(atPath: repositoryURL.path) ? repositoryURL : nil
        return try ConfigurationLoader.resolve(
            repositoryAt: repository,
            nearestAt: nearestConfiguration(from: currentDirectory, stoppingAt: root),
            cli: cli
        )
    }

    private static func loadBaselineIfPresent(
        _ invocation: CLIInvocation,
        configuration: ResizeLintConfiguration,
        root: URL
    ) throws -> BaselineDocument? {
        let url = try baselineURL(invocation, configuration: configuration, root: root)
        if FileManager.default.fileExists(atPath: url.path) { return try BaselineStore.load(from: url) }
        if invocation.baseline != nil { throw CLIUserError.message("Baseline not found: \(relative(url, root: root))") }
        return nil
    }

    private static func baselineURL(
        _ invocation: CLIInvocation,
        configuration: ResizeLintConfiguration,
        root: URL
    ) throws -> URL {
        try resolveInsideRoot(invocation.baseline ?? configuration.baseline, relativeTo: root, root: root)
    }

    private static func initialize(force: Bool, root: URL) throws -> CLIResult {
        let url = root.appending(path: ".resizelint.yml")
        if FileManager.default.fileExists(atPath: url.path), !force {
            throw CLIUserError.message(".resizelint.yml already exists")
        }
        let starter = """
        version: 1

        include:
          - "**/*.swift"
          - "**/Info.plist"
          - "**/*.xcodeproj/project.pbxproj"

        exclude:
          - ".git/**"
          - ".build/**"
          - "DerivedData/**"
          - "Pods/**"
          - "Carthage/**"
          - "**/Generated/**"

        baseline: ".resizelint-baseline.json"
        fail_on: error
        rules: {}
        overrides: []
        """ + "\n"
        try Data(starter.utf8).write(to: url, options: .atomic)
        return CLIResult(exitCode: 0, standardOutput: "Created .resizelint.yml.\n", standardError: "")
    }

    private static func notices(_ result: AnalysisResult, verbose: Bool) -> String {
        let visible = result.notices.filter { verbose || $0.kind == .malformedSuppression || $0.kind == .unreadableFile }
        return visible.map {
            "\(TerminalEscaping.escape($0.path)): \(TerminalEscaping.escape($0.message))"
        }.joined(separator: "\n") + (visible.isEmpty ? "" : "\n")
    }

    private static func invalid(_ error: Error) -> CLIResult {
        CLIResult(
            exitCode: 2,
            standardOutput: "",
            standardError: TerminalEscaping.escape("\(error)") + "\n"
        )
    }

    private static func operational(_ message: String) -> CLIResult {
        CLIResult(
            exitCode: 3,
            standardOutput: "",
            standardError: TerminalEscaping.escape(message) + "\n"
        )
    }

    private static func resolve(_ path: String, relativeTo root: URL) -> URL {
        if path.hasPrefix("/") { return URL(filePath: path).standardizedFileURL }
        return root.appending(path: path).standardizedFileURL
    }

    private static func resolveInsideRoot(_ path: String, relativeTo base: URL, root: URL) throws -> URL {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = resolve(path, relativeTo: base)
        guard !containsSymbolicLink(candidate, stoppingAt: root.standardizedFileURL) else {
            throw CLIUserError.message("Symbolic-link destinations are not allowed: \(path)")
        }
        let resolved = resolvingExistingAncestors(of: candidate)
        let prefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard resolved.path == canonicalRoot.path || resolved.path.hasPrefix(prefix) else {
            throw CLIUserError.message("Path escapes the project root: \(path)")
        }
        return candidate
    }

    private static func projectRoot(from currentDirectory: URL) -> URL {
        let original = currentDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var candidate = original
        while true {
            if FileManager.default.fileExists(atPath: candidate.appending(path: ".git").path) {
                return candidate
            }
            if candidate.path == "/" { return original }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { return original }
            candidate = parent
        }
    }

    private static func nearestConfiguration(from currentDirectory: URL, stoppingAt root: URL) -> URL? {
        var candidate = currentDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        while candidate.path != canonicalRoot.path {
            let configuration = candidate.appending(path: ".resizelint.yml")
            if FileManager.default.fileExists(atPath: configuration.path) {
                return configuration
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { return nil }
            candidate = parent
        }
        return nil
    }

    private static func containsSymbolicLink(_ url: URL, stoppingAt root: URL) -> Bool {
        var current = url.standardizedFileURL
        let stop = root.standardizedFileURL.path
        while current.path != stop, current.path != "/" {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                return true
            }
            current.deleteLastPathComponent()
        }
        return false
    }

    private static func resolvingExistingAncestors(of url: URL) -> URL {
        var ancestor = url
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in missingComponents.reversed() {
            resolved.append(path: component)
        }
        return resolved.standardizedFileURL
    }

    private static func relative(_ url: URL, root: URL) -> String {
        let prefix = root.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
            ? String(url.standardizedFileURL.path.dropFirst(prefix.count))
            : url.lastPathComponent
    }

    private static func parse(_ rawArguments: [String]) throws -> CLIInvocation {
        var arguments = rawArguments
        var operation: CLIOperation = .lint
        if let first = arguments.first, !first.hasPrefix("-") {
            switch first {
            case "lint": operation = .lint; arguments.removeFirst()
            case "fix": operation = .fix(dryRun: false); arguments.removeFirst()
            case "rules": operation = .rules; arguments.removeFirst()
            case "init": operation = .initialize(force: false); arguments.removeFirst()
            case "version": operation = .version; arguments.removeFirst()
            case "baseline":
                arguments.removeFirst()
                guard let action = arguments.first else { throw CLIUserError.message("Missing baseline action") }
                arguments.removeFirst()
                switch action {
                case "create": operation = .baselineCreate(force: false)
                case "update": operation = .baselineUpdate
                case "check": operation = .baselineCheck
                default: throw CLIUserError.message("Unknown baseline action: \(action)")
                }
            default:
                operation = .lint
            }
        }

        var invocation = CLIInvocation(operation: operation)
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func value() throws -> String {
                guard index + 1 < arguments.count else { throw CLIUserError.message("Missing value for \(argument)") }
                index += 1
                return arguments[index]
            }
            switch argument {
            case "--config": invocation.config = try value()
            case "--baseline": invocation.baseline = try value()
            case "--format": invocation.format = ReportFormat(rawValue: try value())
            case "--output": invocation.output = try value()
            case "--fail-on": invocation.failOn = Severity(rawValue: try value())
            case "--jobs":
                guard let jobs = Int(try value()), jobs > 0 else { throw CLIUserError.message("--jobs must be positive") }
                invocation.jobs = jobs
            case "--strict": invocation.strict = true
            case "--no-color": invocation.noColor = true
            case "--quiet": invocation.quiet = true
            case "--verbose": invocation.verbose = true
            case "--dry-run": invocation.operation = .fix(dryRun: true)
            case "--force":
                switch invocation.operation {
                case .baselineCreate: invocation.operation = .baselineCreate(force: true)
                case .initialize: invocation.operation = .initialize(force: true)
                default: throw CLIUserError.message("--force is not valid for this command")
                }
            default:
                if argument.hasPrefix("-") { throw CLIUserError.message("Unknown option: \(argument)") }
                invocation.paths.append(argument)
            }
            index += 1
        }
        if invocation.format == nil { throw CLIUserError.message("Invalid report format") }
        if rawArguments.contains("--fail-on"), invocation.failOn == nil { throw CLIUserError.message("Invalid failure threshold") }
        return invocation
    }
}
