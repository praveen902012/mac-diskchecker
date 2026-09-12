import Foundation

@main
struct ScannerTests {
    static func main() throws {
        let suite = ScannerTests()
        try suite.testAIMetadata()
        try suite.testAccountingAndLinks()
        try suite.testCancellation()
        suite.testMissingRoot()
        try suite.testEmptyFolder()
        try suite.testUnreadableFolder()
        try suite.testTrashEligibility()
        try suite.testDesktopScreenshots()
        print("PASS: accounting, hidden files, hard links, symbolic links, cancellation, missing roots, empty folders, unreadable folders, Trash eligibility, and Desktop screenshot cleanup")
    }
    func testDesktopScreenshots() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let desktop = root.appendingPathComponent("Desktop")
        let nested = desktop.appendingPathComponent("Nested")
        let destination = root.appendingPathComponent("Test Trash")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let names = ["Screenshot 2026-09-11 at 10.22.33 AM.png", "Screen Shot 2026-09-10 at 09.01.02.png", "Screenshot 2026-09-11 at 10.22.33 PM (2).PNG"]
        for name in names { try Data([1, 2, 3]).write(to: desktop.appendingPathComponent(name)) }
        try Data([4]).write(to: desktop.appendingPathComponent("holiday.png"))
        try Data([4]).write(to: desktop.appendingPathComponent("Screenshot notes.png"))
        try Data([4]).write(to: nested.appendingPathComponent(names[0]))
        try fm.createDirectory(at: desktop.appendingPathComponent("Screenshot 2026-09-11 at 01.02.03.png"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: desktop.appendingPathComponent("Screenshot 2026-09-11 at 01.02.04.png"), withDestinationURL: desktop.appendingPathComponent(names[0]))
        let review = try DesktopScreenshots.find(in: desktop)
        equal(Set(review.items.map { $0.url.lastPathComponent }), Set(names))
        expect(review.issues.isEmpty)
        expect(!DesktopScreenshots.matchesName(URL(fileURLWithPath: "Screenshot 2026-09-11 at 10.22.33.txt")))
        expect(DesktopScreenshots.matchesName(URL(fileURLWithPath: "Screenshot 2026-09-11 at 10.22.33\u{202f}PM.png")))
        // New files after review must not join the confirmed batch.
        let newFile = desktop.appendingPathComponent("Screenshot 2026-09-11 at 11.00.00.png")
        try Data([9]).write(to: newFile)
        let changed = review.items[0]
        try Data([1, 2, 3, 4, 5]).write(to: changed.url)
        var attempted: [URL] = []
        let outcome = DesktopScreenshots.moveToTrash(review.items, in: desktop) { url in
            attempted.append(url)
            if url == review.items[1].url { throw CocoaError(.fileWriteNoPermission) }
            try fm.moveItem(at: url, to: destination.appendingPathComponent(url.lastPathComponent))
        }
        equal(outcome.moved, 1)
        equal(outcome.issues.count, 2)
        equal(attempted.count, 2)
        expect(!attempted.contains(changed.url))
        expect(fm.fileExists(atPath: changed.url.path))
        expect(fm.fileExists(atPath: newFile.path))
        expect(fm.fileExists(atPath: nested.appendingPathComponent(names[0]).path))
        expect(fm.fileExists(atPath: desktop.appendingPathComponent("holiday.png").path))
        // A reviewed item cannot be moved when it is outside the approved Desktop.
        let outside = DesktopScreenshots.moveToTrash([review.items[1]], in: nested) { _ in
            preconditionFailure("Out-of-scope item reached move operation")
        }
        equal(outside.moved, 0)
        equal(outside.issues.count, 1)
        throwsError(try DesktopScreenshots.find(in: root.appendingPathComponent("Missing")))
        equal(try DesktopScreenshots.find(in: destination).items.count, 1)
    }
    func testTrashEligibility() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let roots = ["Desktop", "Downloads", "Documents"].map { home.appendingPathComponent($0) }
        for root in roots { try fm.createDirectory(at: root, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: home) }
        func item(_ url: URL, bytes: Int64 = 1_000_000_001, directory: Bool = false) -> ScanNode {
            ScanNode(id: 0, url: url, parent: nil, isDirectory: directory, bytes: bytes)
        }
        for root in roots {
            expect(TrashPolicy.allows(item(root.appendingPathComponent("large.bin")), roots: roots))
            expect(TrashPolicy.allows(item(root.appendingPathComponent("nested/large.bin")), roots: roots))
            expect(TrashPolicy.allows(item(root.appendingPathComponent("large-folder"), directory: true), roots: roots))
            expect(!TrashPolicy.allows(item(root, directory: true), roots: roots))
            for bytes: Int64 in [0, 999_999_999, 1_000_000_000] {
                expect(!TrashPolicy.allows(item(root.appendingPathComponent("small.bin"), bytes: bytes), roots: roots))
            }
        }
        expect(!TrashPolicy.allows(item(home.appendingPathComponent("Pictures/large.bin")), roots: roots))
        expect(!TrashPolicy.allows(item(home.appendingPathComponent("Downloads-old/large.bin")), roots: roots))
        expect(!TrashPolicy.allows(item(roots[0].appendingPathComponent("../large.bin")), roots: roots))
        let escape = roots[0].appendingPathComponent("escape")
        try fm.createSymbolicLink(at: escape, withDestinationURL: home)
        expect(!TrashPolicy.allows(item(escape.appendingPathComponent("large.bin")), roots: roots))
        expect(!TrashPolicy.allows(item(escape, directory: true), roots: roots))
    }
    func testAccountingAndLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/data.bin")
        try Data(repeating: 42, count: 32768).write(to: file)
        try Data(repeating: 7, count: 8192).write(to: root.appendingPathComponent(".hidden"))
        try fm.linkItem(at: file, to: root.appendingPathComponent("hard-link"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let result = try DiskScanner.scan(root, cancellation: ScanCancellation())
        expect(result.issues.isEmpty)
        equal(result.fileCount, 3)
        expect(!result.nodes.contains { $0.name == "loop" })
        expect(result.nodes.contains { $0.name == ".hidden" })
        let allocated = try [file, root.appendingPathComponent(".hidden")].reduce(Int64(0)) { sum, url in
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            return sum + Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        equal(result.nodes[0].bytes, allocated)
        for node in result.nodes where node.isDirectory {
            equal(node.bytes, node.children.reduce(0) { $0 + result.nodes[$1].bytes })
        }
    }
    func testCancellation() throws {
        let token = ScanCancellation()
        token.cancel()
        throwsError(try DiskScanner.scan(FileManager.default.temporaryDirectory, cancellation: token)) {
            expect($0 is ScanCancelled)
        }
    }
    func testMissingRoot() {
        throwsError(try DiskScanner.scan(URL(fileURLWithPath: "/nonexistent-\(UUID())"), cancellation: ScanCancellation()))
    }
    func testEmptyFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try DiskScanner.scan(root, cancellation: ScanCancellation())
        equal(result.nodes.count, 1)
        equal(result.nodes[0].bytes, 0)
        expect(result.issues.isEmpty)
    }
    func testUnreadableFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let blocked = root.appendingPathComponent("blocked")
        try fm.createDirectory(at: blocked, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
            try? fm.removeItem(at: root)
        }
        let result = try DiskScanner.scan(root, cancellation: ScanCancellation())
        expect(result.issues.contains { $0.contains(blocked.path) })
        equal(result.nodes[0].bytes, 0)
    }
}

func expect(_ condition: @autoclosure () -> Bool, line: UInt = #line) {
    precondition(condition(), "Assertion failed at line \(line)")
}
func equal<T: Equatable>(_ left: T, _ right: T) {
    precondition(left == right, "Expected \(left) to equal \(right)")
}
func throwsError<T>(_ operation: @autoclosure () throws -> T, check: (Error) -> Void = { _ in }) {
    do { _ = try operation(); preconditionFailure("Expected an error") }
    catch { check(error) }
}
