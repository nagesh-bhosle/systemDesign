# Booking concurrency concepts

Runnable Spring Boot demo of the layers used to stop double booking and oversell. Design notes: [Booking.md](./Booking.md).

## Quick start

```bash
cd booking-demo
./start.sh
```

Open http://localhost:8083

Stop with `./stop.sh`.

Needs Docker (Postgres **5435**, Redis **6381**) and Java 21. Does not collide with Dropbox (8080), Yelp (8081), or GoPuff (8082).

## How to learn

Each **POST `/api/concepts/...`** resets the relevant row, starts two (or more) threads at the same instant, and returns:

- `problem` / `howThisEndpointWorks`
- `users[]` — who won and who lost
- `timeline[]` — ordered steps (READ, BLOCK, WRITE, exception)
- `finalState` and `invariantHeld`
- `watchInDebugger` — where to put a breakpoint

Hit the **broken** APIs first, then the **fix** APIs.

| Order | Endpoint | What you should see |
|-------|----------|---------------------|
| 1 | `POST /api/concepts/race-condition` | Both users confirm — double booking |
| 2 | `POST /api/concepts/pessimistic-lock` | One waits on `FOR UPDATE`, then rejects |
| 3 | `POST /api/concepts/optimistic-lock` | No wait; loser gets version mismatch |
| 4 | `POST /api/concepts/unsafe-inventory` | Last ticket oversold (`booked > total`) |
| 5 | `POST /api/concepts/atomic-update` | Guarded `UPDATE` — one winner |
| 6 | `POST /api/concepts/pessimistic-inventory` | Lock + Java rules on a count of 5 |
| 7 | `POST /api/concepts/unsafe-counter` | Lost updates (`value < expected`) |
| 8 | `POST /api/concepts/atomic-counter` | `value = value + 1` matches expected |
| 9 | `POST /api/concepts/distributed-lock` | Redis `SET NX` around the unsafe book |
| 10 | `POST /api/concepts/hold-and-confirm` | One HOLD; confirm with `.../confirm?userId=` |
| 11 | `POST /api/concepts/unique-constraint` | Unique `(event, seat)` rejects the second INSERT |

Query params (most endpoints): `users` (default 2), `delayMs` (default 200). A larger delay makes races easier to see and easier to catch in a debugger.

Catalog and live rows:

```
GET  /api/concepts
GET  /api/concepts/state
POST /api/concepts/reset
```

## Manual two-terminal debug

After `GET /api/concepts/state` (to copy ids):

```bash
# Terminal A
curl -X POST 'http://localhost:8083/api/debug/unsafe/1?userId=1&delayMs=4000'

# Terminal B (within 4 seconds)
curl -X POST 'http://localhost:8083/api/debug/unsafe/1?userId=2&delayMs=4000'
```

Same pattern for `/api/debug/pessimistic/{id}`, `/optimistic/{id}`, `/inventory/atomic/{id}`, `/counter/atomic/{id}`, `/distributed/{id}`, `/hold/{id}`.

SQL is logged (`spring.jpa.show-sql=true`). Watch for `FOR UPDATE`, `WHERE version=?`, and `WHERE (total - booked) >= ?`.

## Tests

```bash
./mvnw test
```

H2 profile (`application-test.yml`) proves pessimistic, optimistic, atomic inventory, atomic counter, unique constraint, and hold. Distributed lock is skipped without Redis.
