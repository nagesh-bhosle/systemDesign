#!/bin/bash
#
# stop.sh — Kill any running instance of VoiceDictation
#
# Usage:
#   ./stop.sh          # Stop the app
#   ./stop.sh status   # Check if it's running
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/build/VoiceDictation.app"
BINARY_PATTERN="VoiceDictation.app/Contents/MacOS/VoiceDictation"

if [ "$1" = "status" ]; then
    if pgrep -f "$BINARY_PATTERN" > /dev/null 2>&1; then
        PID=$(pgrep -f "$BINARY_PATTERN")
        echo -e "${GREEN}VoiceDictation is running (PID: $PID)${NC}"
        echo "  App: $APP_PATH"
    else
        echo -e "${YELLOW}VoiceDictation is not running${NC}"
    fi
    exit 0
fi

echo -e "${YELLOW}Stopping VoiceDictation...${NC}"

if pkill -f "$BINARY_PATTERN" 2>/dev/null; then
    echo -e "${GREEN}VoiceDictation stopped (graceful)${NC}"
else
    if pgrep -f "$BINARY_PATTERN" > /dev/null 2>&1; then
        echo -e "${YELLOW}Force killing...${NC}"
        pkill -9 -f "$BINARY_PATTERN" 2>/dev/null
        echo -e "${GREEN}VoiceDictation killed (force)${NC}"
    else
        echo -e "${YELLOW}VoiceDictation was not running${NC}"
    fi
fi
