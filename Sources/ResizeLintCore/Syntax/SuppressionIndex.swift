import Foundation

struct SuppressionIndex: Sendable {
    let fileRules: Set<String>
    let nextLineRules: [Int: Set<String>]
    let notices: [OperationalNotice]

    init(source: String, path: String) {
        var fileRules: Set<String> = []
        var nextLineRules: [Int: Set<String>] = [:]
        var notices: [OperationalNotice] = []
        var declarationSeen = false

        let directiveLines = LexicalMasker.maskingStringLiterals(in: source).components(separatedBy: .newlines)
        let codeLines = LexicalMasker.maskingCommentsAndLiterals(in: source).components(separatedBy: .newlines)
        for (offset, line) in directiveLines.enumerated() {
            let lineNumber = offset + 1
            if let directive = Self.directive(in: line, name: "disable-next-line") {
                if directive.reason.isEmpty {
                    notices.append(Self.malformed(path: path, line: lineNumber))
                } else {
                    nextLineRules[lineNumber + 1, default: []].insert(directive.ruleID)
                }
                continue
            }
            if let directive = Self.directive(in: line, name: "disable-file") {
                if directive.reason.isEmpty || declarationSeen {
                    notices.append(Self.malformed(path: path, line: lineNumber))
                } else {
                    fileRules.insert(directive.ruleID)
                }
                continue
            }
            if line.localizedCaseInsensitiveContains("resizelint:disable") {
                notices.append(Self.malformed(path: path, line: lineNumber))
                continue
            }
            let trimmed = codeLines[offset].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("/*"), !trimmed.hasPrefix("*") {
                declarationSeen = true
            }
        }
        self.fileRules = fileRules
        self.nextLineRules = nextLineRules
        self.notices = notices
    }

    func suppresses(ruleID: String, line: Int) -> Bool {
        fileRules.contains(ruleID) || nextLineRules[line]?.contains(ruleID) == true
    }

    private static func directive(in line: String, name: String) -> (ruleID: String, reason: String)? {
        let pattern = #"^\s*//\s*resizelint:"# + NSRegularExpression.escapedPattern(for: name)
            + #"\s+(RL\d{3})\s+--\s*(.*?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let idRange = Range(match.range(at: 1), in: line),
              let reasonRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[idRange]), String(line[reasonRange]).trimmingCharacters(in: .whitespaces))
    }

    private static func malformed(path: String, line: Int) -> OperationalNotice {
        OperationalNotice(
            kind: .malformedSuppression,
            path: path,
            message: "Malformed suppression at line \(line); a rule ID and nonempty reason are required."
        )
    }
}
