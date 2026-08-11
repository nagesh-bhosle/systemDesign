#!/bin/bash
# ============================================================
# Yelp Demo — One-command startup script
# ============================================================
# Starts PostgreSQL+PostGIS via Docker, then builds and runs
# the Spring Boot application with preloaded data.
#
# Usage:  ./start.sh
# Stop:   ./stop.sh
# ============================================================

set -e

cd "$(dirname "$0")"

# --- 0. Set JAVA_HOME and PATH if not already set ---
if [ -z "$JAVA_HOME" ]; then
    if [ -x "/opt/homebrew/opt/openjdk@21/bin/java" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
    elif [ -x "/opt/homebrew/opt/openjdk/bin/java" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk"
    fi
fi

# Add Docker to PATH if not found (Rancher Desktop, Docker Desktop, Colima)
if ! command -v docker &gt;/dev/null 2&gt;&amp;1; then
    for d in "$HOME/.rd/bin" "/usr/local/bin" "/Applications/Docker.app/Contents/Resources/bin" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin"; do
        if [ -x "$d/docker" ]; then
            export PATH="$d:$PATH"
            break
        fi
    done
fi

echo "Using JAVA_HOME: $JAVA_HOME"
echo "Docker path: $(which docker 2>/dev/null || echo 'not found')"

echo ""
echo "============================================"
echo "  🍴 Yelp Demo — Starting up..."
echo "============================================"
echo ""

# --- 1. Start PostgreSQL + PostGIS via Docker ---
echo "📦 Step 1: Starting PostgreSQL + PostGIS container..."
if docker compose up -d 2>/dev/null || docker-compose up -d; then
    echo "  ✅ Database container started"
else
    echo "  ❌ Failed to start Docker container. Is Docker running?"
    exit 1
fi

# --- 2. Wait for database to be ready ---
echo ""
echo "⏳ Step 2: Waiting for database to be ready..."
for i in $(seq 1 30); do
    if docker exec yelp-postgres pg_isready -U yelp -d yelp > /dev/null 2>&1; then
        echo "  ✅ Database is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "  ❌ Database did not become ready in 30 seconds"
        exit 1
    fi
    echo "  ...waiting ($i/30)"
    sleep 1
done

# --- 3. Build the Spring Boot application ---
echo ""
echo "🔨 Step 3: Building Spring Boot application..."
if ./mvnw clean compile -q 2>&1; then
    echo "  ✅ Build successful"
else
    echo "  ❌ Build failed. Check errors above."
    exit 1
fi

# --- 4. Start the Spring Boot application ---
echo ""
echo "🚀 Step 4: Starting Spring Boot application..."
echo ""
echo "============================================"
echo "  🎉 Yelp Demo is running!"
echo "  📌 Open: http://localhost:8081"
echo "  📊 H2 Console: N/A (using PostgreSQL)"
echo "  🗄️  Database: localhost:5433/yelp"
echo "  🛑 To stop: ./stop.sh"
echo "============================================"
echo ""

./mvnw spring-boot:run