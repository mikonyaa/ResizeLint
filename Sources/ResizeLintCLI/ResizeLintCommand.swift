import ArgumentParser
import Foundation
import ResizeLintCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

struct CLIResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

@main
struct ResizeLintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resizelint",
        abstract: "Find layout assumptions that break in resizable Swift apps.",
        subcommands: [LintCommand.self, FixCommand.self, BaselineCommand.self,
                      RulesCommand.self, InitCommand.self, VersionCommand.self],
        defaultSubcommand: LintCommand.self
    )

    static func main() async {
        let result = await evaluate(arguments: Array(CommandLine.arguments.dropFirst()),
                                    currentDirectory: URL(filePath: FileManager.default.currentDirectoryPath))
        if !result.standardOutput.isEmpty { FileHandle.standardOutput.write(Data(result.standardOutput.utf8)) }
        if !result.standardError.isEmpty { FileHandle.standardError.write(Data(result.standardError.utf8)) }
        #if canImport(Darwin)
        Darwin.exit(result.exitCode)
        #elseif canImport(Glibc)
        Glibc.exit(result.exitCode)
        #elseif canImport(Musl)
        Musl.exit(result.exitCode)
        #endif
    }

    static func runForTesting(
        arguments: [String],
        currentDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath)
    ) async throws -> CLIResult {
        await evaluate(arguments: arguments, currentDirectory: currentDirectory)
    }

    private static func evaluate(arguments: [String], currentDirectory: URL) async -> CLIResult {
        do {
            var command = try parseAsRoot(arguments)
            if let command = command as? any InvocationCommand {
                return await CLIApplication.run(invocation: command.invocation(), currentDirectory: currentDirectory)
            }
            try command.run()
            return CLIResult(exitCode: 0, standardOutput: "", standardError: "")
        } catch {
            let status = exitCode(for: error).rawValue
            var message = fullMessage(for: error, columns: 100)
            if status == 0 {
                return CLIResult(exitCode: 0, standardOutput: message + "\n", standardError: "")
            }
            let unsafeArguments = arguments.filter { $0 != TerminalEscaping.escape($0) }
            if !unsafeArguments.isEmpty {
                // Formatting can wrap inside an argument; never render that untrusted text as usage lines.
                message = "Invalid invocation containing control characters: "
                    + unsafeArguments.map(TerminalEscaping.escape).joined(separator: " ")
                    + "\nSee 'resizelint --help' for usage."
            }
            message = message.split(separator: "\n", omittingEmptySubsequences: false)
                .map { TerminalEscaping.escape(String($0)) }.joined(separator: "\n")
            return CLIResult(exitCode: status == 64 ? 2 : status,
                             standardOutput: "", standardError: message + "\n")
        }
    }
}

protocol InvocationCommand: AsyncParsableCommand {
    func invocation() -> CLIInvocation
}

extension InvocationCommand {
    mutating func run() async throws {
        let result = await CLIApplication.run(invocation: invocation(),
            currentDirectory: URL(filePath: FileManager.default.currentDirectoryPath))
        if !result.standardOutput.isEmpty { FileHandle.standardOutput.write(Data(result.standardOutput.utf8)) }
        if !result.standardError.isEmpty { FileHandle.standardError.write(Data(result.standardError.utf8)) }
        if result.exitCode != 0 { throw ExitCode(result.exitCode) }
    }
}

struct CommonOptions: ParsableArguments {
    @Option(name: .long, help: "Path to .resizelint.yml.") var config: String?
    @Option(name: .long, help: "Path to the baseline JSON file.") var baseline: String?
    @Option(name: .long, help: "Output format: human, xcode, json, or sarif.") var format = "human"
    @Option(name: .long, help: "Write the report to a file.") var output: String?
    @Option(name: .long, help: "Failure threshold: error, warning, or info.") var failOn: String?
    @Flag(name: .long, help: "Equivalent to --fail-on warning.") var strict = false
    @Option(name: .long, help: "Maximum concurrent parsing jobs (positive integer).") var jobs: Int?
    @Flag(name: .long, help: "Disable terminal color.") var noColor = false
    @Flag(name: .long, help: "Suppress normal output.") var quiet = false
    @Flag(name: .long, help: "Show operational audit notices.") var verbose = false

    mutating func validate() throws {
        guard ReportFormat(rawValue: format) != nil else { throw ValidationError("Invalid report format: \(format)") }
        if let failOn, Severity(rawValue: failOn) == nil {
            throw ValidationError("Invalid failure threshold: \(failOn); expected error, warning, or info")
        }
        if let jobs, jobs <= 0 { throw ValidationError("--jobs must be a positive integer") }
    }

    func applying(to invocation: inout CLIInvocation) {
        invocation.config = config
        invocation.baseline = baseline
        invocation.format = ReportFormat(rawValue: format)
        invocation.output = output
        invocation.failOn = failOn.flatMap(Severity.init(rawValue:))
        invocation.strict = strict
        invocation.jobs = jobs
        invocation.noColor = noColor
        invocation.quiet = quiet
        invocation.verbose = verbose
    }
}

struct LintCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "lint", abstract: "Analyze Swift project files.")
    @Argument(help: "Files or directories to analyze.") var paths: [String] = []
    @OptionGroup var options: CommonOptions
    func invocation() -> CLIInvocation {
        var result = CLIInvocation(operation: .lint, paths: paths)
        options.applying(to: &result)
        return result
    }
}

struct FixCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "fix", abstract: "Apply proven-safe fixes.")
    @Argument(help: "Files or directories to fix.") var paths: [String] = []
    @OptionGroup var options: CommonOptions
    @Flag(name: .long, help: "Print a unified diff without changing files.") var dryRun = false
    func invocation() -> CLIInvocation {
        var result = CLIInvocation(operation: .fix(dryRun: dryRun), paths: paths)
        options.applying(to: &result)
        return result
    }
}

struct BaselineCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline", abstract: "Create, update, validate, or migrate a baseline.",
        subcommands: [BaselineCreateCommand.self, BaselineUpdateCommand.self,
                      BaselineCheckCommand.self, BaselineMigrateCommand.self]
    )
}

struct BaselineCreateCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "create")
    @Argument var paths: [String] = []
    @OptionGroup var options: CommonOptions
    @Flag(name: .long) var force = false
    func invocation() -> CLIInvocation {
        var result = CLIInvocation(operation: .baselineCreate(force: force), paths: paths)
        options.applying(to: &result)
        return result
    }
}

struct BaselineUpdateCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "update")
    @Argument var paths: [String] = []
    @OptionGroup var options: CommonOptions
    func invocation() -> CLIInvocation {
        var result = CLIInvocation(operation: .baselineUpdate, paths: paths)
        options.applying(to: &result)
        return result
    }
}

struct BaselineCheckCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "check")
    @Argument var paths: [String] = []
    @OptionGroup var options: CommonOptions
    func invocation() -> CLIInvocation {
        var result = CLIInvocation(operation: .baselineCheck, paths: paths)
        options.applying(to: &result)
        return result
    }
}

struct BaselineMigrateCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "migrate", abstract: "Migrate unambiguous baseline v1 entries to v2.")
    @Argument var paths: [String] = []
    @OptionGroup var options: CommonOptions
    func invocation() -> CLIInvocation {
        var result = CLIInvocation(operation: .baselineMigrate, paths: paths)
        options.applying(to: &result)
        return result
    }
}

struct RulesCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "rules", abstract: "List built-in rules.")
    func invocation() -> CLIInvocation { CLIInvocation(operation: .rules) }
}

struct InitCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "init", abstract: "Create .resizelint.yml.")
    @Flag(name: .long) var force = false
    func invocation() -> CLIInvocation { CLIInvocation(operation: .initialize(force: force)) }
}

struct VersionCommand: InvocationCommand {
    static let configuration = CommandConfiguration(commandName: "version", abstract: "Print the ResizeLint version.")
    func invocation() -> CLIInvocation { CLIInvocation(operation: .version) }
}
