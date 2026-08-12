#!/bin/bash
#
# run.sh — One-click build & launch VoiceDictation
#
# Usage:
#   ./run.sh          # Build and launch the app
#   ./run.sh build    # Build only (don't launch)
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
    VoiceDictation/*.swift \
    -o "$BINARY" 2>&1; then
    echo -e "${GREEN}Built with swiftc${NC}"
else
    echo -e "${RED}Build failed.${NC}"
    exit 1
fi

cp VoiceDictation/Info.plist "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo -e "${GREEN}App bundle: $APP_DIR${NC}"

if [ -n "$CODESIGN_IDENTITY" ]; then
    echo -e "${YELLOW}Codesigning with identity: $CODESIGN_IDENTITY${NC}"
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp=none "$APP_DIR" || {
        echo -e "${YELLOW}Codesign failed (non-fatal)${NC}"
    }
fi

if [ "$1" != "build" ]; then
    echo -e "${GREEN}Launching...${NC}"
    echo ""
    echo "  Optional: Click the mic icon in the menu bar → Settings → paste your Abacus AI API key"
    echo "  Press Option+Shift+Space anywhere to start/stop recording"
    echo ""
    open "$APP_DIR"
fi
