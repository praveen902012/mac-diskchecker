import Foundation

// The AppKit compatibility build is compiled with Catalina's Swift 5.3 tools.
// Modern builds retain compiler-checked transferability and progress closures.
#if compiler(>=5.5)
typealias DiskTransferable = Sendable
typealias ScanProgress = @Sendable (Int, String) -> Void
extension ScanCancellation: @unchecked Sendable {}
#else
protocol DiskTransferable {}
typealias ScanProgress = (Int, String) -> Void
#endif

struct ScanCancelled: Error {}
