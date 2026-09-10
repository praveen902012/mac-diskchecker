#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
ICONSET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon-source.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" Assets/AppIcon-source.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output .build/AppIcon.icns "$ICONSET"
