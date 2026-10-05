#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
swift build --disable-sandbox --cache-path "$project_root/.build/cache" --package-path "$project_root" -c release -debug-info-format none --product FastSpacesApp
binary_dir="$(swift build --disable-sandbox --cache-path "$project_root/.build/cache" --package-path "$project_root" -c release --show-bin-path)"
app="$project_root/dist/Fast Spaces.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/FastSpacesApp" "$app/Contents/MacOS/FastSpacesApp"
cp "$project_root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
codesign --force --sign - --identifier local.fastspaces.utility "$app"
codesign --verify --strict "$app"
echo "Built: $app"
