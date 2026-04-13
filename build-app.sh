#!/bin/bash
set -e

INTERNAL_NAME="DeckManager"
DISPLAY_NAME="DeckManager"
BUNDLE_ID="com.kindofblue.DeckManager"
VERSION="2.0"
BUILD_DIR=".build/release"
APP_DIR="${DISPLAY_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "=== Building ${DISPLAY_NAME} (release) ==="
swift build -c release 2>&1

echo "=== Creating app bundle ==="
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

cp "${BUILD_DIR}/${INTERNAL_NAME}" "${MACOS}/${DISPLAY_NAME}"

# Copy font resources
if [ -d ".build/release/DeckManager_DeckManager.bundle" ]; then
    cp -R ".build/release/DeckManager_DeckManager.bundle" "${RESOURCES}/"
fi

cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

if [ ! -f "${RESOURCES}/AppIcon.icns" ]; then
    echo "(No custom icon — using default macOS icon)"
fi

echo "=== Packaging ==="
rm -f "${DISPLAY_NAME}.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${DISPLAY_NAME}.zip"

APP_SIZE=$(du -sh "${APP_DIR}" | cut -f1)
ZIP_SIZE=$(du -sh "${DISPLAY_NAME}.zip" | cut -f1)

echo ""
echo "=== Done ==="
echo "  App:  ${APP_DIR}  (${APP_SIZE})"
echo "  Zip:  ${DISPLAY_NAME}.zip  (${ZIP_SIZE})"
echo ""
echo "To install:"
echo "  1. Unzip ${DISPLAY_NAME}.zip"
echo "  2. xattr -cr ${DISPLAY_NAME}.app"
echo "  3. Drag to /Applications"
