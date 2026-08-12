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

# Issue #31: Use the exact binary path to avoid killing unrelated processes
APP_PATH="/Users/nageshbhosle/Documents/Nagesh/projects/ds-algo/systemDesign/voice-dictation/build/VoiceDictation.app"

if [ "$1" = "status" ]; then
    # Match by bundle identifier for more precision
    if pgrep -f "VoiceDictation.app/Contents/MacOS/VoiceDictation" > /dev/null 2>&1; then
        PID=$(pgrep -f "VoiceDictation.app/Contents/MacOS/VoiceDictation")
        echo -e "${GREEN}✅ VoiceDictation is running (PID: $PID)${NC}"
    else
        echo -e "${YELLOW}⚪ VoiceDictation is not running${NC}"
    fi
    exit 0
fi

echo -e "${YELLOW}🛑 Stopping VoiceDictation...${NC}"

# Use the specific binary path to avoid false matches
PATTERN="VoiceDictation.app/Contents/MacOS/VoiceDictation"

if pkill -f "$PATTERN" 2>/dev/null; then
    echo -e "${GREEN}✅ VoiceDictation stopped (graceful)${NC}"
else
    if pgrep -f "$PATTERN" > /dev/null 2>&1; then
        echo -e "${YELLOW}Force killing...${NC}"
        pkill -9 -f "$PATTERN" 2>/dev/null
        echo -e "${GREEN}✅ VoiceDictation killed (force)${NC}"
    else
        echo -e "${YELLOW}⚪ VoiceDictation was not running${NC}"
    fi
fi