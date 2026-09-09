#!/bin/bash
# Distributed scheduling lab — Postgres + Redis + RabbitMQ, then Spring Boot on :8080.

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
echo "Starting distributed scheduling lab..."
echo ""

echo "Step 1: Starting Docker containers (PostgreSQL + Redis + RabbitMQ)..."
if docker compose up -d 2>/dev/null || docker-compose up -d; then
    echo "  Containers started"
else
    echo "  Failed to start Docker containers. Is Docker running?"
    exit 1
fi

echo ""
echo "Step 2: Waiting for services to become healthy..."
for i in $(seq 1 30); do
    unhealthy=$(docker compose ps --format '{{.Health}}' 2>/dev/null | grep -cv "healthy" || true)
    if [ "$unhealthy" = "0" ]; then
        echo "  All services healthy"
        break
    fi
    if [ "$i" = "30" ]; then
        echo "  WARNING: some services still unhealthy after 30 checks — continuing anyway"
    fi
    sleep 2
done

PORT_EFF="${SERVER_PORT:-8084}"
echo ""
echo "Step 3: Starting Spring Boot app on :$PORT_EFF ..."
echo "  Dashboard: http://localhost:$PORT_EFF"
echo "  RabbitMQ management: http://localhost:15672 (lab/lab)"
echo ""
./mvnw spring-boot:run
