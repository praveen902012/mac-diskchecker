import Foundation
import ImageIO
import CoreGraphics
import zlib

private struct FixtureImageType {
    let identifier: String
    static let png = FixtureImageType(identifier: "public.png")
    static let jpeg = FixtureImageType(identifier: "public.jpeg")
    static let tiff = FixtureImageType(identifier: "public.tiff")
    static let heic = FixtureImageType(identifier: "public.heic")
}

extension ScannerTests {
    func testAIMetadata() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func chunk(_ kind: String, _ payload: Data) -> Data {
            func be(_ value: UInt32) -> Data { var v = value.bigEndian; return withUnsafeBytes(of: &v) { Data($0) } }
            let checked = Data(kind.utf8) + payload
            let crc = checked.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(checked.count)) }
            return be(UInt32(payload.count)) + checked + be(UInt32(crc))
        }
        // Valid 64x64 pixel image; inject metadata before IEND.
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        func encoded(_ type: FixtureImageType, software: String? = nil) -> Data {
            let data = NSMutableData()
            let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
            var props: [CFString: Any] = [:]
            if let software = software { props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFSoftware: software] }
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
            expect(CGImageDestinationFinalize(dest))
            return data as Data
        }
        let base = encoded(.png)
        func png(_ name: String, key: String = "Software", value: String, compressed: Bool = false) throws -> URL {
            var text = Data(value.utf8)
            var payload = Data(key.utf8) + Data([0])
            if compressed {
                var result = [UInt8](repeating: 0, count: Int(compressBound(uLong(text.count))))
                var length = uLongf(result.count)
                let code = text.withUnsafeBytes { compress(&result, &length, $0.bindMemory(to: Bytef.self).baseAddress, uLong(text.count)) }
                expect(code == Z_OK)
                text = Data(result.prefix(Int(length)))
                payload.append(0)
            }
            payload.append(text)
            let url = root.appendingPathComponent(name + ".png")
            try (Data(base.dropLast(12)) + chunk(compressed ? "zTXt" : "tEXt", payload) + Data(base.suffix(12))).write(to: url)
            return url
        }
        let positive = try png("generator", value: "ComfyUI")
        equal(AIMetadata.inspect(positive).status, .hints)
        equal(AIMetadata.inspect(try png("compressed", value: "Stable Diffusion", compressed: true)).status, .hints)
        equal(AIMetadata.inspect(try png("parameters", key: "parameters", value: "a cat\nSteps: 20, Sampler: Euler, CFG scale: 7, Seed: 42")).status, .hints)
        equal(AIMetadata.inspect(try png("graph", key: "prompt", value: #"{"3":{"class_type":"KSampler","inputs":{"seed":42}}}"#)).status, .hints)
        for (name, key, value) in [("AI Midjourney", "Description", "AI created using Midjourney"), ("editor", "Software", "Adobe Photoshop"), ("prompt", "prompt", "a cat"), ("generic", "Software", "AI"), ("substring", "Software", "NotComfyUI")] {
            equal(AIMetadata.inspect(try png(name, key: key, value: value)).status, .none)
        }
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:CreatorTool="ComfyUI"/></rdf:RDF></x:xmpmeta>
        """
        let xmpURL = root.appendingPathComponent("xmp.png")
        let xmpPayload = Data("XML:com.adobe.xmp".utf8) + Data([0, 0, 0, 0, 0]) + Data(xmp.utf8)
        try (Data(base.dropLast(12)) + chunk("iTXt", xmpPayload) + Data(base.suffix(12))).write(to: xmpURL)
        equal(AIMetadata.inspect(xmpURL).status, .hints)
        let badCRC = root.appendingPathComponent("bad-crc.png")
        var corrupt = chunk("tEXt", Data("Software\0ComfyUI".utf8))
        corrupt[corrupt.count - 1] ^= 1
        try (Data(base.dropLast(12)) + corrupt + Data(base.suffix(12))).write(to: badCRC)
        equal(AIMetadata.inspect(badCRC).status, .unreadable)
        let clean = root.appendingPathComponent("stripped.png")
        try base.write(to: clean)
        equal(AIMetadata.inspect(clean).status, .none)
        for (ext, type) in [("jpg", FixtureImageType.jpeg), ("tiff", FixtureImageType.tiff), ("heic", FixtureImageType.heic)] {
            let url = root.appendingPathComponent("tagged." + ext)
            try encoded(type, software: "ComfyUI").write(to: url)
            equal(AIMetadata.inspect(url).status, .hints)
        }
        let malformed = root.appendingPathComponent("bad.png")
        try Data([1, 2, 3]).write(to: malformed)
        equal(AIMetadata.inspect(malformed).status, .unreadable)
        equal(AIMetadata.inspect(root.appendingPathComponent("missing.jpg")).status, .unreadable)
        let unreadable = try png("unreadable", value: "ComfyUI")
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        equal(AIMetadata.inspect(unreadable).status, .unreadable)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path)
        let large = root.appendingPathComponent("large.jpg")
        try Data(repeating: 0, count: AIMetadata.limit + 1).write(to: large)
        equal(AIMetadata.inspect(large).status, .unreadable)
        let bomb = try png("bomb", value: String(repeating: "x", count: AIMetadata.limit + 1), compressed: true)
        equal(AIMetadata.inspect(bomb).status, .unreadable)
        let oversized = try png("oversized", value: String(repeating: "x", count: AIMetadata.limit + 1))
        equal(AIMetadata.inspect(oversized).status, .unreadable)
        let link = root.appendingPathComponent("link.png")
        try fm.createSymbolicLink(at: link, withDestinationURL: positive)
        equal(AIMetadata.inspect(link).status, .unreadable)
        try Data().write(to: root.appendingPathComponent("file.txt"))
        let token = ScanCancellation()
        let report = AIMetadata.scan(root, cancellation: token)
        expect(report.matches >= 7)
        expect(report.items.contains { $0.status == .unsupported })
        expect(report.items.contains { $0.url.lastPathComponent == "link.png" && $0.status == .unreadable })
        token.cancel()
        let cancelled = AIMetadata.scan(root, cancellation: token)
        expect(cancelled.cancelled)
        expect(cancelled.items.isEmpty)
        let midToken = ScanCancellation()
        let partial = AIMetadata.scan(root, cancellation: midToken) { _, _ in midToken.cancel() }
        expect(partial.cancelled)
        expect(partial.items.count < report.items.count)
        print("PASS: AI metadata formats, generator hints, negatives, malformed data, limits, symlinks, and cancellation")
    }
}
