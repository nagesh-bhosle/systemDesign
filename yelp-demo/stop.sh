#!/bin/bash
# ============================================================
# Yelp Demo — Stop script
# ============================================================
# Stops the Spring Boot app and the Docker database container.
# ============================================================

cd "$(dirname "$0")"

# Add Docker to PATH if not found (Rancher Desktop, Docker Desktop, Colima)
if ! command -v docker >/dev/null 2>&1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then
            export PATH="$d:$PATH"
            break
        fi
    done
fi

echo ""
echo "============================================"
echo "  🛑 Stopping Yelp Demo..."
echo "============================================"
echo ""

# --- 1. Stop Spring Boot (kill any process on current launcher port, fallback 8081) ---
PORT="${SERVER_PORT:-8081}"
# Prefer launcher's stored port if set
CFG="/Users/nageshbhosle/Documents/Nagesh/projects/ds-algo/systemDesign/launcher/config.json"
if [ -z "${SERVER_PORT:-}" ] && [ -f "$CFG" ]; then
  SP=$(python3 -c "import json,pathlib; p=pathlib.Path('$CFG'); d=json.loads(p.read_text()); print(d.get('ports',{}).get('yelp-demo',''))" 2>/dev/null || true)
  [ -n "$SP" ] && PORT="$SP"
fi
echo "Stopping Spring Boot application (port $PORT)..."
PID=$(lsof -ti:"$PORT" 2>/dev/null || true)
if [ -n "$PID" ]; then
    kill $PID 2>/dev/null || true
    echo "  ✅ Stopped app (PID: $PID)"
else
    echo "  ℹ️  App was not running"
fi

# --- 2. Stop Docker container ---
echo ""
echo "Stopping PostgreSQL container..."
if docker compose down 2>/dev/null || docker-compose down 2>/dev/null; then
    echo "  ✅ Database container stopped"
else
    echo "  ℹ️  No Docker container to stop"
fi

echo ""
echo "============================================"
echo "  ✅ Yelp Demo stopped."
echo "============================================"