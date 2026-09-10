#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/DiskChecker/Scanner.swift Sources/DiskChecker/TrashPolicy.swift Sources/DiskChecker/DesktopScreenshots.swift Tests/DiskCheckerTests/ScannerTests.swift -o .build/scanner-tests
.build/scanner-tests
