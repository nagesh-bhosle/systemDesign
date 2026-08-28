# Cassandra Demo Improvement TODO

Reviewed: 2026-08-28
Scope: `systemDesign/cassandra-demo/cassandra-demo`

## P0 — Make the project reproducible and correct

- [x] Unify the keyspace name across `application.yml`, `CassandraConfig`, and CQL scripts.
- [x] Define one canonical `sensor_readings` schema matching `SensorReading`.
- [x] Use one Cassandra session configuration; remove hard-coded keyspace and infrastructure values.
- [x] Configure contact point, port, local datacenter, keyspace, and optional credentials from environment variables.
- [x] Pin compatible Java and Cassandra container images.
- [x] Make Docker Compose start both Cassandra and the Spring Boot app.
- [x] Add Cassandra health/readiness handling and deterministic schema/seed initialization.
- [x] Update the Dockerfile from Java 11 to a Java 17 runtime.

## P1 — Correct the demonstrations

- [x] Model partitioning and clustering with `PRIMARY KEY ((sensor_id), timestamp, id)`.
- [x] Replace unbounded `findAll()` partition reads with bounded partition-key queries.
- [x] Make the clustering page query and display one sensor partition in clustering order.
- [x] Rename topology actions as simulation, or implement a truthful non-mutating status/demo flow.
- [x] Implement consistency-level experiments using explicit driver consistency levels, clearly labeled as illustrative.
- [x] Clarify versioned writes as last-write-wins, or implement application-level optimistic versioning.
- [x] Fix Snowflake sequence rollover, configurable worker ID, and server-side batch limits.
- [x] Remove dead or generic services that interpolate arbitrary CQL identifiers.

## P1 — Security and API hardening

- [ ] Validate request bodies and query parameters with consistent error responses.
- [ ] Allowlist any CQL identifiers; never accept arbitrary keyspace/table/column names from clients.
- [ ] Replace dynamic `innerHTML` rendering with safe DOM/text rendering everywhere.
- [ ] Protect or disable mutation/admin endpoints outside a local demo profile.
- [ ] Bind local-only defaults and document that the demo is not production-safe.

## P1/P2 — Tests and maintainability

- [ ] Add unit tests for Snowflake generation, rollover, concurrency, and clock rollback.
- [ ] Add MockMvc tests for page/API routes, HTTP methods, validation, and status codes.
- [ ] Add a Testcontainers Cassandra integration test for schema and repository persistence.
- [ ] Add Docker Compose smoke testing.
- [ ] Add Maven Wrapper, dependency scanning, and a clean-checkout CI build.
- [ ] Add Thymeleaf fragments for the shared navigation/footer.
- [ ] Add labels, `aria-live` regions, semantic table sections, and consistent loading/error states.

## Recommended implementation batches

1. **Runtime foundation:** canonical schema/config, Java 17 image, pinned Cassandra, Compose app service, health/readiness, README.
2. **Demo correctness:** partition/clustering queries, truthful topology simulation, consistency experiment, versioning semantics, Snowflake hardening.
3. **Security and quality:** validation, safe rendering, access controls/profile gating, tests, CI.

## Review notes

- The project currently builds only after prior repairs, but the current Docker Compose setup previously OOM-killed two Cassandra nodes on this machine.
- DeepSeek V4 Flash was requested, but it is not available as an execution model in this session; implementation must use the available coding agent unless the user changes the model/runtime.
- Do not merge to `main` without explicit user confirmation.
