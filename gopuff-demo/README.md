# GoPuff-style local delivery

Runnable demo of availability-by-location plus orders that cannot double-book physical inventory. Design notes: [Gopuff.md](./Gopuff.md).

## Quick start

```bash
cd gopuff-demo
./start.sh
```

Open http://localhost:8082

Stop with `./stop.sh`.

Needs Docker (Postgres on **5434**, Redis on **6380**) and Java 21.

## Strategy flags (`application.yml`)

All Hello Interview alternatives are real beans. Change a flag and restart.

```yaml
gopuff:
  nearby:
    strategy: travel-time-pruned   # haversine | travel-time-all | travel-time-pruned
  travel-time:
    provider: mock                 # mock | haversine
  inventory:
    read-path: cache               # postgres | cache
  orders:
    consistency: postgres-serializable  # postgres-serializable | distributed-lock
```

| Flag | HI rating | Behavior |
|------|-----------|----------|
| `nearby=haversine` | Bad | Crow-flies miles vs `prune-radius-miles` |
| `nearby=travel-time-all` | Bad | Travel-time for every DC |
| `nearby=travel-time-pruned` | Great (default) | Radius prune, then travel-time |
| `travel-time=mock` | Demo (default) | Distance × per-DC `trafficFactor` (Camden is “across the river”) |
| `travel-time=haversine` | Simple | Minutes from distance / 30 mph |
| `inventory.read-path=postgres` | Baseline | Query inventory tables |
| `inventory.read-path=cache` | Great (default) | Redis per-DC snapshots, TTL, invalidate on order |
| `orders=distributed-lock` | Good | Sorted Redis locks, then DB writes; lock TTL if a process dies |
| `orders=postgres-serializable` | Great (default) | One ACID transaction + retry on serialization failure |

Allocation is greedy from the nearest serviceable DC. If any line cannot be filled, the **whole order fails**.

`regionId` (first three zip digits) is stored for a partitioning / replica-routing discussion. Docker runs a **single** Postgres: availability conceptually reads a replica; orders write the leader.

## APIs

```
GET  /api/availability?lat=39.9526&lon=-75.1652&page=0&size=20
GET  /api/items
POST /api/orders
GET  /api/orders/{id}
GET  /api/config
```

```json
POST /api/orders
{
  "userId": "alice",
  "lat": 39.9526,
  "lon": -75.1652,
  "lines": [{ "itemId": 4, "quantity": 1 }]
}
```

`201` on success. `409` if stock is gone, the location is not serviceable, or a lock/serialization conflict remains after retries.

SKU `LAST-UNIT` is seeded with quantity **1** at Center City so two concurrent buyers can demonstrate oversell protection.

## Seed geography (Philadelphia)

| DC | Notes |
|----|--------|
| Center City, Fishtown, University City | In-town, mock traffic ~1.0–1.1 |
| Camden | Close in miles, `trafficFactor=3.2` so pruned travel-time often **excludes** it |
| King of Prussia | Farther; included only when the location is nearby |

## Tests

```bash
./mvnw test
```

`ConcurrentOrderTest` races two orders for the last unit and expects exactly one `201` and one `409`.
