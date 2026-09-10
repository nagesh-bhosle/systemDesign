#!/usr/bin/env bash
PORT="${PORT:-5173}"
if [ -n "${SERVER_PORT:-}" ]; then PORT="$SERVER_PORT"; fi
if [ -f /tmp/ifc-server.pid ]; then
  PID=$(cat /tmp/ifc-server.pid)
  kill "$PID" 2>/dev/null && echo "Stopped $PID" || echo "No server at $PID"
  rm -f /tmp/ifc-server.pid
fi
# fallback: kill anything on PORT
if command -v lsof >/dev/null 2>&1; then
  PIDS=$(lsof -ti :"$PORT" 2>/dev/null || true)
  if [ -n "$PIDS" ]; then kill $PIDS 2>/dev/null && echo "Killed port $PORT ($PIDS)"; fi
fi
# docker fallback
if command -v docker >/dev/null 2>&1; then
  docker compose -f "$(dirname "$0")/docker-compose.yml" down 2>/dev/null || true
fi
echo "Done."
