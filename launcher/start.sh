#!/usr/bin/env bash
# start.sh — start the systemDesign launcher (serves the dashboard + API)
set -euo pipefail
cd "$(dirname "$0")"

PORT="${LAUNCHER_PORT:-8790}"

if lsof -ti :"$PORT" >/dev/null 2>&1; then
  echo "Launcher already running on :$PORT — open http://localhost:$PORT"
  exit 0
fi

echo "Starting systemDesign launcher on http://localhost:$PORT ..."
nohup python3 server.py --port "$PORT" --no-browser > logs/launcher.log 2>&1 &
echo $! > .launcher.pid

# wait for it to come up
for i in $(seq 1 20); do
  if curl -s -o /dev/null "http://localhost:$PORT/api/projects"; then
    echo "✅ Launcher ready:  http://localhost:$PORT"
    # open the dashboard
    (command -v open >/dev/null && open "http://localhost:$PORT") || true
    exit 0
  fi
  sleep 0.5
done
echo "⚠️  Launcher did not become ready in time — check logs/launcher.log"
exit 1
