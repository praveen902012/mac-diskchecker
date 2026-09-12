#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${1:?Pass a synthetic ai-ui-fixtures directory containing AI example.png, Ordinary image.png, and Notes.txt}"
mkdir -p .build/catalina-cache
swiftc -swift-version 5 -target x86_64-apple-macosx10.15.7 \
    -module-cache-path "$PWD/.build/catalina-cache" -parse-as-library -D CATALINA_UI_TESTS \
    Sources/DiskCheckerCatalina/App.swift Sources/DiskChecker/Compatibility.swift \
    Sources/DiskChecker/Scanner.swift Sources/DiskChecker/AIMetadata.swift \
    Sources/DiskChecker/TrashPolicy.swift Sources/DiskChecker/DesktopScreenshots.swift \
    -o .build/catalina-ui-tests
.build/catalina-ui-tests "$1"
