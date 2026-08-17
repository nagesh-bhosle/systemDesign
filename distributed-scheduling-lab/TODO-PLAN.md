# TODO Plan — Distributed Message Processing Lab

> **Standalone implementation plan.** Read together with `docs/spec.md` (the authoritative
> specification). This plan breaks the spec into ordered, verifiable tasks. Do not deviate
> from the interfaces, endpoints, table schema, or event kinds defined in the spec.

---

## Project facts

| Item | Value |
|---|---|
| Location | `systemDesign/distributed-scheduling-lab/` |
| Java | 21 |
| Spring Boot | 3.3.x |
| Build | Maven (with `mvnw` wrapper — copy from `../dropbox-demo/` or `../booking-demo/`) |
| Infra | PostgreSQL 16, Redis 7, RabbitMQ 3.13 via `docker-compose.yml` |
| Base package | `com.example.lab` |
| No Lombok | plain getters/setters only |
| Config | `lab.mode=naive|coordinated` selects coordination strategy |

## Hard constraints (from spec §15/§16 — verify every one)

1. `docker compose up -d` starts Postgres, Redis, RabbitMQ; healthchecks pass.
2. `mvn spring-boot:run` (or `./mvnw spring-boot:run`) starts cleanly; schema exists; 3 scheduler beans poll.
3. `POST /api/produce?type=INTRADAY&count=50` → 50 rows `status=NEW`.
4. Coordinated INTRADAY: zero duplicates (`processed_count=1` for all) even when a scheduler is killed mid-batch.
5. Coordinated EOD: zero duplicates even when a scheduler is killed mid-batch.
6. Naive mode: duplicates demonstrably occur (`processed_count > 1` for some rows).
7. Killing a scheduler never loses a message; survivors complete in-flight work within lease + sweeper interval.
8. Dashboard at `http://localhost:8080` updates live via SSE, no refresh.
9. Event log distinguishes: RECEIVED, CLAIMED, COMPLETED, LATE_WRITE_REJECTED, REQUEUED, INSTANCE_KILLED, INSTANCE_REVIVED.
10. `completeIfOwned` returning 0 never throws, never corrupts state (idempotency proof).

Key invariants to embed as code comments (spec §16): at-most-once successful processing
(guarded by `completeIfOwned`), never-lost messages (lease + sweeper), per-strategy
coordination with shared recovery, instance count unknowable/irrelevant, broker feeds DB and
DB is the work queue.

---

## Phase 1 — Infrastructure & skeleton

- [x] **T1.1** `docker-compose.yml` — exactly as spec §6 (postgres:16, redis:7, rabbitmq:3.13-management; creds `lab/lab`; ports 5432, 6379, 5672, 15672; healthchecks as specified).
- [x] **T1.2** `pom.xml` — Spring Boot 3.3.x parent, Java 21; dependencies: `spring-boot-starter-web`, `spring-boot-starter-data-jpa`, `spring-boot-starter-data-redis`, `spring-boot-starter-amqp`, `org.postgresql:postgresql` (runtime). No Lombok.
- [x] **T1.3** Copy Maven wrapper (`mvnw`, `mvnw.cmd`, `.mvn/`) from `../dropbox-demo/` so the project builds standalone.
- [x] **T1.4** `src/main/resources/application.yml` — exactly as spec §13 (ddl-auto: none, sql.init.mode: always, lab.* properties incl. `slow-message-id` optional).
- [x] **T1.5** `src/main/resources/schema.sql` — exactly as spec §5 (messages table + 2 partial indexes).
- [x] **T1.6** `LabApplication.java` with `@EnableScheduling`.
- [ ] **Verify:** `./mvnw clean compile` passes; `docker compose up -d` healthy. *(compile ✅ done; docker up deferred to Phase 8)*

## Phase 2 — Domain & repository

- [x] **T2.1** `domain/MessageStatus.java` (NEW, PROCESSING, DONE), `domain/MessageType.java` (INTRADAY, EOD).
- [x] **T2.2** `domain/Message.java` — JPA entity per spec §7, all fields incl. `attempts`, `processedCount`, plain getters/setters.
- [x] **T2.3** `repo/MessageRepository.java` — all 5 queries per spec §8.4: `findTop50ByTypeAndStatusOrderByCreatedAt`, `completeIfOwned` (increments `processedCount`), `markProcessing` (guarded `status='NEW'`), `claimEodBatch` (native CTE `FOR UPDATE SKIP LOCKED` + `RETURNING m.*`), `requeueExpired`. Add `countByStatusAndType`, `countByProcessedCountGreaterThan(1)` for stats, plus a `@Query` for stats aggregation if convenient.
- [x] **Verify:** compile passes; entity maps 1:1 to schema.sql columns.

## Phase 3 — Messaging in

- [x] **T3.1** `config/RabbitConfig.java` — durable queues `q.intraday`, `q.eod`; direct exchange `lab.exchange`; bindings `intraday`/`eod`; Jackson2JsonMessageConverter or simple String payloads.
- [x] **T3.2** `mq/MessageProducer.java` — publishes `{ "type": "...", "payload": "order-<random>" }` to correct queue.
- [x] **T3.3** `mq/MessageListener.java` — `@RabbitListener` on both queues; inserts row `status=NEW`; publishes `ProcessingEvent.received(...)`.
- [x] **T3.4** `api/ProduceController.java` — `POST /api/produce?type=&count=` → publishes count messages, returns `{ "published": n }`.
- [ ] **Verify:** produce 50 INTRADAY → 50 NEW rows. *(runtime — Phase 8)*

## Phase 4 — Coordination layer (the heart)

- [x] **T4.1** `coordination/Coordinator.java` interface — exactly per spec §8.1 (`claimBatch`, `complete`, `handles`).
- [x] **T4.2** `coordination/RedisLockCoordinator.java` — per spec §8.2: per-message lock `lock:msg:{id}` = `{instance}:{token}`, `SET NX PX` (TTL from `lab.redis-lock-ttl-ms`, default 10s), Lua release script comparing value before DEL, guarded `markProcessing`, release lock on DB-race loss, release-on-complete only if still owner.
- [x] **T4.3** `coordination/DbClaimCoordinator.java` — per spec §8.3: `@Transactional claimBatch` delegating to `claimEodBatch` (one atomic statement), `complete` via `completeIfOwned`.
- [x] **T4.4** `coordination/NaiveCoordinator.java` — deliberately broken: SELECT candidates then blind UPDATE by id, no status guard, no lock, no token; `complete` always flips to DONE and increments `processedCount`. Used only in `lab.mode=naive`.
- [x] **T4.5** `coordination/CoordinatorRouter.java` — maps type→coordinator; naive mode returns NaiveCoordinator for both types; coordinated mode returns Redis for INTRADAY, DbClaim for EOD.
- [x] **Verify:** compile; code review against spec semantics (atomicity, token guards, Lua release).

## Phase 5 — Simulated cluster & recovery

- [x] **T5.1** `scheduling/SchedulerInstance.java` — per spec §9.1: `@Scheduled(fixedDelayString="${lab.scheduler-poll-ms:3000}") poll()`, alive flag, currentWork tracking, claim→process→complete loop, events for CLAIMED/COMPLETED/LATE_WRITE_REJECTED, kill/revive/isAlive/getName/getCurrentWork.
- [x] **T5.2** `scheduling/SchedulerRegistry.java` — registers 3 beans `scheduler-1/2/3`; **comment:** simulates a cluster for coordination-behavior purposes; does not simulate network partitions. *(beans declared in `config/SchedulerConfig.java`; registry collects them for lookup)*
- [x] **T5.3** `scheduling/LeaseSweeper.java` — per spec §9.3: `@Scheduled(fixedDelay=5000)`, `requeueExpired(now - lease)` with lease from `lab.lease-seconds` (default 30), publishes REQUEUED event.
- [x] **T5.4** `processing/ProcessingSimulator.java` — sleeps random 500–1500ms (configurable via `lab.processing-delay-min-ms/max-ms`); if message id == `lab.slow-message-id`, sleep 40s (Script D).
- [ ] **Verify:** 3 instances poll; kill/revive works. *(runtime — Phase 8)*

## Phase 6 — Events, API, dashboard

- [x] **T6.1** `events/ProcessingEvent.java` — record per spec §11.2 with factories: received, claimed, completed, lateWriteRejected, requeued, instanceKilled, instanceRevived.
- [x] **T6.2** `events/EventBus.java` — in-memory broadcaster to all `SseEmitter`s (CopyOnWriteArrayList), handles emitter completion/error removal.
- [x] **T6.3** `api/DashboardController.java` — `GET /api/stream` (SSE), `GET /api/stats` (per-state per-type counts, duplicates = rows with processed_count>1, instances array with name/alive/currentWork), `POST /api/reset` (truncate messages, reset schedulers' view).
- [x] **T6.4** `api/KillController.java` — `POST /api/kill/{name}`, `POST /api/revive/{name}`; publish INSTANCE_KILLED / INSTANCE_REVIVED events; 404 for unknown name.
- [x] **T6.5** `static/index.html` — single self-contained page per spec §11.4: pipeline NEW/PROCESSING/DONE columns with chips colored by type (INTRADAY blue, EOD amber; duplicate flash red), instance cards with heartbeat, controls (Produce 50 INTRADAY, Produce 20 EOD, Kill/Revive scheduler-2, Reset), scrolling event log (LATE_WRITE_REJECTED red, REQUEUED orange), stats bar with prominent duplicates counter. Plain JS + EventSource, no framework.
- [ ] **Verify:** SSE events reach browser; stats correct; all 7 event kinds render. *(runtime — Phase 8)*

## Phase 7 — Demo scripts & README

- [x] **T7.1** `README.md` — quickstart (docker compose up, mvn spring-boot:run, open :8080), Scripts A–D from spec §12, verification SQL, and the 4 known limitations from spec §18.
- [x] **T7.2** Optional convenience `start.sh` / `stop.sh` matching sibling projects' style.

## Phase 8 — Verification (acceptance criteria §15)

- [x] **T8.1** Build passes: `./mvnw clean compile` (and ideally `./mvnw clean package -DskipTests`). *(compile ✅; package deferred to orchestrator)*
- [ ] **T8.2** Infra up: `docker compose up -d`, wait healthy.
- [ ] **T8.3** App boots; schema created; 3 schedulers polling (check logs).
- [ ] **T8.4** Script A (naive): duplicates observed via `/api/stats` duplicates > 0.
- [ ] **T8.5** Script B (coordinated INTRADAY): duplicates stay 0; kill scheduler mid-batch; recovery works.
- [ ] **T8.6** Script C (coordinated EOD): duplicates stay 0; kill mid-batch; sweeper requeues.
- [ ] **T8.7** Script D (slow message): LATE_WRITE_REJECTED observed; duplicates stay 0.
- [ ] **T8.8** Review pass: every acceptance criterion from spec §15 checked off.

---

## Definition of done

- All tasks above checked.
- `./mvnw clean compile` green.
- Acceptance criteria 1–10 (spec §15) verified or explicitly documented as blocked (e.g. Docker unavailable) with evidence.
- Code reviewed against spec: interfaces, endpoints, SQL, event kinds, invariants as comments.
