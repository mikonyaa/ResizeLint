import Foundation

public enum SourceKind: String, Codable, Sendable {
    case swift
    case propertyList
    case xcodeProject
}

public struct DiscoveredSource: Equatable, Sendable {
    public let url: URL
    public let relativePath: String
    public let kind: SourceKind

    public init(url: URL, relativePath: String, kind: SourceKind) {
        self.url = url
        self.relativePath = relativePath
        self.kind = kind
    }
}

public enum DiscoveryError: Error, Equatable {
    case pathOutsideRoot(String)
    case missingPath(String)
}

public struct SourceDiscovery: Sendable {
    private let excludedComponents = Set([".git", ".build", "DerivedData", "Pods", "Carthage", "Generated"])

    public init() {}

    public func discover(paths: [URL], scanRoot: URL) throws -> [DiscoveredSource] {
        let root = scanRoot.standardizedFileURL.resolvingSymlinksInPath()
        var result: [DiscoveredSource] = []
        for path in paths {
            let standardized = path.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else {
                throw DiscoveryError.missingPath(standardized.path)
            }
            let resolved = standardized.resolvingSymlinksInPath()
            guard Self.isWithinRoot(resolved, root: root) else {
                throw DiscoveryError.pathOutsideRoot(standardized.path)
            }
            let values = try standardized.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                result.append(contentsOf: try discoverDirectory(standardized, root: root))
            } else if let source = try discoveredFile(standardized, root: root) {
                result.append(source)
            }
        }
        return Array(Set(result)).sorted { $0.relativePath < $1.relativePath }
    }

    private func discoverDirectory(_ directory: URL, root: URL) throws -> [DiscoveredSource] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var result: [DiscoveredSource] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == true {
                if excludedComponents.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            if values.isRegularFile == true, let source = try discoveredFile(url, root: root) {
                result.append(source)
            }
        }
        return result
    }

    private func discoveredFile(_ url: URL, root: URL) throws -> DiscoveredSource? {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isWithinRoot(resolved, root: root) else { return nil }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let relative = String(resolved.path.dropFirst(rootPath.count)).replacingOccurrences(of: "\\", with: "/")
        if relative.split(separator: "/").contains(where: { excludedComponents.contains(String($0)) }) { return nil }
        let kind: SourceKind?
        if url.pathExtension == "swift" {
            kind = .swift
        } else if url.lastPathComponent == "Info.plist" {
            kind = .propertyList
        } else if url.lastPathComponent == "project.pbxproj" {
            kind = .xcodeProject
        } else {
            kind = nil
        }
        return kind.map { DiscoveredSource(url: resolved, relativePath: relative, kind: $0) }
    }

    private static func isWithinRoot(_ url: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path == root.path || url.path.hasPrefix(rootPath)
    }
}

extension DiscoveredSource: Hashable {}
