#!/bin/bash
# Stop the distributed scheduling lab: app containers down (app runs in foreground).

set -e

cd "$(dirname "$0")"

if ! command -v docker >/dev/null 2>&1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then
            export PATH="$d:$PATH"
            break
        fi
    done
fi

PORT="${SERVER_PORT:-8084}"
CFG="/Users/nageshbhosle/Documents/Nagesh/projects/ds-algo/systemDesign/launcher/config.json"
if [ -z "${SERVER_PORT:-}" ] && [ -f "$CFG" ]; then
  SP=$(python3 -c "import json,pathlib; p=pathlib.Path('$CFG'); d=json.loads(p.read_text()); print(d.get('ports',{}).get('distributed-scheduling-lab',''))" 2>/dev/null || true)
  [ -n "$SP" ] && PORT="$SP"
fi
if lsof -ti:"$PORT" >/dev/null 2>&1; then
  lsof -ti:"$PORT" | xargs kill -9 2>/dev/null || true
  echo "  Killed app on port $PORT"
fi

echo "Stopping Docker containers (PostgreSQL + Redis + RabbitMQ)..."
docker compose down 2>/dev/null || docker-compose down || true

# Kill any spring-boot:run for this project still in the background
pkill -f "distributed-scheduling-lab.*spring-boot:run" 2>/dev/null || true

echo "Done."
