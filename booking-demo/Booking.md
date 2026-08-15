# Booking demo — preventing double booking

Teaching implementation of inventory/seat booking concurrency. Not a production ticket platform.

## Requirements

**In scope**

- Show a race: two users both read “available” and both confirm.
- Show database fixes: pessimistic `SELECT ... FOR UPDATE`, optimistic `@Version`, atomic `UPDATE ... WHERE remaining >= qty`.
- Show lost updates on a counter vs `value = value + 1`.
- Show a Redis mutex for multi-instance mutual exclusion.
- Show hold → confirm → expiry cleanup.
- Show a unique `(event, seat)` constraint as a last safety net.

**Out of scope**

- Payments, auth, real Ticketmaster scale, multi-region replication.

## Mapping (concept → API)

| Layer | Strategy | Demo path | Default for learning |
|-------|----------|-----------|----------------------|
| 0 | No lock (broken) | `/race-condition`, `/unsafe-inventory`, `/unsafe-counter` | Hit these first |
| 1 | Pessimistic row lock | `/pessimistic-lock`, `/pessimistic-inventory` | High contention seats |
| 1 | Optimistic version | `/optimistic-lock` | Low contention |
| 2 | Atomic SQL guard | `/atomic-update`, `/atomic-counter` | Preferred for counts |
| 3 | Redis `SET NX` | `/distributed-lock` | Multiple app processes |
| 4 | Hold & confirm | `/hold-and-confirm` | Pay-later flows |
| 5 | Unique index | `/unique-constraint` | Always keep this |

Production systems usually combine **atomic stock updates** + **hold/confirm** + **unique constraints**. Distributed locks help when the critical section spans more than one row or more than one datastore.

## Failure modes called out in the demo

- **Race / oversell:** unsafe read-then-write. Timeline shows two READs of `booked=false`.
- **Pessimistic blocking:** second thread’s `elapsedMs` is ~`delayMs` because it waited on the row lock. Risk in production: long transactions and deadlocks if lock order is inconsistent.
- **Optimistic retries:** loser must retry; under flash-sale contention this thrashes.
- **Atomic UPDATE:** highest throughput for “decrement if remaining ≥ n”. Complex rules still need a lock or a state machine.
- **Distributed lock:** TTL must outlive the work or a crash leaves a lock until expiry. Demo only deletes the key if the token still matches.
- **Hold expiry:** `HoldCleanupJob` runs every 5 seconds. Confirm after `heldUntil` releases the seat.
- **Unique constraint:** application `exists()` is not enough; the index is the last net.

## Seed rows

- Seat `A1` on unsafe / pessimistic / optimistic / holdable tables.
- `LAST-TICKET` quantity 1, `WIDGET` quantity 5.
- Counter `page-views` starting at 0.
- Unique bookings for event `100` / seat `A1` are cleared on each unique-constraint run.
