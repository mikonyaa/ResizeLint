import Foundation

/// JSON/Xcode retain UTF-8 byte columns. SARIF gets separate UTF-16 code unit columns.
struct SourceCoordinates {
    private let bytes: [UInt8]
    private let lineStarts: [Int]

    init(source: String) {
        bytes = Array(source.utf8)
        lineStarts = [0] + bytes.enumerated().compactMap { $0.element == 10 ? $0.offset + 1 : nil }
    }

    func range(offset: Int, length: Int) -> SourceRange {
        SourceRange(start: location(at: offset, utf16: false), end: location(at: offset + length, utf16: false),
                    utf8Offset: offset, utf8Length: length,
                    utf16Start: location(at: offset, utf16: true), utf16End: location(at: offset + length, utf16: true))
    }

    private func location(at offset: Int, utf16: Bool) -> SourceLocation {
        var lower = 0
        var upper = lineStarts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= offset { lower = middle + 1 } else { upper = middle }
        }
        let lineIndex = max(0, lower - 1)
        let start = lineStarts[lineIndex]
        let column = utf16 ? String(decoding: bytes[start..<offset], as: UTF8.self).utf16.count + 1 : offset - start + 1
        return SourceLocation(line: lineIndex + 1, column: column)
    }
}
