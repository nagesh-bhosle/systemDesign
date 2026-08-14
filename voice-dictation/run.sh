#!/bin/bash
#
# run.sh — One-click build & launch VoiceDictation
#
# Usage:
#   ./run.sh          # Build and launch the app
#   ./run.sh build    # Build only (don't launch)
#   ./run.sh install  # Build and copy to ~/Applications/VoiceDictation.app
#   ./run.sh clean    # Full clean build, then launch
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/VoiceDictation.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY="$MACOS_DIR/VoiceDictation"
APP_VERSION="0.5.3"
ZIP_PATH="$BUILD_DIR/VoiceDictation-${APP_VERSION}.zip"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Voice Dictation — Build & Run${NC}"
echo ""

if ! xcrun --show-sdk-path > /dev/null 2>&1; then
    echo -e "${RED}Xcode Command Line Tools not found.${NC}"
    echo -e "${YELLOW}   Run: xcode-select --install${NC}"
    exit 1
fi

if [ "$1" = "clean" ]; then
    echo -e "${YELLOW}Full clean build...${NC}"
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo -e "${YELLOW}Building...${NC}"

ARCH=$(uname -m)

if swiftc -O \
    -parse-as-library \
    -target "${ARCH}-apple-macosx14.0" \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework Carbon \
    -framework ApplicationServices \
    -framework Security \
    -framework UserNotifications \
    -framework Speech \
    -framework ServiceManagement \
    -framework CryptoKit \
    -framework CoreAudio \
    -import-objc-header VoiceDictation/ExceptionCatcher.h \
    VoiceDictation/*.swift \
    VoiceDictation/ExceptionCatcher.m \
    -o "$BINARY" 2>&1; then
    echo -e "${GREEN}Built with swiftc${NC}"
else
    echo -e "${RED}Build failed.${NC}"
    exit 1
fi

cp VoiceDictation/Info.plist "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# Copy privacy policy into bundle
if [ -f "$SCRIPT_DIR/PRIVACY.md" ]; then
    cp "$SCRIPT_DIR/PRIVACY.md" "$RESOURCES_DIR/PRIVACY.md"
fi

# App icon: generate .icns from PNG if needed, copy into bundle
ICON_PNG="$SCRIPT_DIR/VoiceDictation/Resources/AppIcon.png"
ICON_ICNS="$SCRIPT_DIR/VoiceDictation/Resources/AppIcon.icns"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

if [ -f "$ICON_PNG" ]; then
    if [ ! -f "$ICON_ICNS" ]; then
        echo -e "${YELLOW}Generating AppIcon.icns from PNG...${NC}"
        rm -rf "$ICONSET_DIR"
        mkdir -p "$ICONSET_DIR"
        for size in 16 32 128 256 512; do
            sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null
            double=$((size * 2))
            sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" > /dev/null
        done
        iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS" || {
            echo -e "${YELLOW}iconutil failed (non-fatal) — continuing without .icns${NC}"
        }
    fi
    if [ -f "$ICON_ICNS" ]; then
        cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist"
    fi
else
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
fi

echo -e "${GREEN}App bundle: $APP_DIR${NC}"

# Sign with a stable identity so Accessibility survives rebuilds.
if [ -z "$CODESIGN_IDENTITY" ]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E 'Apple Development|Developer ID Application|Mac Developer' \
        | head -1 \
        | sed -E 's/.*"([^"]+)".*/\1/')
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
    echo -e "${YELLOW}Codesigning with: $CODESIGN_IDENTITY${NC}"
    codesign --force --sign "$CODESIGN_IDENTITY" --identifier com.nagesh.voicedictation --timestamp=none "$APP_DIR" || {
        echo -e "${YELLOW}Codesign failed (non-fatal)${NC}"
    }
else
    echo -e "${YELLOW}No Apple codesign identity found. Accessibility may reset after each rebuild.${NC}"
    echo -e "${YELLOW}If auto-paste fails: System Settings → Accessibility → uncheck Voice Dictation, then check it again.${NC}"
fi

# Distribution zip
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
echo -e "${GREEN}Distribution zip: $ZIP_PATH${NC}"

if [ "$1" = "install" ]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    INSTALL_APP="$INSTALL_DIR/VoiceDictation.app"
    echo -e "${YELLOW}Installing to $INSTALL_APP${NC}"
    rm -rf "$INSTALL_APP"
    ditto "$APP_DIR" "$INSTALL_APP"
    echo -e "${GREEN}Installed. Open from Launchpad or:${NC} open \"$INSTALL_APP\""
    echo "This is the stable app identity (com.nagesh.voicedictation). See PRODUCT_ROADMAP.md."
    exit 0
fi

if [ "$1" != "build" ]; then
    echo -e "${GREEN}Launching...${NC}"
    echo ""
    echo "  Optional: Click the menu bar icon → Settings → paste your Abacus AI API key"
    echo "  Press Option+Shift+Space anywhere to start/stop recording"
    echo ""
    open "$APP_DIR"
fi
