# cassandra-demo

A small educational demo of Apache Cassandra using Spring Boot, Thymeleaf, and Docker.
It walks through the core Cassandra concepts: partition keys, clustering order, tunable
consistency, replication, writes, and Snowflake-style time-ordered IDs.

## Stack

- Java 17, Spring Boot 2.6, Spring Data Cassandra
- Cassandra 4.1 (single node in Docker)
- Thymeleaf + a small vanilla JS/CSS frontend

## Quick start (Docker)

Build the app JAR (the Compose `app` service builds from `docker/Dockerfile`, which copies
`target/cassandra-demo-0.0.1-SNAPSHOT.jar`):

```bash
mvn clean package -DskipTests
cd docker
docker compose up --build
```

Then open http://localhost:8080

- Cassandra is exposed on `localhost:9042`.
- The schema (`src/main/resources/cql/schema.cql`) and seed data
  (`src/main/resources/cql/seed-data.cql`) are applied automatically on first boot via the
  Cassandra Docker image's init directory.
- The app starts only after Cassandra reports healthy, then serves on port 8080.

Stop everything with:

```bash
docker compose down
```

To reset data (delete the Cassandra volume) and start clean:

```bash
docker compose down -v
docker compose up --build
```

## Run locally (no Docker)

Start any Cassandra 4.1 instance on `localhost:9042` with keyspace `cassandra_demo`
(replication factor 1) and the schema from `src/main/resources/cql/schema.cql`:

```bash
mvn spring-boot:run
```

## Configuration (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `CASSANDRA_CONTACT_POINTS` | `localhost` | Comma-separated contact points |
| `CASSANDRA_PORT` | `9042` | Native transport port |
| `CASSANDRA_KEYSPACE` | `cassandra_demo` | Keyspace name |
| `CASSANDRA_LOCAL_DATACENTER` | `datacenter1` | Local DC for the driver |

The Compose `app` service sets these to the internal `cassandra` hostname automatically.

## Health check

The app exposes Spring Boot Actuator:

- `GET /actuator/health` — overall health, includes Cassandra reachability
- `GET /actuator/info` — app info

## Notes and limitations

- This is a **local, single-node demo**, not a production system. There is no authentication,
  and admin-style endpoints are simulated.
- With a single node, replication factor is 1; consistency levels such as `QUORUM` are
  discussed conceptually rather than demonstrated across replicas.
- The topology page simulates node add/remove; it does not change the running cluster.
