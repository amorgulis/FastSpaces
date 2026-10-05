#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
swift build --disable-sandbox --cache-path "$project_root/.build/cache" --package-path "$project_root" --product GestureProbe
binary_dir="$(swift build --disable-sandbox --cache-path "$project_root/.build/cache" --package-path "$project_root" --show-bin-path)"
app="$project_root/dist/Fast Spaces Probe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/GestureProbe" "$app/Contents/MacOS/GestureProbe"
cp "$project_root/Resources/Probe-Info.plist" "$app/Contents/Info.plist"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
codesign --force --sign - --identifier local.fastspaces.probe "$app"
codesign --verify --strict "$app"
echo "Built: $app"
