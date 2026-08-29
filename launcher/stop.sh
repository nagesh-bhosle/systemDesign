#!/usr/bin/env bash
# stop.sh — stop the systemDesign launcher server
set -euo pipefail
cd "$(dirname "$0")"

PORT="${LAUNCHER_PORT:-8790}"

if [ -f .launcher.pid ]; then
  PID=$(cat .launcher.pid)
  kill "$PID" 2>/dev/null && echo "Stopped launcher (PID $PID)" || echo "No launcher at $PID"
  rm -f .launcher.pid
fi

# fallback: kill anything on the port
PIDS=$(lsof -ti :"$PORT" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
  kill $PIDS 2>/dev/null && echo "Killed port $PORT"
fi

echo "Done."
