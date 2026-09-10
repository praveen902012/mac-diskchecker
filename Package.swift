// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskChecker",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DiskChecker", targets: ["DiskChecker"])],
    targets: [
        .executableTarget(name: "DiskChecker")
    ]
)
