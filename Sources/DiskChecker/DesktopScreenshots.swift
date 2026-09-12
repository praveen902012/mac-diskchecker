import Foundation
import Darwin

struct DesktopScreenshot: Identifiable, DiskTransferable {
    var id: URL { url }
    let url: URL
    let bytes: Int64
    let fingerprint: String
}

struct ScreenshotSearch: DiskTransferable {
    var items: [DesktopScreenshot] = []
    var issues: [String] = []
}

struct ScreenshotCleanup: DiskTransferable {
    var moved = 0
    var issues: [String] = []
}

enum DesktopScreenshots {
    static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    static func matchesName(_ url: URL) -> Bool {
        guard ["png", "jpg", "jpeg", "heic", "tif", "tiff", "pdf"].contains(url.pathExtension.lowercased()) else { return false }
        let pattern = #"^(?:Screenshot|Screen Shot) \d{4}-\d{2}-\d{2} (?:at )?\d{1,2}[.:]\d{2}[.:]\d{2}(?:[ .\x{202f}\x{00a0}]*(?:AM|PM))?(?: \(\d+\))?$"#
        return url.deletingPathExtension().lastPathComponent.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func inspect(_ url: URL) throws -> DesktopScreenshot? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let marked = (NSMetadataItem(url: url)?.value(forAttribute: "kMDItemIsScreenCapture") as? NSNumber)?.boolValue == true
        guard marked || matchesName(url) else { return nil }
        let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        let fingerprint = "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        return DesktopScreenshot(url: url, bytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0), fingerprint: fingerprint)
    }

    static func find(in desktop: URL = desktop) throws -> ScreenshotSearch {
        var result = ScreenshotSearch()
        // Only direct Desktop files; never descend into folders or follow links.
        for url in try FileManager.default.contentsOfDirectory(at: desktop, includingPropertiesForKeys: nil) {
            do { if let item = try inspect(url) { result.items.append(item) } }
            catch { result.issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        result.items.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        return result
    }

    static func moveToTrash(_ items: [DesktopScreenshot], in desktop: URL = desktop,
                            move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> ScreenshotCleanup {
        var result = ScreenshotCleanup()
        for item in items {
            do {
                guard item.url.deletingLastPathComponent().standardizedFileURL == desktop.standardizedFileURL,
                      let current = try inspect(item.url), current.fingerprint == item.fingerprint else {
                    result.issues.append("\(item.url.lastPathComponent): Changed since review or is no longer an eligible Desktop screenshot. Review again.")
                    continue
                }
                try move(item.url)
                result.moved += 1
            } catch { result.issues.append("\(item.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }
}
