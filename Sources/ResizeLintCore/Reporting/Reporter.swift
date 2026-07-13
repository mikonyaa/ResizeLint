import Foundation

public enum ReportFormat: String, Codable, CaseIterable, Sendable {
    case human
    case xcode
    case json
    case sarif
}

public struct ReportContext: Sendable {
    public let command: String
    public let paths: [String]
    public let durationSeconds: Double

    public init(command: String, paths: [String], durationSeconds: Double) {
        self.command = command
        self.paths = paths
        self.durationSeconds = durationSeconds
    }
}

public enum ReporterError: Error {
    case encoding
}

public enum Reporter {
    public static func render(
        format: ReportFormat,
        result: AnalysisResult,
        context: ReportContext,
        color: Bool = false
    ) throws -> String {
        let sanitized = AnalysisResult(
            diagnostics: result.diagnostics.map(sanitize),
            notices: result.notices,
            filesAnalyzed: result.filesAnalyzed
        )
        switch format {
        case .human: return human(sanitized, context: context, color: color)
        case .xcode: return xcode(sanitized)
        case .json: return try json(sanitized, context: context)
        case .sarif: return try sarif(sanitized)
        }
    }

    private static func human(_ result: AnalysisResult, context: ReportContext, color: Bool) -> String {
        let active = result.diagnostics.filter { !$0.isSuppressed && $0.baselineState != .unchanged }
        var sections = active.map { diagnostic in
            "\(diagnostic.path):\(diagnostic.range.start.line):\(diagnostic.range.start.column)  \(diagnostic.severity.rawValue)  \(diagnostic.ruleID)\n"
                + "\(diagnostic.message)\n\n\(diagnostic.helpURI)"
        }
        let counts = summary(for: active, filesAnalyzed: result.filesAnalyzed)
        let total = active.count
        let noun = total == 1 ? severitySummary(counts) : severitySummary(counts)
        let fileWord = result.filesAnalyzed == 1 ? "file" : "files"
        sections.append("\(noun), \(result.filesAnalyzed) \(fileWord) analyzed in \(String(format: "%.2f", context.durationSeconds))s")
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func xcode(_ result: AnalysisResult) -> String {
        result.diagnostics
            .filter { !$0.isSuppressed && $0.baselineState != .unchanged }
            .map {
                "\($0.path):\($0.range.start.line):\($0.range.start.column): \($0.severity.rawValue): [\($0.ruleID)] \($0.message)"
            }
            .joined(separator: "\n") + (result.diagnostics.isEmpty ? "" : "\n")
    }

    private static func json(_ result: AnalysisResult, context: ReportContext) throws -> String {
        let active = result.diagnostics.filter { !$0.isSuppressed }
        let report = JSONReport(
            schemaVersion: 1,
            toolVersion: ResizeLintVersion.current,
            invocation: Invocation(command: context.command, paths: context.paths),
            summary: summary(for: active, filesAnalyzed: result.filesAnalyzed),
            diagnostics: active,
            fixes: active.compactMap(\.fix),
            timing: Timing(durationSeconds: context.durationSeconds)
        )
        return try encode(report)
    }

    private static func sarif(_ result: AnalysisResult) throws -> String {
        let rules = RuleCatalog.all.map { metadata in
            SARIFRule(
                id: metadata.id,
                name: metadata.name,
                defaultConfiguration: SARIFLevel(level: sarifLevel(metadata.severity)),
                helpUri: metadata.helpURI
            )
        }
        let results = result.diagnostics.filter { !$0.isSuppressed }.map { diagnostic in
            SARIFResult(
                ruleId: diagnostic.ruleID,
                level: sarifLevel(diagnostic.severity),
                message: SARIFMessage(text: diagnostic.message),
                locations: [SARIFLocation(physicalLocation: SARIFPhysicalLocation(
                    artifactLocation: SARIFArtifactLocation(uri: diagnostic.path),
                    region: SARIFRegion(
                        startLine: diagnostic.range.start.line,
                        startColumn: diagnostic.range.start.column,
                        endLine: diagnostic.range.end.line,
                        endColumn: diagnostic.range.end.column
                    )
                ))],
                partialFingerprints: ["resizelint/v1": diagnostic.fingerprint],
                baselineState: diagnostic.baselineState == .unchanged ? "unchanged" : "new"
            )
        }
        let report = SARIFReport(
            schema: "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [SARIFRun(
                tool: SARIFTool(driver: SARIFDriver(
                    name: "ResizeLint",
                    version: ResizeLintVersion.current,
                    informationUri: "https://github.com/mikonyaa/ResizeLint",
                    rules: rules
                )),
                results: results
            )]
        )
        return try encode(report)
    }

    private static func sanitize(_ diagnostic: Diagnostic) -> Diagnostic {
        let path = diagnostic.path.hasPrefix("/") ? URL(filePath: diagnostic.path).lastPathComponent : diagnostic.path
        return Diagnostic(
            ruleID: diagnostic.ruleID,
            ruleName: diagnostic.ruleName,
            severity: diagnostic.severity,
            message: diagnostic.message,
            path: path,
            range: diagnostic.range,
            helpURI: diagnostic.helpURI,
            fix: diagnostic.fix.map {
                SourceEdit(path: path, utf8Offset: $0.utf8Offset, utf8Length: $0.utf8Length, replacement: $0.replacement)
            },
            fingerprint: diagnostic.fingerprint,
            isSuppressed: diagnostic.isSuppressed,
            baselineState: diagnostic.baselineState
        )
    }

    private static func summary(for diagnostics: [Diagnostic], filesAnalyzed: Int) -> ReportSummary {
        ReportSummary(
            errors: diagnostics.count { $0.severity == .error },
            warnings: diagnostics.count { $0.severity == .warning },
            info: diagnostics.count { $0.severity == .info },
            filesAnalyzed: filesAnalyzed
        )
    }

    private static func severitySummary(_ summary: ReportSummary) -> String {
        var parts: [String] = []
        if summary.errors > 0 { parts.append("\(summary.errors) error\(summary.errors == 1 ? "" : "s")") }
        if summary.warnings > 0 { parts.append("\(summary.warnings) warning\(summary.warnings == 1 ? "" : "s")") }
        if summary.info > 0 { parts.append("\(summary.info) info") }
        return parts.isEmpty ? "No findings" : parts.joined(separator: ", ")
    }

    private static func sarifLevel(_ severity: Severity) -> String {
        switch severity {
        case .error: "error"
        case .warning: "warning"
        case .info: "note"
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let output = String(data: data, encoding: .utf8) else { throw ReporterError.encoding }
        return output + "\n"
    }
}

private struct JSONReport: Encodable {
    let schemaVersion: Int
    let toolVersion: String
    let invocation: Invocation
    let summary: ReportSummary
    let diagnostics: [Diagnostic]
    let fixes: [SourceEdit]
    let timing: Timing
}

private struct Invocation: Encodable { let command: String; let paths: [String] }
private struct Timing: Encodable { let durationSeconds: Double }
private struct ReportSummary: Encodable {
    let errors: Int
    let warnings: Int
    let info: Int
    let filesAnalyzed: Int
}

private struct SARIFReport: Encodable {
    let schema: String
    let version: String
    let runs: [SARIFRun]
    enum CodingKeys: String, CodingKey { case schema = "$schema"; case version, runs }
}
private struct SARIFRun: Encodable { let tool: SARIFTool; let results: [SARIFResult] }
private struct SARIFTool: Encodable { let driver: SARIFDriver }
private struct SARIFDriver: Encodable {
    let name: String
    let version: String
    let informationUri: String
    let rules: [SARIFRule]
}
private struct SARIFRule: Encodable {
    let id: String
    let name: String
    let defaultConfiguration: SARIFLevel
    let helpUri: String
}
private struct SARIFLevel: Encodable { let level: String }
private struct SARIFResult: Encodable {
    let ruleId: String
    let level: String
    let message: SARIFMessage
    let locations: [SARIFLocation]
    let partialFingerprints: [String: String]
    let baselineState: String
}
private struct SARIFMessage: Encodable { let text: String }
private struct SARIFLocation: Encodable { let physicalLocation: SARIFPhysicalLocation }
private struct SARIFPhysicalLocation: Encodable {
    let artifactLocation: SARIFArtifactLocation
    let region: SARIFRegion
}
private struct SARIFArtifactLocation: Encodable { let uri: String }
private struct SARIFRegion: Encodable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
}
