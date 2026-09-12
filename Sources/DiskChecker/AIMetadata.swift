import Foundation
import ImageIO
import Darwin
import zlib

enum AIInspectionStatus: String, DiskTransferable {
    case hints = "AI metadata hints"
    case none = "No hints found"
    case unsupported = "Unsupported"
    case unreadable = "Could not inspect"
}

struct AIEvidence: DiskTransferable, Equatable {
    let field: String
    let value: String
    let tool: String
}

struct AIInspection: Identifiable, DiskTransferable {
    let url: URL
    let bytes: Int64
    let status: AIInspectionStatus
    let evidence: [AIEvidence]
    let detail: String
    var id: URL { url }
}

struct AIReport: DiskTransferable {
    var items: [AIInspection] = []
    var cancelled = false
    var issues: [String] = []
    var inspected: Int { items.filter { $0.status == .hints || $0.status == .none }.count }
    var matches: Int { items.filter { $0.status == .hints }.count }
    var skipped: Int { items.count - inspected }
}

enum AIMetadata {
    static let limit = 8 * 1024 * 1024
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"]
    enum Failure: Error { case malformed, limit }

    static func scan(_ root: URL, cancellation: ScanCancellation,
                     progress: ScanProgress = { _, _ in }) -> AIReport {
        var report = AIReport()
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR else {
            report.issues = ["Folder is no longer accessible."]
            return report
        }
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var pending = [root.resolvingSymlinksInPath()]
        var lastProgress = Date.distantPast
        while let directory = pending.popLast() {
            if cancellation.isCancelled { break }
            do {
                var directoryInfo = stat()
                guard lstat(directory.path, &directoryInfo) == 0,
                      directoryInfo.st_mode & S_IFMT == S_IFDIR, directoryInfo.st_dev == rootInfo.st_dev,
                      directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path else {
                    report.issues.append("\(directory.path): Folder changed or contains a symbolic link.")
                    continue
                }
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) {
                    if cancellation.isCancelled { break }
                    var info = stat()
                    guard lstat(url.path, &info) == 0 else {
                        report.items.append(failed(url, "File is no longer accessible.")); continue
                    }
                    guard info.st_dev == rootInfo.st_dev, info.st_mode & S_IFMT != S_IFLNK else {
                        report.items.append(failed(url, "Skipped symbolic link or another volume.")); continue
                    }
                    if info.st_flags & UInt32(SF_DATALESS) != 0 {
                        report.items.append(failed(url, "Skipped cloud item that is not downloaded.")); continue
                    }
                    let values = try url.resourceValues(forKeys: Set(keys))
                    if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current && values.ubiquitousItemDownloadingStatus != .downloaded {
                        report.items.append(failed(url, "Skipped cloud item that is not downloaded.")); continue
                    }
                    if info.st_mode & S_IFMT == S_IFDIR { pending.append(url); continue }
                    guard info.st_mode & S_IFMT == S_IFREG else { continue }
                    report.items.append(inspect(url, bytes: Int64(info.st_blocks) * 512, device: rootInfo.st_dev))
                    if Date().timeIntervalSince(lastProgress) > 0.15 {
                        progress(report.items.count, url.lastPathComponent)
                        lastProgress = Date()
                    }
                }
            } catch { report.issues.append("\(directory.path): \(error.localizedDescription)") }
        }
        report.cancelled = cancellation.isCancelled
        report.items.sort { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes }
        return report
    }

    static func failed(_ url: URL, _ detail: String, bytes: Int64 = 0) -> AIInspection {
        AIInspection(url: url, bytes: bytes, status: .unreadable, evidence: [], detail: detail)
    }

    static func inspect(_ url: URL, bytes: Int64 = 0, device: dev_t? = nil) -> AIInspection {
        guard extensions.contains(url.pathExtension.lowercased()) else {
            return AIInspection(url: url, bytes: bytes, status: .unsupported, evidence: [], detail: "Supports PNG, JPEG, HEIC, and TIFF images.")
        }
        var before = stat()
        guard lstat(url.path, &before) == 0, before.st_flags & UInt32(SF_DATALESS) == 0 else {
            return failed(url, "Image is unavailable or not downloaded.", bytes: bytes)
        }
        // O_NOFOLLOW prevents a replaced leaf from becoming a followed symbolic link.
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return failed(url, "Unable to open image.", bytes: bytes) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              (device == nil || info.st_dev == device), info.st_ino == before.st_ino, info.st_dev == before.st_dev else {
            return failed(url, "File changed or is not a regular file on this volume.", bytes: bytes)
        }
        do {
            var fields: [(String, String)] = []
            if url.pathExtension.lowercased() == "png" {
                fields = try pngFields(handle, size: UInt64(info.st_size))
            } else {
                // Bound ImageIO's input as well as extracted metadata. Large non-PNG
                // containers are explicitly incomplete rather than silently negative.
                guard info.st_size <= limit else { throw Failure.limit }
                let data = try handle.read(upToCount: Int(info.st_size)) ?? Data()
                guard data.count <= limit,
                      let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetCount(source) > 0,
                      CGImageSourceGetStatus(source) == .statusComplete else { throw Failure.malformed }
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) {
                    flatten(properties as NSDictionary, prefix: "", into: &fields)
                }
                if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
                    CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                        if let value = CGImageMetadataTagCopyValue(tag) { fields.append((path as String, String(describing: value))) }
                        return true
                    }
                }
                guard fields.reduce(0, { $0 + $1.0.utf8.count + $1.1.utf8.count }) <= limit else { throw Failure.limit }
            }
            var after = stat()
            guard fstat(fd, &after) == 0, after.st_size == info.st_size,
                  after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { throw Failure.malformed }
            let evidence = classify(fields)
            return AIInspection(url: url, bytes: bytes, status: evidence.isEmpty ? .none : .hints,
                                evidence: evidence, detail: evidence.isEmpty ? "No recognized AI metadata hints in supported fields." : "Unverified embedded metadata suggests AI involvement.")
        } catch Failure.limit {
            return failed(url, "Inspection exceeded the 8 MiB input or metadata limit; results are incomplete.", bytes: bytes)
        } catch {
            return failed(url, "Malformed, changed, or unreadable image metadata.", bytes: bytes)
        }
    }

    static func flatten(_ dictionary: NSDictionary, prefix: String, into fields: inout [(String, String)]) {
        for (key, value) in dictionary {
            let path = prefix + "/" + String(describing: key)
            if let nested = value as? NSDictionary { flatten(nested, prefix: path, into: &fields) }
            else if let string = value as? String { fields.append((path, string)) }
        }
    }

    static func classify(_ fields: [(String, String)]) -> [AIEvidence] {
        var evidence: [AIEvidence] = []
        for (field, value) in fields {
            let key = field.lowercased()
            let lower = value.lowercased()
            var tool: String?
            if key.contains("software") || key.contains("creatortool") || key.hasSuffix("/creator") || key == "creator" {
                for name in ["Stable Diffusion", "AUTOMATIC1111", "ComfyUI", "Midjourney", "DALL-E", "DALL·E", "Adobe Firefly", "InvokeAI", "NovelAI"] {
                    let escaped = NSRegularExpression.escapedPattern(for: name.lowercased())
                    if lower.range(of: "(?<![a-z0-9])" + escaped + "(?![a-z0-9])", options: .regularExpression) != nil { tool = name; break }
                }
            }
            if key == "parameters" || key.contains("usercomment") || key.contains("description") {
                if lower.range(of: #"steps:\s*\d+.*sampler:\s*[^,]+,.*cfg scale:\s*[\d.]+.*seed:\s*\d+"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    tool = "Stable Diffusion parameters"
                }
            }
            if key == "prompt", let data = value.data(using: .utf8),
               let graph = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]],
               graph.values.contains(where: { node in
                   guard let name = node["class_type"] as? String, node["inputs"] is [String: Any] else { return false }
                   return ["KSampler", "KSamplerAdvanced", "SamplerCustom", "SamplerCustomAdvanced"].contains(name)
               }) { tool = "ComfyUI generation graph" }
            if let tool = tool {
                let item = AIEvidence(field: field, value: String(value.prefix(4096)), tool: tool)
                if !evidence.contains(item) { evidence.append(item) }
            }
        }
        return evidence
    }

    // PNG eXIf is a TIFF metadata directory, not necessarily a decodable image.
    static func exifFields(_ data: Data) throws -> [(String, String)] {
        let bytes = Array(data)
        guard bytes.count >= 8 else { throw Failure.malformed }
        let little = bytes[0] == 73 && bytes[1] == 73
        guard little || (bytes[0] == 77 && bytes[1] == 77) else { throw Failure.malformed }
        func number(_ offset: Int, _ length: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - length else { throw Failure.malformed }
            let slice = Array(bytes[offset..<(offset + length)])
            return (little ? Array(slice.reversed()) : slice).reduce(0) { ($0 << 8) | Int($1) }
        }
        guard try number(2, 2) == 42 else { throw Failure.malformed }
        var pending = [try number(4, 4)]
        var seen = Set<Int>()
        var fields: [(String, String)] = []
        while let offset = pending.popLast(), offset != 0 {
            guard seen.insert(offset).inserted, seen.count <= 32 else { throw Failure.malformed }
            let count = try number(offset, 2)
            guard count <= 4096 else { throw Failure.limit }
            for index in 0..<count {
                let entry = offset + 2 + index * 12
                let tag = try number(entry, 2)
                let type = try number(entry + 2, 2)
                let length = try number(entry + 4, 4)
                let pointer = try number(entry + 8, 4)
                if tag == 34665, type == 4, length == 1 { pending.append(pointer) }
                guard let key = [305: "Software", 270: "Description", 315: "Creator", 37510: "UserComment"][tag],
                      [1, 2, 7].contains(type) else { continue }
                let start = length <= 4 ? entry + 8 : pointer
                guard length <= bytes.count, start <= bytes.count - length else { throw Failure.malformed }
                var value = Data(bytes[start..<(start + length)])
                if tag == 37510, value.starts(with: Data("ASCII\0\0\0".utf8)) { value = Data(value.dropFirst(8)) }
                if let text = String(data: value, encoding: .utf8) ?? String(data: value, encoding: .isoLatin1) {
                    fields.append((key, text.trimmingCharacters(in: .controlCharacters)))
                }
            }
            let next = try number(offset + 2 + count * 12, 4)
            if next != 0 { pending.append(next) }
        }
        return fields
    }

    // Read PNG metadata without loading pixel data. Both encoded text and inflated
    // output consume a shared budget, preventing compressed metadata bombs.
    static func pngFields(_ handle: FileHandle, size: UInt64) throws -> [(String, String)] {
        func read(_ count: Int) throws -> Data {
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw Failure.malformed }
            return data
        }
        guard try read(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else { throw Failure.malformed }
        var budget = limit
        var fields: [(String, String)] = []
        var sawHeader = false
        var sawPixels = false
        var chunks = 0
        while try handle.offset() < size {
            chunks += 1
            guard chunks <= 100_000 else { throw Failure.limit }
            let header = try read(8)
            let length = header.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            let kind = String(decoding: header.suffix(4), as: UTF8.self)
            let offset = try handle.offset()
            guard UInt64(length) + 4 <= size - offset else { throw Failure.malformed }
            guard sawHeader || (kind == "IHDR" && length == 13) else { throw Failure.malformed }
            sawHeader = true
            if ["tEXt", "zTXt", "iTXt", "eXIf"].contains(kind) {
                guard length <= budget else { throw Failure.limit }
                budget -= length
                let payload = try read(length)
                let storedCRC = try read(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                let checked = Data(header.suffix(4)) + payload
                let crc = checked.withUnsafeBytes { raw in crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(checked.count)) }
                guard UInt32(crc) == storedCRC else { throw Failure.malformed }
                if kind == "eXIf" {
                    fields.append(contentsOf: try exifFields(payload))
                    continue
                }
                let bytes = Array(payload)
                guard let separator = bytes.firstIndex(of: 0), separator > 0, separator <= 79 else { throw Failure.malformed }
                let key = String(decoding: bytes[..<separator], as: UTF8.self)
                var textData = Data(bytes.dropFirst(separator + 1))
                var compressed = false
                if kind == "zTXt" {
                    guard textData.first == 0 else { throw Failure.malformed }
                    textData = Data(textData.dropFirst()); compressed = true
                } else if kind == "iTXt" {
                    let rest = Array(textData)
                    guard rest.count >= 4, rest[0] <= 1, rest[1] == 0,
                          let languageEnd = rest[2...].firstIndex(of: 0),
                          languageEnd + 1 < rest.count,
                          let translatedEnd = rest[(languageEnd + 1)...].firstIndex(of: 0) else { throw Failure.malformed }
                    compressed = rest[0] == 1
                    textData = Data(rest.dropFirst(translatedEnd + 1))
                }
                if compressed {
                    guard budget > 0 else { throw Failure.limit }
                    var output = [UInt8](repeating: 0, count: budget)
                    var count = uLongf(budget)
                    let code = textData.withUnsafeBytes { raw in
                        uncompress(&output, &count, raw.bindMemory(to: Bytef.self).baseAddress, uLong(textData.count))
                    }
                    if code == Z_BUF_ERROR { throw Failure.limit }
                    guard code == Z_OK else { throw Failure.malformed }
                    budget -= Int(count)
                    textData = Data(output.prefix(Int(count)))
                }
                guard let value = String(data: textData, encoding: kind == "iTXt" ? .utf8 : .isoLatin1) else { throw Failure.malformed }
                if key == "XML:com.adobe.xmp" {
                    if let metadata = CGImageMetadataCreateFromXMPData(textData as CFData) {
                        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                            if let value = CGImageMetadataTagCopyValue(tag) { fields.append((path as String, String(describing: value))) }
                            return true
                        }
                    } else { throw Failure.malformed }
                } else { fields.append((key, value)) }
            } else {
                if kind == "IDAT" { sawPixels = true }
                try handle.seek(toOffset: offset + UInt64(length) + 4)
            }
            if kind == "IEND" {
                guard length == 0, sawPixels else { throw Failure.malformed }
                return fields
            }
        }
        throw Failure.malformed
    }
}
