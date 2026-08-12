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

if [ "$1" = "status" ]; then
    if pgrep -x "VoiceDictation" > /dev/null 2>&1; then
        PID=$(pgrep -x "VoiceDictation")
        echo -e "${GREEN}✅ VoiceDictation is running (PID: $PID)${NC}"
    else
        echo -e "${YELLOW}⚪ VoiceDictation is not running${NC}"
    fi
    exit 0
fi

echo -e "${YELLOW}🛑 Stopping VoiceDictation...${NC}"

# Try graceful termination first
if pkill -x "VoiceDictation" 2>/dev/null; then
    echo -e "${GREEN}✅ VoiceDictation stopped (graceful)${NC}"
else
    # Check if it was even running
    if pgrep -x "VoiceDictation" > /dev/null 2>&1; then
        echo -e "${YELLOW}Force killing...${NC}"
        pkill -9 -x "VoiceDictation" 2>/dev/null
        echo -e "${GREEN}✅ VoiceDictation killed (force)${NC}"
    else
        echo -e "${YELLOW}⚪ VoiceDictation was not running${NC}"
    fi
fi