#!/bin/bash
cd "$(dirname "$0")"

if ! command -v docker >/dev/null 2>&1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then
            export PATH="$d:$PATH"
            break
        fi
    done
fi

echo "Stopping booking demo..."

PID=$(lsof -ti:8083 2>/dev/null || true)
if [ -n "$PID" ]; then
    kill $PID 2>/dev/null || true
    echo "  Stopped app (PID: $PID)"
else
    echo "  App was not running"
fi

echo "Stopping Docker containers..."
if docker compose down 2>/dev/null || docker-compose down 2>/dev/null; then
    echo "  Containers stopped"
else
    echo "  No Docker containers to stop"
fi

echo "Booking demo stopped."
