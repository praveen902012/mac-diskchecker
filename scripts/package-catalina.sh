#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Run with Catalina's Command Line Tools (Swift 5.3+) on an Intel Mac.
# Some newer Apple silicon toolchains no longer ship Intel back-deployment libs.
if [[ "$(uname -m)" != x86_64 ]]; then
    echo 'Build this compatibility app on an Intel Mac with Apple Command Line Tools.' >&2
    exit 1
fi
mkdir -p .build/catalina-cache dist/catalina
swiftc -swift-version 5 -target x86_64-apple-macosx10.15.7 \
    -module-cache-path "$PWD/.build/catalina-cache" -parse-as-library -O \
    Sources/DiskCheckerCatalina/App.swift Sources/DiskChecker/Compatibility.swift \
    Sources/DiskChecker/Scanner.swift Sources/DiskChecker/AIMetadata.swift \
    Sources/DiskChecker/TrashPolicy.swift Sources/DiskChecker/DesktopScreenshots.swift \
    -o .build/DiskChecker-Catalina
APP='dist/catalina/Disk Checker.app'
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/DiskChecker-Catalina "$APP/Contents/MacOS/DiskChecker"
if [[ -f .build/AppIcon.icns ]]; then
    cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    ./scripts/build-icon.sh
    cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DiskChecker</string>
<key>CFBundleIdentifier</key><string>local.diskchecker.app</string>
<key>CFBundleName</key><string>Disk Checker Catalina</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>10.15.7</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (Intel, macOS Catalina 10.15.7+)"
