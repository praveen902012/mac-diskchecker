#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/catalina-cache
swiftc -swift-version 5 -target x86_64-apple-macosx10.15.7 \
    -module-cache-path "$PWD/.build/catalina-cache" \
    Sources/DiskChecker/Compatibility.swift Sources/DiskChecker/Scanner.swift \
    Sources/DiskChecker/TrashPolicy.swift Sources/DiskChecker/DesktopScreenshots.swift \
    Sources/DiskChecker/AIMetadata.swift Tests/DiskCheckerTests/AIMetadataTests.swift \
    Tests/DiskCheckerTests/ScannerTests.swift -o .build/catalina-tests
.build/catalina-tests
