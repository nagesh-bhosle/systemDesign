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

# Issue #32: Use pkill -f to match the full path, not just the exact
# process name. This handles cases where the binary is renamed or run
# from a different path.
if [ "$1" = "status" ]; then
    if pgrep -f "VoiceDictation.app" > /dev/null 2>&1; then
        PID=$(pgrep -f "VoiceDictation.app")
        echo -e "${GREEN}✅ VoiceDictation is running (PID: $PID)${NC}"
    else
        echo -e "${YELLOW}⚪ VoiceDictation is not running${NC}"
    fi
    exit 0
fi

echo -e "${YELLOW}🛑 Stopping VoiceDictation...${NC}"

# Try graceful termination first (issue #32: use -f for path matching)
if pkill -f "VoiceDictation.app" 2>/dev/null; then
    echo -e "${GREEN}✅ VoiceDictation stopped (graceful)${NC}"
else
    # Check if it was even running
    if pgrep -f "VoiceDictation.app" > /dev/null 2>&1; then
        echo -e "${YELLOW}Force killing...${NC}"
        pkill -9 -f "VoiceDictation.app" 2>/dev/null
        echo -e "${GREEN}✅ VoiceDictation killed (force)${NC}"
    else
        echo -e "${YELLOW}⚪ VoiceDictation was not running${NC}"
    fi
fi