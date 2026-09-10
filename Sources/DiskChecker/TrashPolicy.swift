import Foundation

/// Eligibility uses the allocated size recorded by the latest completed scan.
enum TrashPolicy {
    static let minimumBytes: Int64 = 1_000_000_000
    static var allowedRoots: [URL] {
        let fm = FileManager.default
        return [FileManager.SearchPathDirectory.desktopDirectory, .downloadsDirectory, .documentDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first }
    }

    static func allows(_ node: ScanNode, roots: [URL] = allowedRoots) -> Bool {
        guard node.bytes > minimumBytes, node.url.isFileURL else { return false }
        let original = node.url.standardizedFileURL.path
        let resolved = node.url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(node.url.lastPathComponent)
            .resolvingSymlinksInPath().standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
            // Require both the selected path and its target to remain within the
            // same approved folder. The approved folder itself is never eligible.
            return original.hasPrefix(rootPath + "/") && resolved.hasPrefix(resolvedRoot + "/")
        }
    }
}
