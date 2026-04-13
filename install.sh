#!/bin/bash
# DeckManager Installer
# Usage: curl the install script or run after unzipping

set -e

APP_NAME="DeckManager"
DOWNLOAD_DIR="$HOME/Downloads"
INSTALL_DIR="/Applications"

echo ""
echo "=== DeckManager Installer ==="
echo ""

# Find the app — check common locations
APP_PATH=""
for dir in "$DOWNLOAD_DIR" "$DOWNLOAD_DIR/${APP_NAME}" "." "./${APP_NAME}"; do
    if [ -d "${dir}/${APP_NAME}.app" ]; then
        APP_PATH="${dir}/${APP_NAME}.app"
        break
    fi
done

if [ -z "$APP_PATH" ]; then
    # Try unzipping if zip exists
    for dir in "$DOWNLOAD_DIR" "."; do
        if [ -f "${dir}/${APP_NAME}.zip" ]; then
            echo "Found ${APP_NAME}.zip — unzipping..."
            ditto -x -k "${dir}/${APP_NAME}.zip" "${dir}"
            APP_PATH="${dir}/${APP_NAME}.app"
            break
        fi
    done
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: Could not find ${APP_NAME}.app or ${APP_NAME}.zip"
    echo "Make sure the file is in ~/Downloads or the current directory."
    exit 1
fi

echo "Found: ${APP_PATH}"

# Remove quarantine flag (macOS blocks unsigned downloaded apps)
echo "Removing quarantine flag..."
xattr -cr "$APP_PATH"

# Copy to Applications
echo "Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "$APP_PATH" "${INSTALL_DIR}/${APP_NAME}.app"

echo ""
echo "=== Installed! ==="
echo ""
echo "Launch from Applications or run:"
echo "  open /Applications/${APP_NAME}.app"
echo ""

# Offer to launch
read -p "Launch now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "${INSTALL_DIR}/${APP_NAME}.app"
fi
