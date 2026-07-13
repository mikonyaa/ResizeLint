import Foundation

public enum ScanError: Error, Equatable {
    case sourceTooLarge(path: String, bytes: Int)
    case invalidUTF8(String)
}

public enum ProjectScanner {
    public static let maximumSourceBytes = 10 * 1_048_576

    public static func scan(
        paths: [URL],
        root: URL,
        configuration: ResizeLintConfiguration
    ) async throws -> AnalysisResult {
        try Task.checkCancellation()
        let discovered = try SourceDiscovery().discover(paths: paths, scanRoot: root).filter { file in
            let included = configuration.include.isEmpty
                || configuration.include.contains { Glob.matches(file.relativePath, pattern: $0) }
            let excluded = configuration.exclude.contains { Glob.matches(file.relativePath, pattern: $0) }
            return included && !excluded
        }
        var inputs: [SourceInput] = []
        var notices: [OperationalNotice] = []
        for file in discovered {
            try Task.checkCancellation()
            do {
                let data = try Data(contentsOf: file.url, options: [.mappedIfSafe])
                guard data.count <= maximumSourceBytes else {
                    throw ScanError.sourceTooLarge(path: file.relativePath, bytes: data.count)
                }
                guard let contents = String(data: data, encoding: .utf8) else {
                    throw ScanError.invalidUTF8(file.relativePath)
                }
                inputs.append(SourceInput(path: file.relativePath, contents: contents, kind: file.kind))
            } catch let error as ScanError {
                throw error
            } catch {
                notices.append(OperationalNotice(
                    kind: .unreadableFile,
                    path: file.relativePath,
                    message: "Unable to read source: \(error.localizedDescription)"
                ))
            }
        }
        let analyzed = await ResizeAnalyzer().analyze(AnalysisRequest(files: inputs, configuration: configuration))
        return AnalysisResult(
            diagnostics: analyzed.diagnostics,
            notices: (notices + analyzed.notices).sorted { ($0.path, $0.message) < ($1.path, $1.message) },
            filesAnalyzed: analyzed.filesAnalyzed
        )
    }
}
