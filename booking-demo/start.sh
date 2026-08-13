#!/bin/bash
# Booking concepts demo — Postgres + Redis, then Spring Boot on :8083.

set -e

cd "$(dirname "$0")"

if [ -z "$JAVA_HOME" ]; then
    if [ -x "/opt/homebrew/opt/openjdk@21/bin/java" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
    elif [ -x "/opt/homebrew/opt/openjdk/bin/java" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk"
    fi
fi

if ! command -v docker >/dev/null 2>&1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then
            export PATH="$d:$PATH"
            break
        fi
    done
fi

echo "Using JAVA_HOME: ${JAVA_HOME:-unset}"
echo "Docker path: $(which docker 2>/dev/null || echo 'not found')"
echo ""
echo "Starting booking concepts demo..."
echo ""

echo "Step 1: Starting Docker containers (PostgreSQL + Redis)..."
if docker compose up -d 2>/dev/null || docker-compose up -d; then
    echo "  Containers started"
else
    echo "  Failed to start Docker containers. Is Docker running?"
    exit 1
fi

echo ""
echo "Step 2: Waiting for PostgreSQL..."
for i in $(seq 1 30); do
    if docker exec booking-postgres pg_isready -U booking -d booking > /dev/null 2>&1; then
        echo "  PostgreSQL is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  PostgreSQL did not become ready in 30 seconds"
        exit 1
    fi
    echo "  ...waiting ($i/30)"
    sleep 1
done

echo ""
echo "Step 2b: Waiting for Redis..."
for i in $(seq 1 20); do
    if docker exec booking-redis redis-cli ping 2>/dev/null | grep -q PONG; then
        echo "  Redis is ready"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "  Redis did not become ready in 20 seconds"
        exit 1
    fi
    echo "  ...waiting ($i/20)"
    sleep 1
done

echo ""
echo "Step 3: Building Spring Boot application..."
if ./mvnw clean compile -q; then
    echo "  Build successful"
else
    echo "  Build failed."
    exit 1
fi

echo ""
echo "Booking demo is running"
echo "  Open:       http://localhost:8083"
echo "  Catalog:    GET http://localhost:8083/api/concepts"
echo "  PostgreSQL: localhost:5435/booking"
echo "  Redis:      localhost:6381"
echo "  Stop:       ./stop.sh"
echo ""

./mvnw spring-boot:run
