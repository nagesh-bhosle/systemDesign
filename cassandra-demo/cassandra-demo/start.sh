#!/bin/bash
# ============================================================
# Cassandra Demo — One-command startup script
# ============================================================
# Starts a single-node Cassandra 4.1 via Docker (with schema + seed),
# then builds and runs the Spring Boot application.
#
# Usage:  ./start.sh
# Stop:   ./stop.sh
# ============================================================

set -e

cd "$(dirname "$0")"

# --- JAVA_HOME ---
if [ -z "$JAVA_HOME" ]; then
    if [ -x "/opt/homebrew/opt/openjdk@17/bin/java" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
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
echo "Step 1: Starting Cassandra (Docker)..."
# Remove a stale container with the reserved name if present (prevents a name
# conflict when a previous run was stopped outside compose).
docker rm -f cassandra-node1 2>/dev/null || true
docker compose -f docker/docker-compose.yml up -d --force-recreate cassandra

echo ""
echo "Step 2: Waiting for Cassandra to be healthy..."
for i in $(seq 1 60); do
    if docker exec cassandra-node1 cqlsh -e "SELECT release_version FROM system.local" >/dev/null 2>&1; then
        echo "  Cassandra ready."
        break
    fi
    sleep 2
done

echo ""
echo "Step 2b: Applying schema + seed (idempotent)..."
docker exec -i cassandra-node1 cqlsh < src/main/resources/cql/schema.cql || true
docker exec -i cassandra-node1 cqlsh < src/main/resources/cql/seed-data.cql || true

PORT="${SERVER_PORT:-8080}"
echo ""
echo "Step 3: Building + starting Spring Boot app on :$PORT ..."
echo "  Open:      http://localhost:$PORT"
echo "  Cassandra: localhost:9042"
echo "  Stop:      ./stop.sh"
echo ""

mvn -q -DskipTests package
SERVER_PORT="$PORT" CASSANDRA_CONTACT_POINTS="${CASSANDRA_CONTACT_POINTS:-localhost}" \
    mvn spring-boot:run
