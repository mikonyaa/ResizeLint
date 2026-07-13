import ArgumentParser
import ResizeLintCore

struct CLIResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

@main
struct ResizeLintCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resizelint",
        abstract: "Find layout assumptions that break in resizable Swift apps.",
        subcommands: [VersionCommand.self]
    )

    static func runForTesting(arguments: [String]) throws -> CLIResult {
        guard arguments == ["version"] else {
            throw ValidationError("Unsupported test invocation")
        }

        return CLIResult(
            exitCode: 0,
            standardOutput: "\(ResizeLintVersion.current)\n",
            standardError: ""
        )
    }
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the ResizeLint version."
    )

    func run() {
        print(ResizeLintVersion.current)
    }
}
