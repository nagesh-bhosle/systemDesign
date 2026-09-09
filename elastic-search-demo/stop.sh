#!/bin/bash
cd "$(dirname "$0")"

if ! command -v docker >/dev/null 2>&1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then export PATH="$d:$PATH"; break; fi
    done
fi

echo ""
echo "============================================"
echo "  🛑 Stopping Elastic Search Lab..."
echo "============================================"
echo ""

PORT="${SERVER_PORT:-8086}"
CFG="/Users/nageshbhosle/Documents/Nagesh/projects/ds-algo/systemDesign/launcher/config.json"
if [ -z "${SERVER_PORT:-}" ] && [ -f "$CFG" ]; then
  SP=$(python3 -c "import json,pathlib; p=pathlib.Path('$CFG'); d=json.loads(p.read_text()); print(d.get('ports',{}).get('elastic-search-demo',''))" 2>/dev/null || true)
  [ -n "$SP" ] && PORT="$SP"
fi
echo "Stopping Spring Boot application (port $PORT)..."
PID=$(lsof -ti:"$PORT" 2>/dev/null || true)
if [ -n "$PID" ]; then kill $PID 2>/dev/null || true; echo "  ✅ Stopped app (PID: $PID)"; else echo "  ℹ️  App was not running"; fi

echo ""
echo "Stopping Docker containers..."
if docker compose down 2>/dev/null || docker-compose down 2>/dev/null; then echo "  ✅ Containers stopped"; else echo "  ℹ️  No Docker containers to stop"; fi

echo ""
echo "============================================"
echo "  ✅ Elastic Search Lab stopped."
echo "============================================"
