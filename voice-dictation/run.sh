#!/bin/bash
#
# run.sh — One-click build & launch VoiceDictation
#
# Usage:
#   ./run.sh          # Build and launch the app
#   ./run.sh build    # Build only (don't launch)
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

# ── Colours ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🎙️  Voice Dictation — Build & Run${NC}"
echo ""

# ── Clean previous build ─────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# ── Build ─────────────────────────────────────────────────
echo -e "${YELLOW}🔨 Building...${NC}"

# Direct swiftc compilation (SPM is broken with Command Line Tools only)
if swiftc -O \
    -parse-as-library \
    -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework Carbon \
    -framework ApplicationServices \
    -framework Security \
    -framework UserNotifications \
    -framework Speech \
    VoiceDictation/*.swift \
    -o "$BINARY" 2>&1; then
    echo -e "${GREEN}✅ Built with swiftc${NC}"
else
    echo -e "${RED}❌ Build failed.${NC}"
    exit 1
fi

# ── Assemble .app bundle ──────────────────────────────────
cp VoiceDictation/Info.plist "$CONTENTS_DIR/Info.plist"
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo -e "${GREEN}📦 App bundle: $APP_DIR${NC}"

# ── Launch (unless --build-only) ──────────────────────────
if [ "$1" != "build" ]; then
    echo -e "${GREEN}🚀 Launching...${NC}"
    echo ""
    echo "  📋 First time? Click the 🎤 icon in the menu bar → Settings → paste your OpenAI API key"
    echo "  ⌨️  Press ⌥⇧Space anywhere to start/stop recording"
    echo ""
    open "$APP_DIR"
fi