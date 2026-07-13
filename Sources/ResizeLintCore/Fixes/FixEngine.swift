import Foundation
import SwiftParser
import SwiftParserDiagnostics
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FixError: Error, Equatable {
    case overlappingEdits
    case invalidRange
    case invalidUTF8
    case syntaxRegression
    case unsafeDestination
}

public struct FixPreview: Equatable, Sendable {
    public let updatedSource: String
    public let unifiedDiff: String

    public init(updatedSource: String, unifiedDiff: String) {
        self.updatedSource = updatedSource
        self.unifiedDiff = unifiedDiff
    }
}

public enum FixEngine {
    public static func apply(edits: [SourceEdit], to source: String) throws -> String {
        let ordered = edits.sorted { $0.utf8Offset < $1.utf8Offset }
        for pair in zip(ordered, ordered.dropFirst())
        where pair.0.utf8Offset + pair.0.utf8Length > pair.1.utf8Offset {
            throw FixError.overlappingEdits
        }

        var bytes = Array(source.utf8)
        for edit in ordered.reversed() {
            guard edit.utf8Offset >= 0, edit.utf8Length >= 0,
                  edit.utf8Offset + edit.utf8Length <= bytes.count else { throw FixError.invalidRange }
            bytes.replaceSubrange(
                edit.utf8Offset..<(edit.utf8Offset + edit.utf8Length),
                with: edit.replacement.utf8
            )
        }
        guard let updated = String(bytes: bytes, encoding: .utf8) else { throw FixError.invalidUTF8 }
        return updated
    }

    public static func preview(source: String, edits: [SourceEdit], path: String) throws -> FixPreview {
        let updated = try apply(edits: edits, to: source)
        return FixPreview(updatedSource: updated, unifiedDiff: unifiedDiff(old: source, new: updated, path: path))
    }

    public static func writeAtomically(source: String, edits: [SourceEdit], to url: URL) throws {
        let updated = try apply(edits: edits, to: source)
        let parsed = Parser.parse(source: updated)
        guard ParseDiagnosticsGenerator.diagnostics(for: parsed).isEmpty else { throw FixError.syntaxRegression }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw FixError.unsafeDestination
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes[.posixPermissions]
        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).resizelint-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data(updated.utf8).write(to: temporary, options: .withoutOverwriting)
        if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path) }
        try replaceItem(at: url, withItemAt: temporary)
    }

    private static func replaceItem(at destination: URL, withItemAt replacement: URL) throws {
        let result = replacement.path.withCString { replacementPath in
            destination.path.withCString { destinationPath in
                rename(replacementPath, destinationPath)
            }
        }
        guard result == 0 else {
            let code = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSFilePathErrorKey: destination.path]
            )
        }
    }

    private static func unifiedDiff(old: String, new: String, path: String) -> String {
        guard old != new else { return "" }
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false)
        var output = "--- a/\(path)\n+++ b/\(path)\n@@ -1,\(oldLines.count) +1,\(newLines.count) @@\n"
        output += oldLines.map { "-\($0)" }.joined(separator: "\n") + "\n"
        output += newLines.map { "+\($0)" }.joined(separator: "\n") + "\n"
        return output
    }
}
