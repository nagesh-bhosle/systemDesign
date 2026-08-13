# Local delivery (GoPuff-style) — design notes

Interview-style problem: **availability by location** plus **orders that cannot double-book** physical inventory. Payments, routing, catalog search, and cancellations are out of scope.

## Requirements we implement

**Functional**

- Availability for a lat/lon is the **union of inventory** at DCs that can deliver in about one hour.
- A customer can order **multiple items** in one request.

**Non-functional**

- Availability path should stay cheap (cache, short TTL).
- Orders are **strongly consistent** (one physical unit, one buyer).
- Scale story: many DCs, large catalog, order volume much smaller than browse QPS.

## Entities

| Entity | Meaning |
|--------|---------|
| Item | Catalog type (e.g. Cheetos), not a physical bag |
| DistributionCenter | Warehouse with lat/lon and a region id (zip prefix) |
| Inventory | Quantity of an item **at a DC** |
| Order / OrderLine | Confirmed reservation, allocated to specific DCs |

## APIs

- `GET /api/availability?lat=&lon=` — nearby DCs, then sum quantities by item
- `POST /api/orders` — allocate from nearest DCs, all-or-nothing

## Alternatives (see `application.yml`)

**Nearby**

- `haversine` — crow-flies miles vs a threshold (ignores roads/traffic)
- `travel-time-all` — travel-time for every DC (too many estimates)
- `travel-time-pruned` — radius prune, then travel-time (**default**)

**Availability reads**

- `postgres` — query inventory tables
- `cache` — Redis per-DC snapshots, TTL, invalidate on order (**default**)

**Orders**

- `distributed-lock` — Redis locks on sorted inventory keys, then DB writes (deadlock-safe; crash/TTL documented)
- `postgres-serializable` — one ACID transaction (**default**)

**Travel time in this demo**

- `mock` — distance plus a DC traffic factor (Camden is “across the river”)
- `haversine` — minutes from distance / assumed speed only

Read replicas and zip-prefix partitioning are **modeled** (`regionId`) but run as a single Postgres in Docker.

## Allocation

Greedy from the nearest serviceable DC. If any line cannot be filled, the whole order fails.

## References

Public breakdown: https://www.hellointerview.com/learn/system-design/problem-breakdowns/gopuff
