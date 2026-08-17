# Distributed Message Processing Lab
## Implementation Specification for LLM-Assisted Development

> **Purpose of this document:** This is a complete, unambiguous specification for building a demo Spring Boot application that compares two distributed scheduling strategies: **Redis distributed locks** and **database-based atomic claiming**. Feed this entire document to your implementing LLM. Every file, configuration, class, and script is specified. Do not deviate from the interfaces and endpoints defined here - they exist so the demo can be driven and verified.

---

## 1. Learning Objectives

By the end of this demo you will have running code that proves:

1. Multiple `@Scheduled` processors on the same JVM reliably simulate a multi-instance cluster.
2. A naive scheduler processes messages twice when more than one scheduler runs (the failure mode both strategies fix).
3. A Redis-based distributed lock (`SET NX PX` + TTL lease) coordinates schedulers for one message class.
4. A database-based claim (`UPDATE` with `FOR UPDATE SKIP LOCKED`, or SQL Server `UPDLOCK, READPAST`) coordinates schedulers for another message class.
5. Lease expiry and crash recovery work in both strategies: a killed scheduler's messages are automatically reclaimed.
6. Idempotent final updates (guarded by a claim token) make late writes harmless.

---

## 2. High-Level Architecture

```
                        +-----------------------------+
                        |      RabbitMQ (Docker)      |
                        |  queues: q.intraday, q.eod  |
                        +--------------+--------------+
                                       | consume
                                       v
                        +-----------------------------+
                        |   Spring Boot Application   |
                        |                             |
                        |  MessageListener            |
                        |    -> persists as status=NEW|
                        |                             |
                        |  +-----------------------+  |
                        |  | Simulated Cluster     |  |
                        |  |  scheduler-1 (bean)   |  |
                        |  |  scheduler-2 (bean)   |  |
                        |  |  scheduler-3 (bean)   |  |
                        |  |  each polls every 3s  |  |
                        |  +----------+------------+  |
                        |             |               |
                        |   +---------v---------+     |
                        |   | CoordinatorRouter |     |
                        |   +--+-------------+--+     |
                        |      |             |        |
                        |  INTRADAY         EOD      |
                        |      |             |        |
                        |  +---v----+   +----v-----+  |
                        |  | Redis  |   | DB claim |  |
                        |  | lock   |   | + lease  |  |
                        |  | + TTL  |   | + sweeper|  |
                        |  +---+----+   +----+-----+  |
                        |      |             |        |
                        +------|-------------|--------+
                               v             v
                        +------+-------------+--------+
                        |  PostgreSQL (Docker)        |
                        |  table: messages            |
                        |  NEW -> PROCESSING -> DONE  |
                        +-----------------------------+

                        +-----------------------------+
                        |  Redis (Docker)             |
                        |  locks: lock:msg:<id>       |
                        +-----------------------------+
```

**Message flow:**

1. Client POSTs to `/api/produce?type=INTRADAY&count=50` (or `EOD`).
2. Producer publishes JSON to RabbitMQ (`q.intraday` / `q.eod`).
3. A single `@RabbitListener` consumes and inserts a row into `messages` with `status = NEW`. The queue guarantees durability; the DB guarantees visibility.
4. Three scheduler beans (the simulated instances) poll every 3 seconds. Each calls the coordinator for its message type.
5. INTRADAY messages are claimed via Redis lock; EOD messages via DB atomic claim.
6. Processing is simulated (`Thread.sleep(500-1500ms)`), then the message transitions `PROCESSING -> DONE` with an idempotent guarded update.
7. Lease recovery: if a scheduler dies mid-processing, the Redis lock TTL expires (INTRADAY) or the DB lease sweeper requeues (EOD).


---

## 3. Technology Stack

| Component | Choice | Reason |
|---|---|---|
| Java | 21 | Latest LTS |
| Spring Boot | 3.3.x | Current stable |
| Message broker | RabbitMQ 3.13 (Docker) | Simple, durable, Spring AMQP support |
| Database | PostgreSQL 16 (Docker) | `FOR UPDATE SKIP LOCKED` support |
| Lock provider | Redis 7 (Docker) | `SET NX PX` semantics |
| Build | Maven | Convention |
| UI | Single static HTML page + Server-Sent Events | Zero-dependency live visualization |
| Containers | docker-compose | One command spins everything |

---

## 4. Project Structure

```
distributed-scheduling-lab/
|-- docker-compose.yml
|-- pom.xml
|-- README.md
`-- src/main/
    |-- java/com/example/lab/
    |   |-- LabApplication.java
    |   |-- config/
    |   |   |-- RabbitConfig.java
    |   |   |-- RedisConfig.java
    |   |   `-- SchedulerConfig.java
    |   |-- domain/
    |   |   |-- Message.java
    |   |   |-- MessageType.java
    |   |   `-- MessageStatus.java
    |   |-- repo/
    |   |   `-- MessageRepository.java
    |   |-- mq/
    |   |   |-- MessageProducer.java
    |   |   `-- MessageListener.java
    |   |-- coordination/
    |   |   |-- Coordinator.java            (interface)
    |   |   |-- RedisLockCoordinator.java   (INTRADAY strategy)
    |   |   |-- DbClaimCoordinator.java     (EOD strategy)
    |   |   `-- NaiveCoordinator.java       (broken, for contrast)
    |   |-- scheduling/
    |   |   |-- SchedulerInstance.java      (one simulated node)
    |   |   |-- SchedulerRegistry.java      (creates 3 instances)
    |   |   `-- LeaseSweeper.java           (lease recovery)
    |   |-- processing/
    |   |   `-- ProcessingSimulator.java
    |   |-- api/
    |   |   |-- ProduceController.java
    |   |   |-- DashboardController.java    (SSE stream + stats)
    |   |   `-- KillController.java         (simulate crash)
    |   `-- events/
    |       |-- ProcessingEvent.java
    |       `-- EventBus.java               (in-memory pub/sub for SSE)
    `-- resources/
        |-- application.yml
        |-- schema.sql
        `-- static/
            `-- index.html                (live dashboard)
```

---

## 5. Database Schema (schema.sql)

Single table. The EOD strategy claims rows here; the INTRADAY strategy uses it for status bookkeeping (the lock itself lives in Redis). Add a `processed_count` column so naive-mode duplicates are directly observable.

```sql
CREATE TABLE IF NOT EXISTS messages (
    id              BIGSERIAL PRIMARY KEY,
    type            VARCHAR(10)  NOT NULL,                 -- 'INTRADAY' | 'EOD'
    payload         TEXT         NOT NULL,
    status          VARCHAR(20)  NOT NULL DEFAULT 'NEW',   -- NEW | PROCESSING | DONE
    claimed_by      VARCHAR(50),
    claim_token     UUID,
    claimed_at      TIMESTAMPTZ,
    processed_at    TIMESTAMPTZ,
    attempts        INT NOT NULL DEFAULT 0,
    processed_count INT NOT NULL DEFAULT 0,   -- incremented on EVERY completion; >1 means duplicate
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_new
    ON messages (created_at) WHERE status = 'NEW';

CREATE INDEX IF NOT EXISTS idx_messages_leased
    ON messages (claimed_at) WHERE status = 'PROCESSING';
```


---

## 6. docker-compose.yml

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: lab
      POSTGRES_USER: lab
      POSTGRES_PASSWORD: lab
    ports: ["5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U lab"]
      interval: 5s
      timeout: 3s
      retries: 10

  redis:
    image: redis:7
    ports: ["6379:6379"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10

  rabbitmq:
    image: rabbitmq:3.13-management
    environment:
      RABBITMQ_DEFAULT_USER: lab
      RABBITMQ_DEFAULT_PASS: lab
    ports: ["5672:5672", "15672:15672"]
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 5s
      timeout: 5s
      retries: 12
```

---

## 7. Core Domain

```java
// MessageStatus.java
public enum MessageStatus { NEW, PROCESSING, DONE }

// MessageType.java
public enum MessageType { INTRADAY, EOD }

// Message.java - JPA entity
@Entity
@Table(name = "messages")
public class Message {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private MessageType type;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String payload;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private MessageStatus status = MessageStatus.NEW;

    private String claimedBy;
    private UUID claimToken;
    private Instant claimedAt;
    private Instant processedAt;

    @Column(nullable = false)
    private int attempts = 0;

    @Column(nullable = false)
    private int processedCount = 0;   // duplicate detector for naive mode

    @Column(nullable = false)
    private Instant createdAt = Instant.now();

    // plain getters and setters (no Lombok)
}
```


---

## 8. The Coordination Layer (heart of the demo)

### 8.1 Interface

```java
public interface Coordinator {

    /**
     * Attempt to claim up to batchSize NEW messages for the given instance.
     * Must be atomic: two concurrent calls from different instances must
     * never return the same message.
     * @return the messages this instance now owns (possibly empty)
     */
    List<Message> claimBatch(String instanceName, int batchSize);

    /**
     * Idempotent completion. Must no-op if the caller no longer owns the
     * claim (token mismatch / lease lost).
     * @return true if this call performed the transition, false if ignored
     */
    boolean complete(Message message, String instanceName, UUID claimToken);

    /** Message type this coordinator handles. */
    MessageType handles();
}
```

### 8.2 Strategy 1 - RedisLockCoordinator (for INTRADAY)

**Semantics:** one lock per message (not per batch). Key `lock:msg:{id}`, value `{instanceName}:{claimToken}`, TTL 10 seconds (short for demo purposes). Acquire with `SET key value NX PX 10000` - atomic acquire-or-fail. Release via a Lua script that compares the value before `DEL`, so we never delete someone else's lock after our own TTL expired.

```java
@Component
public class RedisLockCoordinator implements Coordinator {

    private final StringRedisTemplate redis;
    private final MessageRepository repo;
    private static final Duration LOCK_TTL = Duration.ofSeconds(10);

    private static final DefaultRedisScript<Long> RELEASE_SCRIPT =
        new DefaultRedisScript<>(
            "if redis.call('get', KEYS[1]) == ARGV[1] then " +
            "return redis.call('del', KEYS[1]) else return 0 end",
            Long.class);

    @Override
    public List<Message> claimBatch(String instanceName, int batchSize) {
        // 1. Read candidates - NO database lock. Redis is the arbiter.
        List<Message> candidates = repo.findTop50ByTypeAndStatusOrderByCreatedAt(
                MessageType.INTRADAY, MessageStatus.NEW);

        List<Message> won = new ArrayList<>();
        for (Message m : candidates) {
            if (won.size() >= batchSize) break;

            UUID token = UUID.randomUUID();
            String key   = "lock:msg:" + m.getId();
            String value = instanceName + ":" + token;

            // SET key value NX PX 10000  (atomic acquire-or-fail)
            Boolean acquired = redis.opsForValue()
                    .setIfAbsent(key, value, LOCK_TTL);

            if (Boolean.TRUE.equals(acquired)) {
                // 2. Bookkeeping in DB - guarded so we only flip NEW rows
                int updated = repo.markProcessing(
                        m.getId(), instanceName, token, Instant.now());
                if (updated == 1) {
                    m.setClaimToken(token);
                    won.add(m);
                } else {
                    // Someone else beat us in the DB - release our lock
                    redis.execute(RELEASE_SCRIPT, List.of(key), value);
                }
            }
            // acquired == false -> another instance holds the lock; skip silently
        }
        return won;
    }

    @Override
    public boolean complete(Message m, String instanceName, UUID claimToken) {
        // 1. Idempotent guarded transition (increments processed_count)
        int updated = repo.completeIfOwned(
                m.getId(), instanceName, claimToken, Instant.now());

        // 2. Release the lock ONLY if we still own it
        String key      = "lock:msg:" + m.getId();
        String expected = instanceName + ":" + claimToken;
        redis.execute(RELEASE_SCRIPT, List.of(key), expected);

        return updated == 1;
    }

    @Override
    public MessageType handles() { return MessageType.INTRADAY; }
}
```

**Crash recovery for INTRADAY:** no special code needed for the lock itself - if the instance dies, the key expires after 10 seconds. But the DB row is stuck at `PROCESSING`, so the shared **LeaseSweeper (9.3)** flips rows with stale `claimed_at` back to `NEW`. The Redis TTL is the lease; the sweeper reconciles the bookkeeping.


### 8.3 Strategy 2 - DbClaimCoordinator (for EOD)

**Semantics:** one atomic `UPDATE` that claims a whole batch using `FOR UPDATE SKIP LOCKED` in a subquery, returning the full rows. Lease is 30 seconds (demo value), enforced by the LeaseSweeper. The claim and its commit happen in a short transaction; processing happens outside it.

```java
@Component
public class DbClaimCoordinator implements Coordinator {

    private final MessageRepository repo;

    @Override
    @Transactional
    public List<Message> claimBatch(String instanceName, int batchSize) {
        UUID batchToken = UUID.randomUUID();
        // One statement: selects candidates, locks them (competitors skip),
        // flips to PROCESSING, returns the rows we actually won.
        return repo.claimEodBatch(instanceName, batchToken, Instant.now(), batchSize);
    }

    @Override
    public boolean complete(Message m, String instanceName, UUID claimToken) {
        return repo.completeIfOwned(
                m.getId(), instanceName, claimToken, Instant.now()) == 1;
    }

    @Override
    public MessageType handles() { return MessageType.EOD; }
}
```

### 8.4 Repository queries

```java
public interface MessageRepository extends JpaRepository<Message, Long> {

    List<Message> findTop50ByTypeAndStatusOrderByCreatedAt(
            MessageType type, MessageStatus status);

    // --- shared guarded completion (idempotent) ---
    // processed_count is incremented on every successful transition so
    // naive-mode duplicates become visible as processed_count > 1.
    @Modifying
    @Query("UPDATE Message m SET m.status = 'DONE', m.processedAt = :now, " +
           "m.processedCount = m.processedCount + 1 " +
           "WHERE m.id = :id AND m.status = 'PROCESSING' " +
           "AND m.claimedBy = :instance AND m.claimToken = :token")
    int completeIfOwned(@Param("id") Long id,
                        @Param("instance") String instance,
                        @Param("token") UUID token,
                        @Param("now") Instant now);

    // --- Redis strategy bookkeeping (guarded) ---
    @Modifying
    @Query("UPDATE Message m SET m.status = 'PROCESSING', m.claimedBy = :inst, " +
           "m.claimToken = :token, m.claimedAt = :now, " +
           "m.attempts = m.attempts + 1 " +
           "WHERE m.id = :id AND m.status = 'NEW'")
    int markProcessing(@Param("id") Long id,
                       @Param("inst") String inst,
                       @Param("token") UUID token,
                       @Param("now") Instant now);

    // --- DB strategy atomic claim (PostgreSQL dialect) ---
    @Modifying
    @Query(value = """
            WITH batch AS (
                SELECT id FROM messages
                WHERE status = 'NEW' AND type = 'EOD'
                ORDER BY created_at
                LIMIT :batchSize
                FOR UPDATE SKIP LOCKED
            )
            UPDATE messages m
            SET status      = 'PROCESSING',
                claimed_by  = :inst,
                claim_token = :token,
                claimed_at  = :now,
                attempts    = attempts + 1
            FROM batch b
            WHERE m.id = b.id
            RETURNING m.*
            """, nativeQuery = true)
    List<Message> claimEodBatch(@Param("inst") String inst,
                                @Param("token") UUID token,
                                @Param("now") Instant now,
                                @Param("batchSize") int batchSize);

    // --- lease sweeper (shared by both strategies) ---
    @Modifying
    @Query("UPDATE Message m SET m.status = 'NEW', m.claimedBy = NULL, " +
           "m.claimToken = NULL, m.claimedAt = NULL " +
           "WHERE m.status = 'PROCESSING' AND m.claimedAt < :expiredBefore")
    int requeueExpired(@Param("expiredBefore") Instant expiredBefore);
}
```

> **SQL Server variant (for reference only - this lab uses Postgres):** replace the `claimEodBatch` native query with
> `WITH batch AS (SELECT TOP (:batchSize) id FROM messages WITH (UPDLOCK, READPAST, ROWLOCK) WHERE status = 'NEW' AND type = 'EOD' ORDER BY created_at) UPDATE m SET ... OUTPUT inserted.* FROM messages m JOIN batch b ON b.id = m.id;`
> Everything else stays identical.

### 8.5 NaiveCoordinator (the broken baseline - keep it, it is the lesson)

```java
@Component
public class NaiveCoordinator implements Coordinator {
    // Deliberately WRONG: SELECT candidates, then blindly UPDATE by id
    // with no status guard and no lock. With 3 scheduler instances this
    // WILL double-process within minutes - observable via processed_count > 1.
    // Used only when lab.mode=naive to demonstrate the failure mode.
}
```

### 8.6 CoordinatorRouter

A simple component that maps `MessageType -> Coordinator`. When `lab.mode=naive`, it returns `NaiveCoordinator` for BOTH types. When `lab.mode=coordinated`, it returns `RedisLockCoordinator` for INTRADAY and `DbClaimCoordinator` for EOD.


---

## 9. The Simulated Cluster

### 9.1 SchedulerInstance - one bean per simulated node

```java
public class SchedulerInstance {

    private final String name;                    // "scheduler-1", etc.
    private final CoordinatorRouter router;
    private final ProcessingSimulator processor;
    private final EventBus events;
    private final AtomicBoolean alive = new AtomicBoolean(true);
    private final AtomicReference<String> currentWork = new AtomicReference<>("idle");

    @Scheduled(fixedDelayString = "${lab.scheduler-poll-ms:3000}")
    public void poll() {
        if (!alive.get()) return;                 // a dead instance does nothing
        for (MessageType type : MessageType.values()) {
            Coordinator c = router.forType(type);
            List<Message> batch = c.claimBatch(name, 5);
            for (Message m : batch) {
                currentWork.set(type + " #" + m.getId());
                events.publish(ProcessingEvent.claimed(m, name));
                try {
                    processor.process(m);         // sleeps 500-1500 ms
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return;
                }
                boolean ok = c.complete(m, name, m.getClaimToken());
                events.publish(ok
                        ? ProcessingEvent.completed(m, name)
                        : ProcessingEvent.lateWriteRejected(m, name));
                currentWork.set("idle");
            }
        }
    }

    public void kill()   { alive.set(false); }    // simulate crash / scale-down
    public void revive() { alive.set(true);  }    // simulate scale-up
    public boolean isAlive()       { return alive.get(); }
    public String  getName()       { return name; }
    public String  getCurrentWork(){ return currentWork.get(); }
}
```

### 9.2 SchedulerRegistry

Registers three `SchedulerInstance` beans named `scheduler-1`, `scheduler-2`, `scheduler-3`. **Important:** all three share one JVM (same connection pools, same Redis connection). This is acceptable for the demo and actually makes contention more aggressive, since all schedulers fire on near-identical timing. Add a code comment stating clearly: this simulates a cluster for coordination-behavior purposes; it does not simulate network partitions.

### 9.3 LeaseSweeper - shared crash-recovery daemon

```java
@Component
public class LeaseSweeper {

    private final MessageRepository repo;
    private final EventBus events;

    private static final Duration LEASE = Duration.ofSeconds(30);  // demo value

    @Scheduled(fixedDelay = 5000)
    public void sweep() {
        int requeued = repo.requeueExpired(Instant.now().minus(LEASE));
        if (requeued > 0) {
            events.publish(ProcessingEvent.requeued(requeued));
        }
    }
}
```

One sweeper covers both strategies: for EOD it reclaims rows whose owning instance died; for INTRADAY it reconciles DB state after the Redis lock has already expired on its own.

---

## 10. Messaging In / Out

### 10.1 Producer endpoint

```
POST /api/produce?type=INTRADAY&count=50
POST /api/produce?type=EOD&count=20
```

Publishes `count` JSON messages of the form `{ "type": "INTRADAY", "payload": "order-<random>" }` to the corresponding queue. Returns `{ "published": 50 }`.

### 10.2 Listener

```java
@RabbitListener(queues = "q.intraday")
public void onIntraday(String json) { persist(json, MessageType.INTRADAY); }

@RabbitListener(queues = "q.eod")
public void onEod(String json)      { persist(json, MessageType.EOD); }

private void persist(String json, MessageType type) {
    // insert row with status = NEW, then publish ProcessingEvent.received(...)
}
```

### 10.3 RabbitConfig

Declare two durable queues (`q.intraday`, `q.eod`), one direct exchange `lab.exchange`, and bindings `intraday` / `eod`. Default listener container settings are fine - the listener only inserts a row.


---

## 11. Live Dashboard (SSE + static HTML)

### 11.1 EventBus

In-memory broadcaster: a `CopyOnWriteArrayList<SseEmitter>` (or Reactor `Sinks.Many<ProcessingEvent>`). Every claim / complete / requeue / reject / receive publishes an event to all connected browsers.

### 11.2 ProcessingEvent

```java
public record ProcessingEvent(
        String kind,        // RECEIVED | CLAIMED | COMPLETED | LATE_WRITE_REJECTED | REQUEUED | INSTANCE_KILLED | INSTANCE_REVIVED
        Long messageId,
        String messageType,
        String instance,    // null for RECEIVED
        Instant at
) {
    public static ProcessingEvent received(Message m)               { ... }
    public static ProcessingEvent claimed(Message m, String inst)   { ... }
    public static ProcessingEvent completed(Message m, String inst) { ... }
    public static ProcessingEvent lateWriteRejected(Message m, String inst) { ... }
    public static ProcessingEvent requeued(int count)               { ... }
    // factory bodies fill the fields above
}
```

### 11.3 Endpoints

```
GET  /api/stream           -> text/event-stream, emits ProcessingEvent JSON
GET  /api/stats            -> { "NEW":        {"INTRADAY": n, "EOD": n},
                               "PROCESSING":  {"INTRADAY": n, "EOD": n},
                               "DONE":        {"INTRADAY": n, "EOD": n},
                               "duplicates":  n,   // rows with processed_count > 1
                               "instances":   [{"name": "...", "alive": bool, "currentWork": "..."}] }
POST /api/kill/{name}      -> kill a scheduler instance (simulate crash)
POST /api/revive/{name}    -> revive it (simulate scale-up)
POST /api/reset            -> truncate messages table, clear event state
```

### 11.4 index.html requirements

A single self-contained page (plain JS + `EventSource`, no framework) showing:

1. **Pipeline view** - three columns NEW / PROCESSING / DONE with message chips flowing between them, colored by type (INTRADAY = blue, EOD = amber). A chip that arrives in DONE twice (naive mode) flashes red.
2. **Instance panel** - three cards for scheduler-1/2/3 showing alive/dead state, the message currently being processed, and a heartbeat dot. Dead instances render grey with a red border.
3. **Controls** - buttons: "Produce 50 INTRADAY", "Produce 20 EOD", "Kill scheduler-2", "Revive scheduler-2", "Reset".
4. **Event log** - scrolling timestamped log. Highlight `LATE_WRITE_REJECTED` in red and `REQUEUED` (lease expired) in orange.
5. **Stats bar** - counts per state and a prominent `duplicates` counter (must stay 0 in coordinated mode; grows in naive mode).

---

## 12. Demo Scripts (what the user will run)

### Script A - naive failure (baseline)
1. Start with `lab.mode=naive`.
2. Produce 50 INTRADAY.
3. Watch the log: the same message id is CLAIMED by two schedulers and completed twice. The `duplicates` counter grows.
4. Verify in DB: `SELECT id, processed_count FROM messages WHERE processed_count > 1;` returns rows.
5. Conclusion: this is why coordination exists.

### Script B - Redis lock (INTRADAY)
1. Start with `lab.mode=coordinated`. Produce 50 INTRADAY.
2. Every message claimed exactly once; log shows lock acquisitions and silent skips.
3. Mid-processing, call `POST /api/kill/scheduler-2`. Its 10s Redis TTL expires, the sweeper requeues its rows, another instance completes them.
4. Verify: `duplicates` stays 0.

### Script C - DB claim (EOD)
1. Produce 20 EOD.
2. Log shows atomic batch claims; competing schedulers skip locked rows.
3. Kill scheduler-1 mid-batch. After the 30s lease, the sweeper requeues; a survivor completes them.
4. Verify: `duplicates` stays 0.

### Script D - idempotent late write
1. Add a config property `lab.slow-message-id` that makes ProcessingSimulator sleep 40s (beyond the lease) for one chosen message.
2. The lease expires, another instance reprocesses and completes it.
3. The original instance wakes and calls `complete()` -> `completeIfOwned` returns 0 -> log shows `LATE_WRITE_REJECTED (token mismatch)`. State stays correct, `duplicates` stays 0.


---

## 13. application.yml

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/lab
    username: lab
    password: lab
  jpa:
    hibernate:
      ddl-auto: none          # schema.sql is authoritative
    properties:
      hibernate.jdbc.time_zone: UTC
  sql:
    init:
      mode: always            # executes schema.sql at startup
  data:
    redis:
      host: localhost
      port: 6379
  rabbitmq:
    host: localhost
    port: 5672
    username: lab
    password: lab

lab:
  mode: coordinated           # naive | coordinated
  batch-size: 5
  scheduler-poll-ms: 3000
  lease-seconds: 30
  redis-lock-ttl-ms: 10000
  processing-delay-min-ms: 500
  processing-delay-max-ms: 1500
  slow-message-id:            # optional: id that sleeps 40s (Script D)
```

---

## 14. pom.xml dependencies

- `spring-boot-starter-web`
- `spring-boot-starter-data-jpa`
- `spring-boot-starter-data-redis`
- `spring-boot-starter-amqp`
- `org.postgresql:postgresql` (runtime)
- No Lombok - plain getters/setters so generated code is explicit and debuggable.

---

## 15. Acceptance Criteria (the implementing LLM must verify every one)

1. `docker compose up -d` starts Postgres, Redis, RabbitMQ; all healthchecks pass.
2. `mvn spring-boot:run` starts cleanly; the schema exists; three scheduler beans are polling.
3. `POST /api/produce?type=INTRADAY&count=50` results in 50 rows with status NEW.
4. In coordinated mode, INTRADAY messages complete with zero duplicates (`processed_count = 1` for all rows) even when a scheduler is killed mid-batch.
5. In coordinated mode, EOD messages complete with zero duplicates even when a scheduler is killed mid-batch.
6. In naive mode, duplicates demonstrably occur (`processed_count > 1` for some rows) - this is the control experiment.
7. Killing a scheduler (`POST /api/kill/scheduler-2`) never loses a message: all its in-flight messages are completed by survivors within lease + sweeper interval.
8. The dashboard at `http://localhost:8080` updates live via SSE with no page refresh.
9. The event log visibly distinguishes: RECEIVED, CLAIMED, COMPLETED, LATE_WRITE_REJECTED, REQUEUED, INSTANCE_KILLED, INSTANCE_REVIVED.
10. `completeIfOwned` returning 0 never throws and never corrupts state - this is the idempotency proof.

---

## 16. Key Invariants (embed these as code comments)

1. **A message may be processed at most once successfully.** Enforced by the `completeIfOwned` guard, not by hoping claims never collide.
2. **A message is never lost.** Enforced by lease + sweeper, not by hoping instances never die.
3. **Coordination is per-strategy; recovery is shared.** Redis TTL for INTRADAY, DB lease for EOD; one sweeper reconciles both.
4. **Instance count is unknowable and irrelevant.** Schedulers join and leave freely; correctness comes from atomic claims and idempotent writes, never from membership tracking.
5. **The broker feeds the DB; the DB is the work queue.** RabbitMQ guarantees ingestion durability; the `messages` table is the single source of truth for processing state.

---

## 17. Suggested Implementation Order for the LLM

1. docker-compose.yml + schema.sql + application.yml - verify infrastructure boots.
2. Domain entities + repository - verify schema mapping.
3. Producer + listener - verify NEW rows appear from queue messages.
4. NaiveCoordinator + one scheduler, then three - run Script A (duplicates observed).
5. RedisLockCoordinator - run Script B.
6. DbClaimCoordinator + LeaseSweeper - run Script C.
7. Kill/revive endpoints + SSE dashboard - make Scripts B and C observable live.
8. Slow-message injection - run Script D.
9. Dashboard polish.

---

## 18. Known Limitations of the Simulation (state these in the README)

1. All three "instances" share one JVM - no real network partition behavior is simulated.
2. Lease values (30s DB, 10s Redis) are demo-shortened; production values would be minutes.
3. Processing is a sleep - no real downstream calls, so idempotency of external side effects is out of scope (but the guarded-write pattern that enables it is demonstrated).
4. The queue-to-DB hop is intentionally synchronous and simple; in production you might process directly from the broker with consumer groups instead - this lab isolates the scheduling-coordination concern on purpose.
