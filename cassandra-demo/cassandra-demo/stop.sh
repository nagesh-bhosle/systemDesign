#!/bin/bash
# ============================================================
# Cassandra Demo — Stop script
# ============================================================
# Stops the Spring Boot app and the Cassandra Docker container.
# ============================================================

cd "$(dirname "$0")"

if ! command -v docker >/dev/null 2>&1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then export PATH="$d:$PATH"; break; fi
    done
fi

echo "Stopping Cassandra Demo..."

PORT="${SERVER_PORT:-8080}"
PID=$(lsof -ti:"$PORT" 2>/dev/null || true)
if [ -n "$PID" ]; then
    kill $PID 2>/dev/null || true
    echo "  Stopped app (PID: $PID)"
else
    echo "  App was not running"
fi

echo "Stopping Cassandra container..."
# Remove any stale container using the reserved name (even if created outside
# this compose project, e.g. via `docker run`), then compose down.
docker rm -f cassandra-node1 2>/dev/null || true
docker compose -f docker/docker-compose.yml down 2>/dev/null || docker compose down 2>/dev/null || true

echo "Done."
