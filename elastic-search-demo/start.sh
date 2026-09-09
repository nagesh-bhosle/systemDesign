#!/bin/bash
# ============================================================
# Elastic Search Lab — One-command startup script
# ============================================================
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
        if [ -x "$d/docker" ]; then export PATH="$d:$PATH"; break; fi
    done
fi

echo "Using JAVA_HOME: $JAVA_HOME"
echo "Docker path: $(which docker 2>/dev/null || echo 'not found')"

echo ""
echo "============================================"
echo "  🔍 Elastic Search Lab — Starting up..."
echo "============================================"
echo ""

echo "📦 Step 1: Starting Docker containers (PostgreSQL + Elasticsearch)..."
if docker compose up -d 2>/dev/null || docker-compose up -d; then
    echo "  ✅ Containers started"
else
    echo "  ❌ Failed to start Docker containers. Is Docker running?"
    exit 1
fi

echo ""
echo "⏳ Step 2: Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
    if docker exec es-demo-postgres pg_isready -U esdemo -d esdemo > /dev/null 2>&1; then
        echo "  ✅ PostgreSQL is ready"
        break
    fi
    if [ $i -eq 30 ]; then echo "  ❌ PostgreSQL did not become ready in 30 seconds"; exit 1; fi
    echo "  ...waiting ($i/30)"
    sleep 1
done

echo ""
echo "⏳ Step 2b: Waiting for Elasticsearch to be ready..."
for i in $(seq 1 60); do
    if curl -s http://localhost:9201/_cluster/health | grep -q '"status":"green"\|"status":"yellow"' 2>/dev/null; then
        echo "  ✅ Elasticsearch is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "  ⚠️  Elasticsearch did not become ready in 60 seconds — continuing anyway"
    fi
    echo "  ...waiting ($i/60)"
    sleep 1
done

echo ""
echo "🔨 Step 3: Building Spring Boot application..."
if ./mvnw clean compile -q 2>&1; then
    echo "  ✅ Build successful"
else
    echo "  ❌ Build failed. Check errors above."
    exit 1
fi

echo ""
echo "🚀 Step 4: Starting Spring Boot application..."
echo ""
echo "============================================"
PORT_EFF="${SERVER_PORT:-8086}"
echo "  🎉 Elastic Search Lab is running!"
echo "  📌 Open: http://localhost:$PORT_EFF"
echo "  🗄️  PostgreSQL: localhost:5434/esdemo"
echo "  🔍 Elasticsearch: localhost:9201"
echo "  🛑 To stop: ./stop.sh"
echo "============================================"
echo ""

./mvnw spring-boot:run
