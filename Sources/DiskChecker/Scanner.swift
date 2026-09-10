import Foundation
import Darwin

struct ScanNode: Identifiable, Sendable {
    let id: Int
    let url: URL
    let parent: Int?
    let isDirectory: Bool
    var bytes: Int64 = 0
    var children: [Int] = []
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

struct ScanResult: Sendable {
    var nodes: [ScanNode]
    var issues: [String]
    var fileCount: Int
}

final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.withLock { value = true } }
    var isCancelled: Bool { lock.withLock { value } }
}

enum DiskScanner {
    static func scan(_ root: URL, cancellation: ScanCancellation,
                     progress: @Sendable (Int, String) -> Void = { _, _ in }) throws -> ScanResult {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0,
              (rootStat.st_mode & S_IFMT) == S_IFDIR else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var nodes = [ScanNode(id: 0, url: root, parent: nil, isDirectory: true)]
        var pending = [0]
        var issues: [String] = []
        var identities = Set<String>()
        var fileCount = 0
        var lastProgress = Date.distantPast
        while let parent = pending.popLast() {
            if cancellation.isCancelled { throw CancellationError() }
            let urls: [URL]
            do {
                urls = try fm.contentsOfDirectory(at: nodes[parent].url,
                    includingPropertiesForKeys: Array(keys), options: [])
            } catch {
                issues.append("\(nodes[parent].url.path): \(error.localizedDescription)")
                continue
            }
            for url in urls {
                if cancellation.isCancelled { throw CancellationError() }
                do {
                    let values = try url.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true { continue }
                    var info = stat()
                    guard lstat(url.path, &info) == 0 else {
                        issues.append("\(url.path): Could not read file information.")
                        continue
                    }
                    guard info.st_dev == rootStat.st_dev else {
                        issues.append("\(url.path): Skipped a different mounted volume.")
                        continue
                    }
                    let directory = values.isDirectory == true
                    guard directory || (info.st_mode & S_IFMT) == S_IFREG else { continue }
                    let id = nodes.count
                    var bytes: Int64 = 0
                    if !directory {
                        fileCount += 1
                        let identity = "\(info.st_dev):\(info.st_ino)"
                        if identities.insert(identity).inserted {
                            bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
                        }
                    }
                    nodes.append(ScanNode(id: id, url: url, parent: parent, isDirectory: directory, bytes: bytes))
                    nodes[parent].children.append(id)
                    if directory { pending.append(id) }
                } catch {
                    issues.append("\(url.path): \(error.localizedDescription)")
                }
            }
            if Date().timeIntervalSince(lastProgress) > 0.15 {
                lastProgress = Date()
                progress(fileCount, nodes[parent].url.path)
            }
        }
        for id in nodes.indices.reversed() {
            if let parent = nodes[id].parent { nodes[parent].bytes += nodes[id].bytes }
        }
        if cancellation.isCancelled { throw CancellationError() }
        return ScanResult(nodes: nodes, issues: issues, fileCount: fileCount)
    }
}
