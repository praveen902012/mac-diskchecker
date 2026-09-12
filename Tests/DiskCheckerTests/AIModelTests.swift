import Foundation

@main
struct AIModelTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let model = DiskModel()
        model.checkAI()
        precondition(!model.aiBusy && !model.showAI, "A completed storage scan is required")
        model.result = try DiskScanner.scan(root, cancellation: ScanCancellation())
        model.checkAI()
        precondition(model.aiBusy && model.busy && model.showAI)
        let activePath = model.aiPath
        model.scan(root)
        precondition(!model.scanning && model.aiPath == activePath, "Storage scans must not overlap AI inspection")
        model.reviewDesktopScreenshots()
        precondition(!model.screenshotBusy, "Screenshot operations must not overlap AI inspection")
        model.cancelAI()
        for _ in 0..<500 {
            if !model.aiBusy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!model.aiBusy && model.aiReport != nil, "Cancellation must finish with a report")
        // Starting a fresh disk scan invalidates previous provenance results,
        // including when the disk scan later fails or is cancelled.
        model.scan(root.appendingPathComponent("missing"))
        precondition(model.aiReport == nil && model.aiPath.isEmpty)
        for _ in 0..<500 {
            if !model.scanning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!model.scanning && model.aiReport == nil)
        precondition(model.result != nil, "Failed rescans preserve prior storage results")
        print("PASS: AI model eligibility, busy guards, cancellation completion, and stale-report invalidation")
    }
}
