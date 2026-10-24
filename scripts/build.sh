#!/bin/bash
# Builds DeepSeek.app into dist/.
#
#   scripts/build.sh              Release build (universal: Apple Silicon + Intel)
#   scripts/build.sh --install    …and copy it to /Applications
#   scripts/build.sh --dmg        …and package dist/DeepSeek-<version>.dmg
#   scripts/build.sh --debug      Debug build instead of Release
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
INSTALL=0
DMG=0
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG=Debug ;;
        --install) INSTALL=1 ;;
        --dmg) DMG=1 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# Build outside the project folder: iCloud-synced folders such as ~/Documents tag bundles
# with Finder metadata, which codesign rejects ("resource fork … detritus not allowed").
DERIVED="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/DeepSeekNative}"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --use-cache --quiet
fi

echo "▸ Building $CONFIG…"
xcodebuild \
    -project DeepSeekNative.xcodeproj \
    -scheme DeepSeekNative \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -destination 'generic/platform=macOS' \
    -quiet \
    build

APP="$DERIVED/Build/Products/$CONFIG/DeepSeek.app"
codesign --verify --deep --strict "$APP"

mkdir -p dist
rm -rf dist/DeepSeek.app
ditto --noextattr --noqtn "$APP" dist/DeepSeek.app
echo "▸ Built dist/DeepSeek.app ($(du -sh "$APP" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/DeepSeek"))"

if [ "$INSTALL" = 1 ]; then
    osascript -e 'quit app id "com.sink7.DeepSeekNative"' >/dev/null 2>&1 || true
    rm -rf /Applications/DeepSeek.app
    ditto --noextattr --noqtn "$APP" /Applications/DeepSeek.app
    echo "▸ Installed /Applications/DeepSeek.app"
fi

if [ "$DMG" = 1 ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
    DMG_PATH="dist/DeepSeek-$VERSION.dmg"
    STAGING="$(mktemp -d)"
    trap 'rm -rf "$STAGING"' EXIT
    ditto --noextattr --noqtn "$APP" "$STAGING/DeepSeek.app"
    ln -s /Applications "$STAGING/Applications"
    rm -f "$DMG_PATH"
    hdiutil create -quiet -volname "DeepSeek" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
    echo "▸ Packaged $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
fi
