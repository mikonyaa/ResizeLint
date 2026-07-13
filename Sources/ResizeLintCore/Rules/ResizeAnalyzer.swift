import Foundation
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public struct SourceInput: Sendable {
    public let path: String
    public let contents: String
    public let kind: SourceKind

    public init(path: String, contents: String, kind: SourceKind? = nil) {
        self.path = path.replacingOccurrences(of: "\\", with: "/")
        self.contents = contents
        if let kind {
            self.kind = kind
        } else if path.hasSuffix(".swift") {
            self.kind = .swift
        } else if path.hasSuffix("Info.plist") {
            self.kind = .propertyList
        } else {
            self.kind = .xcodeProject
        }
    }
}

public struct AnalysisRequest: Sendable {
    public let files: [SourceInput]
    public let configuration: ResizeLintConfiguration

    public init(files: [SourceInput], configuration: ResizeLintConfiguration = ResizeLintConfiguration()) {
        self.files = files
        self.configuration = configuration
    }
}

public struct AnalysisResult: Sendable {
    public let diagnostics: [Diagnostic]
    public let notices: [OperationalNotice]
    public let filesAnalyzed: Int

    public init(diagnostics: [Diagnostic], notices: [OperationalNotice], filesAnalyzed: Int) {
        self.diagnostics = diagnostics
        self.notices = notices
        self.filesAnalyzed = filesAnalyzed
    }
}

public struct ResizeAnalyzer: Sendable {
    public init() {}

    public func analyze(_ request: AnalysisRequest) async -> AnalysisResult {
        var diagnostics: [Diagnostic] = []
        var notices: [OperationalNotice] = []
        let batchSize = max(1, request.configuration.jobs)

        for start in stride(from: 0, to: request.files.count, by: batchSize) {
            let end = min(start + batchSize, request.files.count)
            let batch = Array(request.files[start..<end])
            await withTaskGroup(of: FileAnalysis.self) { group in
                for file in batch {
                    group.addTask { Self.analyzeFile(file, configuration: request.configuration) }
                }
                for await result in group {
                    diagnostics.append(contentsOf: result.diagnostics)
                    notices.append(contentsOf: result.notices)
                }
            }
        }

        let projectResult = Self.analyzeProject(request.files, configuration: request.configuration)
        diagnostics.append(contentsOf: projectResult.diagnostics)
        notices.append(contentsOf: projectResult.notices)
        return AnalysisResult(
            diagnostics: diagnostics.sorted(),
            notices: notices.sorted { ($0.path, $0.message) < ($1.path, $1.message) },
            filesAnalyzed: request.files.count
        )
    }

    private static func analyzeFile(
        _ file: SourceInput,
        configuration: ResizeLintConfiguration
    ) -> FileAnalysis {
        switch file.kind {
        case .swift:
            return analyzeSwift(file, configuration: configuration)
        case .propertyList, .xcodeProject:
            return analyzeProjectFile(file, configuration: configuration)
        }
    }

    private static func analyzeSwift(
        _ file: SourceInput,
        configuration: ResizeLintConfiguration
    ) -> FileAnalysis {
        let tree = Parser.parse(source: file.contents)
        let parseDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree)
        let masked = LexicalMasker.maskingCommentsAndLiterals(in: file.contents)
        let suppressions = SuppressionIndex(source: file.contents, path: file.path)
        var notices = suppressions.notices
        if !parseDiagnostics.isEmpty {
            notices.append(OperationalNotice(
                kind: .syntaxError,
                path: file.path,
                message: "SwiftParser recovered from \(parseDiagnostics.count) syntax diagnostic(s)."
            ))
        }

        var matches: [RuleMatch] = []
        let rl001 = regexMatches(
            #"\bUIScreen\s*\.\s*main\s*\.\s*(?:(?:coordinateSpace|fixedCoordinateSpace)\s*\.\s*)?(?:bounds|nativeBounds)\b"#,
            in: masked
        )
        matches.append(contentsOf: rl001.map { RuleMatch(ruleID: "RL001", range: $0) })

        let rl002 = regexMatches(#"\bUIScreen\s*\.\s*main\s*\.\s*(?:scale|nativeScale)\b"#, in: masked)
        matches.append(contentsOf: rl002.map { RuleMatch(ruleID: "RL002", range: $0) })

        let covered = rl001 + rl002
        let generic = regexMatches(#"\bUIScreen\s*\.\s*main\b"#, in: masked)
            .filter { candidate in !covered.contains(where: { NSLocationInRange(candidate.location, $0) }) }
        matches.append(contentsOf: generic.map { RuleMatch(ruleID: "RL003", range: $0) })

        for range in regexMatches(#"\bUIApplication\s*\.\s*shared\s*\.\s*(?:windows|keyWindow)\b"#, in: masked)
        where !isBroadcastWindowIteration(range: range, source: masked) {
            matches.append(RuleMatch(ruleID: "RL004", range: range))
        }
        for range in regexMatches(#"\bUIApplication\s*\.\s*shared\s*\.\s*connectedScenes\b"#, in: masked)
        where !isBroadcastSceneIteration(range: range, source: masked) {
            matches.append(RuleMatch(ruleID: "RL004", range: range))
        }

        for range in regexMatches(#"\bUIApplication\s*\.\s*shared\s*\.\s*(?:statusBarFrame|statusBarOrientation)\b"#, in: masked) {
            matches.append(RuleMatch(ruleID: "RL005", range: range))
        }

        let idiomPattern = #"(?:(?:traitCollection|UIDevice\s*\.\s*current)\s*\.\s*)?userInterfaceIdiom\s*(?:==|!=)\s*\.(?:phone|pad)\b"#
        for range in regexMatches(idiomPattern, in: masked) where isLayoutDecision(range: range, source: masked, orientation: false) {
            matches.append(RuleMatch(ruleID: "RL006", range: range))
        }

        let orientationPattern = #"\b(?:UIDevice\s*\.\s*current\s*\.\s*orientation|interfaceOrientation|statusBarOrientation)(?:\s*\.\s*(?:isPortrait|isLandscape))?\b"#
        for range in regexMatches(orientationPattern, in: masked) where isLayoutDecision(range: range, source: masked, orientation: true) {
            matches.append(RuleMatch(ruleID: "RL007", range: range))
        }

        let diagnostics = matches.compactMap { match in
            makeDiagnostic(
                match,
                file: file,
                configuration: configuration,
                suppressions: suppressions
            )
        }
        return FileAnalysis(diagnostics: diagnostics, notices: notices)
    }

    private static func analyzeProjectFile(
        _ file: SourceInput,
        configuration: ResizeLintConfiguration
    ) -> FileAnalysis {
        guard configuration.isRuleEnabled("RL009", path: file.path) else { return FileAnalysis() }
        let pattern: String
        switch file.kind {
        case .propertyList:
            pattern = #"<key>\s*UIRequiresFullScreen\s*</key>\s*<true\s*/>"#
        case .xcodeProject:
            pattern = #"(?:INFOPLIST_KEY_)?UIRequiresFullScreen(?:\s*\[[^\]]+\])?\s*=\s*(?:YES|true)\b"#
        case .swift:
            return FileAnalysis()
        }
        let searchable: String
        switch file.kind {
        case .xcodeProject:
            searchable = LexicalMasker.maskingCommentsAndLiterals(in: file.contents)
        case .propertyList:
            searchable = LexicalMasker.maskingXMLComments(in: file.contents)
        case .swift:
            searchable = file.contents
        }
        let matches = regexMatches(pattern, in: searchable, caseInsensitive: true)
        let diagnostics = matches.map { range in
            makeDiagnostic(
                RuleMatch(ruleID: "RL009", range: range),
                file: file,
                configuration: configuration,
                suppressions: nil
            )
        }.compactMap { $0 }
        return FileAnalysis(diagnostics: diagnostics)
    }

    private static func analyzeProject(
        _ files: [SourceInput],
        configuration: ResizeLintConfiguration
    ) -> FileAnalysis {
        guard configuration.isRuleEnabled("RL008", path: "") else { return FileAnalysis() }
        let swiftFiles = files.filter { $0.kind == .swift }
        let projectText = files.filter { $0.kind == .xcodeProject }.map(\.contents).joined(separator: "\n")
        let plistText = files.filter { $0.kind == .propertyList }.map(\.contents).joined(separator: "\n")
        let hasApplicationTarget = projectText.range(
            of: #"com\.apple\.product-type\.application"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        guard hasApplicationTarget else {
            let legacyWindow = swiftFiles.contains { isLegacyAppDelegate($0.contents) }
            return legacyWindow
                ? FileAnalysis(notices: [OperationalNotice(
                    kind: .ambiguousProject,
                    path: "",
                    message: "Legacy lifecycle evidence exists, but no unambiguous iOS application target was found."
                )])
                : FileAnalysis()
        }
        let hasSwiftUIApp = swiftFiles.contains {
            regexMatches(#"@main\s+(?:struct|class)\s+\w+\s*:\s*App\b"#, in: LexicalMasker.maskingCommentsAndLiterals(in: $0.contents)).isEmpty == false
        }
        let hasSceneDelegate = swiftFiles.contains {
            regexMatches(#"\bUISceneDelegate\b"#, in: LexicalMasker.maskingCommentsAndLiterals(in: $0.contents)).isEmpty == false
        }
        let hasSceneManifest = plistText.contains("UIApplicationSceneManifest")
            || projectText.contains("INFOPLIST_KEY_UIApplicationSceneManifest_Generation")
        guard !hasSwiftUIApp, !hasSceneDelegate, !hasSceneManifest,
              let legacyFile = swiftFiles.first(where: { isLegacyAppDelegate($0.contents) }) else {
            return FileAnalysis()
        }
        let masked = LexicalMasker.maskingCommentsAndLiterals(in: legacyFile.contents)
        guard let range = regexMatches(#"\bvar\s+window\s*:\s*UIWindow\s*\?"#, in: masked).first else {
            return FileAnalysis()
        }
        let suppression = SuppressionIndex(source: legacyFile.contents, path: legacyFile.path)
        let diagnostic = makeDiagnostic(
            RuleMatch(ruleID: "RL008", range: range),
            file: legacyFile,
            configuration: configuration,
            suppressions: suppression
        )
        return FileAnalysis(diagnostics: diagnostic.map { [$0] } ?? [], notices: suppression.notices)
    }

    private static func isLegacyAppDelegate(_ source: String) -> Bool {
        let masked = LexicalMasker.maskingCommentsAndLiterals(in: source)
        let delegate = regexMatches(#"\bUIApplicationDelegate\b"#, in: masked).isEmpty == false
        let window = regexMatches(#"\bvar\s+window\s*:\s*UIWindow\s*\?"#, in: masked).isEmpty == false
        return delegate && window
    }

    private static func makeDiagnostic(
        _ match: RuleMatch,
        file: SourceInput,
        configuration: ResizeLintConfiguration,
        suppressions: SuppressionIndex?
    ) -> Diagnostic? {
        guard configuration.isRuleEnabled(match.ruleID, path: file.path),
              let stringRange = Range(match.range, in: file.contents) else { return nil }
        let metadata = RuleCatalog.metadata(for: match.ruleID)
        let startOffset = file.contents.utf8.distance(from: file.contents.startIndex, to: stringRange.lowerBound)
        let endOffset = file.contents.utf8.distance(from: file.contents.startIndex, to: stringRange.upperBound)
        let start = location(in: file.contents, at: stringRange.lowerBound)
        let end = location(in: file.contents, at: stringRange.upperBound)
        let matchedSource = String(file.contents[stringRange])
        let fingerprint = Fingerprinter.fingerprint(
            ruleID: match.ruleID,
            path: file.path,
            syntaxKind: file.kind == .swift ? "memberAccess" : "projectSetting",
            surroundingTokens: matchedSource.components(separatedBy: .whitespacesAndNewlines)
        )
        let fix = safeFix(
            ruleID: match.ruleID,
            matchedSource: matchedSource,
            file: file,
            range: stringRange,
            utf8Offset: startOffset,
            utf8Length: endOffset - startOffset
        )
        return Diagnostic(
            ruleID: match.ruleID,
            ruleName: metadata.name,
            severity: configuration.severity(for: match.ruleID, default: metadata.severity, path: file.path),
            message: metadata.message,
            path: file.path,
            range: SourceRange(
                start: start,
                end: end,
                utf8Offset: startOffset,
                utf8Length: endOffset - startOffset
            ),
            helpURI: metadata.helpURI,
            fix: fix,
            fingerprint: fingerprint,
            isSuppressed: suppressions?.suppresses(ruleID: match.ruleID, line: start.line) ?? false
        )
    }

    private static func safeFix(
        ruleID: String,
        matchedSource: String,
        file: SourceInput,
        range: Range<String.Index>,
        utf8Offset: Int,
        utf8Length: Int
    ) -> SourceEdit? {
        guard ruleID == "RL002", matchedSource == "UIScreen.main.scale",
              hasTraitCollectionContext(source: file.contents, before: range.lowerBound) else { return nil }
        return SourceEdit(
            path: file.path,
            utf8Offset: utf8Offset,
            utf8Length: utf8Length,
            replacement: "traitCollection.displayScale"
        )
    }

    private static func hasTraitCollectionContext(source: String, before index: String.Index) -> Bool {
        let prefix = String(source[..<index])
        let pattern = #"\bclass\s+\w+[^\{\n]*:\s*(?:UIView|UIViewController|UITableViewCell|UICollectionViewCell|UIControl)\b[^\{]*\{"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let declaration = expression.matches(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)).last,
              let declarationRange = Range(declaration.range, in: prefix) else { return false }
        let bodyPrefix = prefix[declarationRange.lowerBound...]
        let depth = bodyPrefix.reduce(into: 0) { depth, character in
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
        }
        guard depth > 0 else { return false }
        let currentLine = prefix.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return currentLine.range(of: #"\b(?:static|class)\s+(?:let|var|func)\b"#, options: .regularExpression) == nil
    }

    private static func location(in source: String, at index: String.Index) -> SourceLocation {
        let prefix = source[..<index]
        let line = prefix.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        let lastNewline = prefix.utf8.lastIndex(of: 10)
        let column: Int
        if let lastNewline {
            column = prefix.utf8.distance(from: prefix.utf8.index(after: lastNewline), to: prefix.utf8.endIndex) + 1
        } else {
            column = prefix.utf8.count + 1
        }
        return SourceLocation(line: line, column: column)
    }

    private static func regexMatches(
        _ pattern: String,
        in source: String,
        caseInsensitive: Bool = false
    ) -> [NSRange] {
        var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).map(\.range)
    }

    private static func isBroadcastSceneIteration(range: NSRange, source: String) -> Bool {
        let lower = max(0, range.location - 160)
        let upper = min(source.utf16.count, range.location + range.length + 600)
        let contextRange = NSRange(location: lower, length: upper - lower)
        guard let swiftRange = Range(contextRange, in: source) else { return false }
        let context = String(source[swiftRange])
        let directIteration = context.range(
            of: #"(?:for\s+\w+\s+in\s+[^\n]*connectedScenes|connectedScenes[\s\S]{0,500}?\.\s*forEach)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let namedCollection = context.range(
            of: #"(?:let|var)\s+(\w+)\s*=\s*UIApplication\s*\.\s*shared\s*\.\s*connectedScenes[\s\S]{0,500}?for\s+\w+\s+in\s+\1\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let flattenedCollection = context.range(
            of: #"connectedScenes[\s\S]{0,500}?flatMap[\s\S]{0,80}?windows\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let selects = context.range(of: #"\.\s*first\b"#, options: .regularExpression) != nil
        return (directIteration || namedCollection || flattenedCollection) && !selects
    }

    private static func isBroadcastWindowIteration(range: NSRange, source: String) -> Bool {
        let upper = min(source.utf16.count, range.location + range.length + 120)
        let contextRange = NSRange(location: range.location, length: upper - range.location)
        guard let swiftRange = Range(contextRange, in: source) else { return false }
        let context = String(source[swiftRange])
        return context.range(
            of: #"(?:windows|keyWindow)\s*\.\s*forEach\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isLayoutDecision(range: NSRange, source: String, orientation: Bool) -> Bool {
        if orientation, isOrientationDeclaration(range: range, source: source) { return false }
        let lower = max(0, range.location - 120)
        let upper = min(source.utf16.count, range.location + range.length + 180)
        guard let swiftRange = Range(NSRange(location: lower, length: upper - lower), in: source) else { return false }
        let context = String(source[swiftRange]).lowercased()
        if orientation {
            let excluded = [
                "supportedinterfaceorientations", "camera", "motion", "captureconnection",
                "videoorientation", "avcapture",
            ]
            if excluded.contains(where: context.contains) { return false }
        } else {
            let capability = ["camera", "sensor", "haptic", "capability"]
            if capability.contains(where: context.contains) { return false }
        }
        let layoutTerms = [
            "width", "height", "size", "frame", "constraint", "column", "grid", "layout",
            "sidebar", "navigation", "modal", "presentation", "split", "compact",
            "regular", "rotation", "alert", "actionsheet", "popover", "sheet",
        ]
        let tabLayout = context.range(
            of: #"\btab(?:bar)?\b"#,
            options: .regularExpression
        ) != nil
        return tabLayout || layoutTerms.contains(where: context.contains)
    }

    private static func isOrientationDeclaration(range: NSRange, source: String) -> Bool {
        guard let match = Range(range, in: source) else { return false }
        let tail = source[match.lowerBound..<source.index(
            match.upperBound,
            offsetBy: min(80, source.distance(from: match.upperBound, to: source.endIndex))
        )]
        return tail.range(
            of: #"^interfaceOrientation\s*:\s*UIInterfaceOrientation\b"#,
            options: .regularExpression
        ) != nil
    }
}

private struct RuleMatch: Sendable {
    let ruleID: String
    let range: NSRange
}

private struct FileAnalysis: Sendable {
    var diagnostics: [Diagnostic] = []
    var notices: [OperationalNotice] = []
}
