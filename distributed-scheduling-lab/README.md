# Distributed Scheduling Lab

A Spring Boot demo that compares **distributed scheduling strategies** on a live,
visualizable pipeline:

| Message class | Strategy | Mechanism |
|---|---|---|
| `INTRADAY` | Redis distributed lock | `SET key value NX PX <ttl>` + Lua compare-and-delete release |
| `EOD` | Database atomic claim | `UPDATE ... FOR UPDATE SKIP LOCKED` in a CTE, `RETURNING` the claimed rows |
| (baseline) | Naive — deliberately broken | unguarded SELECT + blind UPDATE ⇒ duplicates |

Three `@Scheduled` "instances" (`scheduler-1/2/3`) run in one JVM and contend for
the same rows. A shared **lease sweeper** recovers messages from dead instances.
A single-page dashboard (SSE, no framework) shows the pipeline, instances,
events and the all-important **duplicates** counter live.

## Stack

Java 21 · Spring Boot 3.3.x · PostgreSQL 16 · Redis 7 · RabbitMQ 3.13 · Maven

## Quickstart

```bash
cd systemDesign/distributed-scheduling-lab

# 1. infrastructure (Postgres :5432, Redis :6379, RabbitMQ :5672/:15672)
docker compose up -d

# 2. the app (starts on :8080)
./mvnw spring-boot:run

# 3. open the dashboard
open http://localhost:8080
```

Or use the convenience scripts: `./start.sh` / `./stop.sh`.

Switch coordination mode at startup:

```bash
./mvnw spring-boot:run -Dspring-boot.run.arguments=--lab.mode=naive
```

## Demo scripts

### Script A — naive failure (the baseline)

1. Start with `--lab.mode=naive`.
2. Dashboard → **Produce 50 INTRADAY**.
3. Watch the log: the same message id is CLAIMED by two schedulers and completed
   twice; chips in DONE flash red (`×2`); the **duplicates** counter grows.
4. Verify in the DB:

   ```sql
   SELECT id, processed_count FROM messages WHERE processed_count > 1;
   ```

5. Conclusion: this is why coordination exists.

### Script B — Redis lock (INTRADAY)

1. Restart with `--lab.mode=coordinated`. **Produce 50 INTRADAY**.
2. Every message is claimed exactly once; competing instances silently fail the
   `SET NX` and skip.
3. Mid-processing, click **Kill scheduler-2** (or `POST /api/kill/scheduler-2`).
   Its 10s Redis TTL expires, the sweeper requeues its rows (`REQUEUED` in
   orange), a survivor completes them.
4. Verify: **duplicates stays 0**.

### Script C — DB claim (EOD)

1. **Produce 20 EOD**.
2. The log shows atomic batch claims; competing schedulers `SKIP LOCKED` past
   locked rows.
3. Kill `scheduler-1` mid-batch. After the 30s lease the sweeper requeues; a
   survivor completes them.
4. Verify: **duplicates stays 0**.

### Script D — idempotent late write

1. Pick a message id that is still `NEW` (e.g. from the dashboard chips), then
   restart with it configured:

   ```bash
   ./mvnw spring-boot:run -Dspring-boot.run.arguments=--lab.slow-message-id=42
   ```

2. Produce more messages. When #42 is claimed, its instance sleeps **40s** —
   beyond any lease. The lease expires, another instance reprocesses and
   completes it.
3. The original instance wakes and calls `complete()` → `completeIfOwned`
   returns 0 → the log shows `LATE_WRITE_REJECTED` (red). State stays correct,
   **duplicates stays 0**.

## Verification SQL

```sql
-- duplicates (must be empty in coordinated mode)
SELECT id, type, processed_count, attempts FROM messages WHERE processed_count > 1;

-- pipeline state
SELECT status, type, count(*) FROM messages GROUP BY status, type ORDER BY status;

-- in-flight claims (lease candidates)
SELECT id, claimed_by, claimed_at FROM messages WHERE status = 'PROCESSING';
```

Connect: `docker compose exec postgres psql -U lab -d lab`

## API

| Endpoint | Effect |
|---|---|
| `POST /api/produce?type=INTRADAY&count=50` | publish n messages → queue → persisted as `NEW` |
| `GET /api/stream` | SSE stream of `ProcessingEvent`s |
| `GET /api/stats` | per-state/per-type counts, `duplicates`, `instances[]`, `mode` |
| `POST /api/kill/{name}` | crash a scheduler (abandons in-flight work) |
| `POST /api/revive/{name}` | revive a scheduler |
| `POST /api/reset` | truncate the messages table |

## Key invariants (spec §16)

1. **A message may be processed at most once successfully** — enforced by the
   guarded `completeIfOwned` update, not by hoping claims never collide.
2. **A message is never lost** — enforced by lease + sweeper, not by hoping
   instances never die.
3. **Coordination is per-strategy; recovery is shared** — Redis TTL for
   INTRADAY, DB lease for EOD; one sweeper reconciles both.
4. **Instance count is unknowable and irrelevant** — schedulers join and leave
   freely; correctness comes from atomic claims and idempotent writes.
5. **The broker feeds the DB; the DB is the work queue** — RabbitMQ guarantees
   ingestion durability; the `messages` table is the single source of truth.

## Known limitations of the simulation

1. All three "instances" share one JVM — no real network partition behavior is
   simulated.
2. Lease values (30s DB, 10s Redis) are demo-shortened; production values would
   be minutes.
3. Processing is a sleep — no real downstream calls, so idempotency of external
   side effects is out of scope (but the guarded-write pattern that enables it
   is demonstrated).
4. The queue-to-DB hop is intentionally synchronous and simple; in production
   you might process directly from the broker with consumer groups instead —
   this lab isolates the scheduling-coordination concern on purpose.
