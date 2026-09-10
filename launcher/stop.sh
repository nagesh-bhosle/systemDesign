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

# fallback: kill anything on the port (lsof preferred, else ss/fuser, else tcp probe skip)
if command -v lsof >/dev/null 2>&1; then
  PIDS=$(lsof -ti :"$PORT" 2>/dev/null || true)
  if [ -n "$PIDS" ]; then kill $PIDS 2>/dev/null && echo "Killed port $PORT ($PIDS)"; fi
elif command -v ss >/dev/null 2>&1; then
  PIDS=$(ss -lptn "sport = :$PORT" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | tr '\n' ' ')
  if [ -n "$PIDS" ]; then kill $PIDS 2>/dev/null && echo "Killed port $PORT ($PIDS)"; fi
elif command -v fuser >/dev/null 2>&1; then
  PIDS=$(fuser "$PORT/tcp" 2>/dev/null | tr -d ' ' )
  # fuser prints "1234 5678" space-separated on some distros
  for p in $PIDS; do kill "$p" 2>/dev/null && echo "Killed port $PORT ($p)"; done
fi

echo "Done."
