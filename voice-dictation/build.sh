#!/bin/bash
#
# build.sh — Build VoiceDictation macOS app
#
# Usage:
#   ./build.sh          # Build to build/VoiceDictation.app
#   ./build.sh run      # Build and launch
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/VoiceDictation.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building VoiceDictation..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Build the executable
swift build -c release 2>&1 || {
    echo "⚠️  Swift Package Manager build failed (known CLT module issue)."
    echo "   Trying direct swiftc compilation..."
    
    # Fallback: direct swiftc compilation
    swiftc -O \
        -parse-as-library \
        -target arm64-apple-macosx14.0 \
        -sdk "$(xcrun --show-sdk-path)" \
        -framework Cocoa \
        -framework SwiftUI \
        -framework AVFoundation \
        -framework Carbon \
        -framework ApplicationServices \
        -framework Security \
        VoiceDictation/*.swift \
        -o "$MACOS_DIR/VoiceDictation" 2>&1
}

# If SPM build succeeded, copy the binary
if [ -f ".build/release/VoiceDictation" ]; then
    cp ".build/release/VoiceDictation" "$MACOS_DIR/VoiceDictation"
fi

# Copy Info.plist
cp VoiceDictation/Info.plist "$CONTENTS_DIR/Info.plist"

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "✅ Build complete: $APP_DIR"

# Optionally run
if [ "$1" = "run" ]; then
    echo "🚀 Launching VoiceDictation..."
    open "$APP_DIR"
fi