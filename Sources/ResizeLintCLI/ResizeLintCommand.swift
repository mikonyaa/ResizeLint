import ArgumentParser
import Foundation
import ResizeLintCore

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
        subcommands: [
            LintCommand.self,
            FixCommand.self,
            BaselineCommand.self,
            RulesCommand.self,
            InitCommand.self,
            VersionCommand.self,
        ],
        defaultSubcommand: LintCommand.self
    )

    static func runForTesting(
        arguments: [String],
        currentDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath)
    ) async throws -> CLIResult {
        await CLIApplication.run(arguments: arguments, currentDirectory: currentDirectory)
    }
}

struct CommonOptions: ParsableArguments {
    @Option(name: .long, help: "Path to .resizelint.yml.") var config: String?
    @Option(name: .long, help: "Path to the baseline JSON file.") var baseline: String?
    @Option(name: .long, help: "Output format: human, xcode, json, or sarif.") var format = "human"
    @Option(name: .long, help: "Write the report to a file.") var output: String?
    @Option(name: .long, help: "Failure threshold: error, warning, or info.") var failOn: String?
    @Flag(name: .long, help: "Equivalent to --fail-on warning.") var strict = false
    @Option(name: .long, help: "Maximum concurrent parsing jobs.") var jobs: Int?
    @Flag(name: .long, help: "Disable terminal color.") var noColor = false
    @Flag(name: .long, help: "Suppress normal output.") var quiet = false
    @Flag(name: .long, help: "Show operational audit notices.") var verbose = false

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

struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "lint", abstract: "Analyze Swift project files.")
    @Argument(help: "Files or directories to analyze.") var paths: [String] = []
    @OptionGroup var options: CommonOptions

    mutating func run() async throws {
        var invocation = CLIInvocation(operation: .lint, paths: paths)
        options.applying(to: &invocation)
        try await execute(invocation)
    }
}

struct FixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "fix", abstract: "Apply proven-safe fixes.")
    @Argument(help: "Files or directories to fix.") var paths: [String] = []
    @OptionGroup var options: CommonOptions
    @Flag(name: .long, help: "Print a unified diff without changing files.") var dryRun = false

    mutating func run() async throws {
        var invocation = CLIInvocation(operation: .fix(dryRun: dryRun), paths: paths)
        options.applying(to: &invocation)
        try await execute(invocation)
    }
}

struct BaselineCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline",
        abstract: "Create, update, or validate a baseline.",
        subcommands: [BaselineCreateCommand.self, BaselineUpdateCommand.self, BaselineCheckCommand.self]
    )
}

struct BaselineCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create")
    @Argument var paths: [String] = []
    @OptionGroup var options: CommonOptions
    @Flag(name: .long) var force = false
    mutating func run() async throws {
        var invocation = CLIInvocation(operation: .baselineCreate(force: force), paths: paths)
        options.applying(to: &invocation)
        try await execute(invocation)
    }
}

struct BaselineUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update")
    @Argument var paths: [String] = []
    @OptionGroup var options: CommonOptions
    mutating func run() async throws {
        var invocation = CLIInvocation(operation: .baselineUpdate, paths: paths)
        options.applying(to: &invocation)
        try await execute(invocation)
    }
}

struct BaselineCheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "check")
    @Argument var paths: [String] = []
    @OptionGroup var options: CommonOptions
    mutating func run() async throws {
        var invocation = CLIInvocation(operation: .baselineCheck, paths: paths)
        options.applying(to: &invocation)
        try await execute(invocation)
    }
}

struct RulesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rules", abstract: "List built-in rules.")
    mutating func run() async throws { try await execute(CLIInvocation(operation: .rules)) }
}

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "init", abstract: "Create .resizelint.yml.")
    @Flag(name: .long) var force = false
    mutating func run() async throws { try await execute(CLIInvocation(operation: .initialize(force: force))) }
}

struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "version", abstract: "Print the ResizeLint version.")
    mutating func run() async throws { try await execute(CLIInvocation(operation: .version)) }
}

private func execute(_ invocation: CLIInvocation) async throws {
    let result = await CLIApplication.run(
        invocation: invocation,
        currentDirectory: URL(filePath: FileManager.default.currentDirectoryPath)
    )
    if !result.standardOutput.isEmpty { FileHandle.standardOutput.write(Data(result.standardOutput.utf8)) }
    if !result.standardError.isEmpty { FileHandle.standardError.write(Data(result.standardError.utf8)) }
    if result.exitCode != 0 { throw ExitCode(result.exitCode) }
}
