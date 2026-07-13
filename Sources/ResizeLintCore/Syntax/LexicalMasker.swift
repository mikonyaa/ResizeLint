import Foundation

enum LexicalMasker {
    static func maskingXMLComments(in source: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#) else { return source }
        var units = Array(source.utf16)
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        for match in matches {
            for position in match.range.location..<(match.range.location + match.range.length)
            where units[position] != 10 && units[position] != 13 {
                units[position] = 32
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func maskingStringLiterals(in source: String) -> String {
        masking(in: source, comments: false)
    }

    static func maskingCommentsAndLiterals(in source: String) -> String {
        masking(in: source, comments: true)
    }

    private static func masking(in source: String, comments: Bool) -> String {
        let units = Array(source.utf16)
        var output = units
        var index = 0

        func isNewline(_ value: UInt16) -> Bool { value == 10 || value == 13 }
        func mask(_ position: Int) {
            if !isNewline(output[position]) { output[position] = 32 }
        }
        func matches(_ values: [UInt16], at position: Int) -> Bool {
            guard position + values.count <= units.count else { return false }
            return Array(units[position..<(position + values.count)]) == values
        }

        while index < units.count {
            if matches([47, 47], at: index) {
                while index < units.count, !isNewline(units[index]) {
                    if comments { mask(index) }
                    index += 1
                }
                continue
            }
            if matches([47, 42], at: index) {
                var depth = 0
                while index < units.count {
                    if matches([47, 42], at: index) {
                        depth += 1
                        if comments { mask(index); mask(index + 1) }
                        index += 2
                    } else if matches([42, 47], at: index) {
                        depth -= 1
                        if comments { mask(index); mask(index + 1) }
                        index += 2
                        if depth == 0 { break }
                    } else {
                        if comments { mask(index) }
                        index += 1
                    }
                }
                continue
            }

            var hashCount = 0
            while index + hashCount < units.count, units[index + hashCount] == 35 { hashCount += 1 }
            let quoteIndex = index + hashCount
            if quoteIndex < units.count, units[quoteIndex] == 34 {
                let multiline = matches([34, 34, 34], at: quoteIndex)
                let quoteCount = multiline ? 3 : 1
                for position in index..<(quoteIndex + quoteCount) { mask(position) }
                index = quoteIndex + quoteCount

                while index < units.count {
                    let closingQuotes = Array(repeating: UInt16(34), count: quoteCount)
                    if matches(closingQuotes, at: index) {
                        let hashesStart = index + quoteCount
                        let expectedHashes = Array(repeating: UInt16(35), count: hashCount)
                        if matches(expectedHashes, at: hashesStart) {
                            for position in index..<(hashesStart + hashCount) { mask(position) }
                            index = hashesStart + hashCount
                            break
                        }
                    }
                    if hashCount == 0, !multiline, units[index] == 92 {
                        mask(index)
                        index += 1
                        if index < units.count { mask(index); index += 1 }
                    } else {
                        mask(index)
                        index += 1
                    }
                }
                continue
            }
            index += 1
        }

        return String(decoding: output, as: UTF16.self)
    }
}
