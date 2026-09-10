# Elasticsearch — Interview Notes

> Concise, bullet-heavy system design notes. Pairs with the **Elastic Search Lab** demo.

## Why Elasticsearch Exists

- **Postgres `LIKE '%term%'` = O(n) full scan** — no index can help a leading wildcard; sequential scan over every row.
- **`ILIKE` + `pg_trgm` helps but still limited** — trigram GIN is large, ranking is crude (similarity score, not TF/IDF), no fuzzy typo tolerance beyond threshold, no geo ranking.
- **`tsvector`/`tsquery` is better but still Postgres**:
  - Good for exact lexeme matching + GIN, but ranking is simple (`ts_rank`), no BM25 tuning, no per-field boosting, no typo/fuzzy, no geo BKD tree.
  - Geo via PostGIS `ST_DWithin` + GiST works for small data but degrades at scale; no distributed sharding.
- **What ES brings**: inverted index + BM25 ranking + analyzers + BKD geo trees + distributed shards — built for text + geo at scale.
- **Trade-offs of adding ES**:
  - Eventual consistency (refresh ~1s, not immediate) — not for strong-consistency reads.
  - Dual-write complexity (PG + ES must stay in sync) — extra pipeline to build and monitor.
  - Operational cost (extra cluster, heap tuning, shard management, monitoring).
  - Data duplication — PG remains source of truth, ES is a derived view you must reindex and version.

## Core Concepts

- **Hierarchy**: `Document` (JSON) -> `Index` (like a table) -> `Shard` (horizontal partition) -> `Segment` (immutable Lucene file) -> `Inverted Index` (term -> doc list).
- **Shard types**: primary (writes) + replica (reads, failover); replicas scale read throughput, not write; each shard is a full Lucene index.
- **Segment**: append-only, immutable; merged in background; deleted docs only purged on merge.
- **Inverted index**: token -> sorted posting list of doc IDs + positions/offsets; enables O(1) term lookup; stored per segment.
- **Near-real-time**: docs visible only after refresh creates a new segment; `refresh_interval` trades freshness vs throughput.
- **Analyzer chain**: `char filter` -> `tokenizer` -> `token filters`
  - e.g. `standard` tokenizer splits on word boundaries; `lowercase` + `edge_ngram` emit prefix tokens.
  - `english` analyzer adds stemming + stop-word removal for `description` in this demo.
- **Mapping types**:
  - `text` — analyzed, full-text search (e.g. `name`, `description`).
  - `keyword` — exact value, aggregations/filters (e.g. `category`, `priceRange`, `locationNames`).
  - `geo_point` — lat/lon for distance queries (BKD tree).
  - `completion` — FST-backed suggester for instant autocomplete.
  - `double` / `integer` — numeric range queries and sorting (`avgRating`, `numRatings`).

## Write Path

- App sends `bulk index` request (batch of JSON docs) — bulk is far cheaper than single-doc indexing.
- Docs go to **in-memory buffer** + **translog (WAL)** — translog fsyncs for durability (defaults to `request` or `async`).
- **Refresh (default 1s)**: buffer flushed to a new **segment**; segment becomes searchable (near-real-time, not instant).
- Translog retained until segment is **fsynced to disk** via **flush** — flush is the durability boundary.
- **Background segment merge**: small segments merged into larger ones; deleted docs purged; keeps segment count bounded and search fast.
- **Refresh != Flush**: refresh makes docs visible (NRT); flush makes them durable on disk.
- Failure: if node crashes before flush, translog replays on recovery; replicas replay from primary.

## Read Path

- Client hits **coordinator node** (any node can coordinate; often the receiving node).
- Coordinator **scatters** query to all shards (primary or replica) — fan-out.
- Each shard runs query locally: scans inverted index, computes **BM25 score** per doc, applies filters.
- Shards return top-K doc IDs + scores (+ sort values) to coordinator — only IDs cross the network.
- Coordinator **gathers & merges**: global sort, pagination (`from`/`size`), highlighting, aggregations.
- Results returned with `_score`, `took` (ES internal ms), `hits.total`, highlights and `sort` distances.
- Aggregations and `highlight` are computed per shard then merged — same scatter/gather pattern.

## Geo Search

- **Storage**: `geo_point` field indexed as **BKD tree** (block KD-tree) — efficient range/distance queries in 2D without scanning all docs.
- **`geo_distance` query**: `field + center (lat/lon) + distance (e.g. "5km")` — filters docs within radius; uses BKD tree to prune.
- **`_geo_distance` sort**: sorts results by distance from a point; returns `sort` values in meters/km; this demo sorts by `_geo_distance` when `sortBy=distance`.
- **`geohash_grid` / `geo_distance` aggregations**: bucket docs by grid cell or distance ring (e.g. "how many restaurants within 1km/5km/10km").
- Distance units: `m`, `km`, `mi` — this demo converts `radiusMeters / 1000` to `km` for the query.
- This demo: `location` is `geo_point` stored as `[lon, lat]`; queries use `geoDistance` filter + `_geoDistance` sort for "nearest first".

## Relevance & Scoring

- **BM25** (default since ES 5): `score = IDF * (TF * (k1+1)) / (TF + k1*(1 - b + b * |doc|/avgLen))`
  - `k1` (1.2 default) — term frequency saturation; higher = slower saturation (more weight to repeated terms).
  - `b` (0.75 default) — length normalization; 0 = no penalty for long docs, 1 = full penalty.
  - `IDF` — rare terms score higher than common ones.
- **Field boosting**: `name^3` means a match in `name` scores 3x vs base; `description^2` scores 2x.
  - This demo: `multi_match` on `name^3, description^2, category, address`.
- **`function_score` for business signals**:
  - `gauss` decay on `location` (closer = higher score) — e.g. `scale: 2km, decay: 0.5`.
  - `field_value_factor` on `avgRating` / `numRatings` (popular = higher score).
  - Combine with `boost_mode: multiply` or `sum` to blend text relevance with proximity/popularity.

## Autocomplete

| Approach | How it works | Pros | Cons |
|---|---|---|---|
| **edge_ngram** | Analyzer emits prefixes at index time (`s`, `su`, `sus`, `sush`, `sushi`) | Simple, typo-tolerant with fuzzy, works with normal queries | Larger index, not instant; prefix-only |
| **completion suggester** | FST in memory, `completion` type | Blazing fast, sorted by weight | Exact prefix only, no typo tolerance, separate field |
| **search_as_you_type** | Shingle + edge ngram built-in, 3 subfields | Best relevance for as-you-type, phrase aware | Bigger mapping, ES 7.3+ only |

- **This demo uses `edge_ngram`**: custom `edge_ngram_analyzer` (standard tokenizer + lowercase + edge_ngram 2-15) on `name.ngram` subfield; `/api/suggest` queries `name.ngram` prefix + `multi_match` fallback.
- Fallback: if ES is down, `/api/suggest` falls back to PG `LIKE`-style in-memory filtering — still works, just slower.

## ES vs Postgres — When to Pick Which

| Dimension | Postgres (PostGIS + tsvector) | Elasticsearch |
|---|---|---|
| Text search | GIN + ts_rank, no BM25 tuning | Inverted index + BM25 + boosting + fuzzy |
| Geo | GiST + ST_DWithin, single node | BKD tree + geo_distance, distributed |
| Autocomplete | LIKE / trigram, slow at scale | edge_ngram / completion, sub-ms |
| Aggregations | GROUP BY, fast for small data | Distributed aggs, histogram/geohash |
| Consistency | Strong (ACID) | Eventual (refresh 1s) |
| Ops cost | One DB | Extra cluster + sync |
| Best for | Source of truth, transactions, <100K docs | Search-heavy, ranking, geo, scale |

- **Rule of thumb**: stay on PG if search is simple and data < ~100K rows; add ES when you need ranked text + geo + autocomplete + scale.
- **Hybrid is common**: PG for transactions and source of truth, ES as derived search index — exactly this demo's architecture.

## Dual-Write & Sync

- **Problem**: PG is source of truth, ES is derived index — they must stay consistent.
- **Naive dual-write** (write PG then ES in app code) — risks inconsistency on partial failure; no atomicity.
- **Transactional outbox**: write business row + outbox event in one PG transaction; async relay publishes to queue — atomic.
- **CDC / Debezium**: tails PG WAL (logical replication slot), emits change events without app changes — lowest coupling.
- **Kafka as backbone**: Debezium -> Kafka topic -> ES sink connector -> bulk index; replayable, ordered per key.
- **Reindex on startup** (this demo): `DataInitializer` seeds PG then calls `reindexAll()` to bulk-index into ES — simple, correct for a lab; production uses incremental CDC.
- **Idempotency**: ES `index` with deterministic `_id` (business PK) makes replays safe; use `op_type: index` not `create`.
- **Backfill**: for large tables, snapshot PG and bulk-load into ES with `_bulk` + `refresh_interval: -1` then re-enable.

## Scaling & Failure Modes

- **Scaling**:
  - More **shards** = more write parallelism + bigger index capacity; too many shards = overhead (each is a Lucene index with file handles/heap).
  - More **replicas** = more read throughput + HA; replicas copy from primary via translog.
  - Choose shard count at index creation; use **reindex** or **split** to change later; prefer fewer, larger shards.
- **Failure modes**:
  - **Split-brain**: two masters in network partition; ES 7+ requires quorum via cluster bootstrapping / voting config to avoid.
  - **Quorum loss**: if fewer than quorum masters alive, cluster goes red (no writes); reads may still serve from available shards.
  - **Replication lag**: replica slightly behind primary; reads may be stale by ~1s (refresh interval); use `?refresh=wait_for` if needed.
  - **Recovery**: snapshot/restore to S3/GCS (`_snapshot` API); translog replay for recent writes; replicas re-sync from primary on restart.
  - **Backpressure**: bulk queue full -> `429 Too Many Requests`; client must retry with exponential backoff; tune `thread_pool.bulk.queue_size`.
  - **Disk pressure**: flood-stage watermark blocks writes when disk > 95% — add disk or delete old indices.

## Mapping Example (this project)

Actual mapping from `src/main/java/com/example/esdemo/config/ElasticsearchConfig.java`:

```json
{
  "settings": {
    "analysis": {
      "analyzer": {
        "edge_ngram_analyzer": {
          "tokenizer": "standard",
          "filter": ["lowercase", "edge_ngram_filter"]
        }
      },
      "filter": {
        "edge_ngram_filter": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 15
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name":         { "type": "text", "analyzer": "standard", "boost": 3.0,
                        "fields": { "ngram": { "type": "text", "analyzer": "edge_ngram_analyzer" } } },
      "description":  { "type": "text", "analyzer": "english" },
      "category":     { "type": "keyword" },
      "address":      { "type": "text", "analyzer": "standard" },
      "location":     { "type": "geo_point" },
      "locationNames":{ "type": "keyword" },
      "avgRating":    { "type": "double" },
      "numRatings":   { "type": "integer" },
      "priceRange":   { "type": "keyword" },
      "suggest":      { "type": "completion" }
    }
  }
}
```

## Query DSL Example (text + geo + sort)

Typical combined search — `bool` with `must` (scored) + `filter` (exact, no scoring) + `_geo_distance` sort:

```json
{
  "query": {
    "bool": {
      "must": [
        { "multi_match": { "query": "sushi", "fields": ["name^3", "description^2", "category", "address"] } }
      ],
      "filter": [
        { "term": { "category": "restaurant" } },
        { "geo_distance": { "distance": "5km", "location": { "lat": 37.7749, "lon": -122.4194 } } }
      ]
    }
  },
  "sort": [
    { "_geo_distance": { "location": { "lat": 37.7749, "lon": -122.4194 }, "order": "asc", "unit": "km" } }
  ],
  "from": 0, "size": 20
}
```

- `must` contributes to `_score` (BM25); `filter` is a yes/no prune (cached, no scoring).
- Swap sort to `{ "avgRating": "desc" }` for rating-ranked results (default in this demo).

## Interview Script

**2-minute ES pitch** (when asked "what is Elasticsearch?"):

> "Elasticsearch is a distributed search and analytics engine built on Lucene. Postgres does `LIKE '%sushi%'` as a full table scan and its `tsvector` ranking is basic. ES stores an inverted index — term to doc list — so text lookup is O(1), scores with BM25, and supports analyzers for tokenization and stemming. Geo points go into a BKD tree for fast radius queries. Writes are near-real-time — bulk index to a buffer, refresh every second into a new segment, with a translog WAL for durability and background merges to keep segments compact. Reads scatter to shards, each scores locally, and the coordinator merges. You'd pick ES when you need ranked text plus geo plus autocomplete at scale; you'd stay on Postgres when search is simple or strong consistency matters. The trade-off is operational cost and eventual consistency, so you sync via an outbox or CDC pipeline like Debezium into Kafka."

**"How would you design Yelp search with ES?"** (60-second answer):

> "Index each business as a document with `name` as `text` boosted 3x, `description` with the `english` analyzer, `category` as `keyword`, and `location` as `geo_point`. Add an `edge_ngram` subfield on `name` for autocomplete. At query time use a `bool` query — `must` with `multi_match` on name and description, `filter` with `term` on category and `geo_distance` on location, and sort by `_geo_distance` or by a `function_score` that blends BM25 with a gauss decay on distance and a factor on rating. Scale with shards for write volume and replicas for read fan-out; sync from Postgres via an outbox or Debezium CDC into Kafka so the ES index is a derived view. Monitor shard health, handle replication lag with a 1-second refresh, and snapshot to S3 for recovery."

## Quick Recall Checklist

- Inverted index = term -> postings; BKD tree = geo pruning; BM25 = TF*IDF with k1/b + field boost.
- Refresh (1s, NRT) != Flush (fsync, durable); segment is visible, translog is recoverable.
- `text` for search, `keyword` for filter/agg, `geo_point` for distance, `completion` for FST suggest.
- Autocomplete: edge_ngram (this demo) vs completion (FST, exact) vs search_as_you_type (shingle, phrase-aware).
- Dual-write: outbox or CDC (Debezium -> Kafka -> ES sink); never rely on app dual-write alone.
- Scale: shards for writes/capacity, replicas for reads/HA; pick shard count at creation, reindex to change.
- Failure: quorum for master, `429` on bulk pressure, snapshot/restore + translog replay for recovery.
