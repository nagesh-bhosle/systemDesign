#!/bin/bash
# ============================================================
# Dropbox Demo — One-command startup script
# ============================================================
# Starts Azurite (Azure Blob emulator) via Docker, then builds
# and runs the Spring Boot application (H2 in-memory).
#
# Usage:  ./start.sh
# Stop:   ./stop.sh
# ============================================================

set -e

cd "$(dirname "$0")"

# --- JAVA_HOME ---
if [ -z "$JAVA_HOME" ]; then
    if [ -x "/opt/homebrew/opt/openjdk@21/bin/java" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
    elif [ -x "/opt/homebrew/opt/openjdk/bin/java" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk"
    fi
fi

# --- Docker on PATH ---
if ! command -v docker >/dev/null 2>&1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then export PATH="$d:$PATH"; break; fi
    done
fi

echo "Using JAVA_HOME: ${JAVA_HOME:-unset}"
echo "Docker path: $(which docker 2>/dev/null || echo 'not found')"

echo ""
echo "Step 1: Starting Azurite (Azure Blob emulator) via Docker..."
docker compose up -d
# wait for azurite to listen on 10000
for i in $(seq 1 30); do
    if lsof -ti :10000 >/dev/null 2>&1; then echo "  Azurite ready."; break; fi
    sleep 1
done

echo ""
echo "Step 2: Building the Spring Boot app..."
if [ -x ./mvnw ]; then
    ./mvnw -q -DskipTests package
else
    mvn -q -DskipTests package
fi

PORT="${SERVER_PORT:-8080}"
echo ""
echo "Step 3: Starting Dropbox Demo on :$PORT ..."
echo "  Open:      http://localhost:$PORT"
echo "  H2 console: http://localhost:$PORT/h2-console (jdbc:h2:mem:dropbox, sa, no password)"
echo "  Stop:      ./stop.sh"
echo ""

if [ -x ./mvnw ]; then
    SERVER_PORT="$PORT" ./mvnw spring-boot:run
else
    SERVER_PORT="$PORT" mvn spring-boot:run
fi
