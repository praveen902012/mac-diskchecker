#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/DiskChecker/Compatibility.swift Sources/DiskChecker/Scanner.swift Sources/DiskChecker/TrashPolicy.swift Sources/DiskChecker/DesktopScreenshots.swift Sources/DiskChecker/AIMetadata.swift Tests/DiskCheckerTests/AIMetadataTests.swift Tests/DiskCheckerTests/ScannerTests.swift -o .build/scanner-tests
.build/scanner-tests

# Compile the real app model without its application entry point. The generated
# copy lives only in build artifacts; production source remains unchanged.
sed '/^@main$/d' Sources/DiskChecker/App.swift > .build/App-model-tests.swift
swiftc -module-cache-path "$PWD/.build/clang-cache" -parse-as-library Sources/DiskChecker/Compatibility.swift Sources/DiskChecker/Scanner.swift Sources/DiskChecker/TrashPolicy.swift Sources/DiskChecker/DesktopScreenshots.swift Sources/DiskChecker/AIMetadata.swift Sources/DiskChecker/AIMetadataView.swift .build/App-model-tests.swift Tests/DiskCheckerTests/AIModelTests.swift -o .build/ai-model-tests
.build/ai-model-tests
