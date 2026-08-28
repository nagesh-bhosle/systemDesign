# Java 17 runtime to match the Maven build (java.version=17)
FROM eclipse-temurin:17-jre

# Run as a non-root user
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app

# Copy the Maven build artifact (JAR file) into the container
COPY --chown=appuser:appuser target/cassandra-demo-0.0.1-SNAPSHOT.jar cassandra-demo.jar

USER appuser

# Expose the application port
EXPOSE 8080

# Actuator health endpoint used by Docker/CI readiness checks
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
  CMD wget -q -O - http://127.0.0.1:8080/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "-jar", "cassandra-demo.jar"]