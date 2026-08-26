#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-5173}"
cd "$SCRIPT_DIR/app"

if lsof -i :"$PORT" >/dev/null 2>&1; then
  echo "Port $PORT already in use. Run ./stop.sh or set PORT=5174 ./start.sh"
  exit 1
fi

echo "Starting Interview Face Coach on http://localhost:$PORT"
echo "Press Ctrl+C to stop — or run ./stop.sh in another shell"
# serve static app; no deps
if command -v python3 >/dev/null 2>&1; then
  python3 -m http.server "$PORT" &
  PID=$!
  echo "$PID" > /tmp/ifc-server.pid
  echo "PID $PID — open http://localhost:$PORT in your browser"
  echo "Tip: if camera is blocked, use http://localhost:$PORT (not file://)"
  wait $PID
elif command -v docker >/dev/null 2>&1; then
  cd "$SCRIPT_DIR"
  docker compose up --build
else
  echo "Need python3 or docker installed."
  exit 1
fi
