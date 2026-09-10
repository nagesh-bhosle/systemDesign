# Elastic Search Lab — Postgres vs Elasticsearch

> Side-by-side benchmark of Postgres (PostGIS + tsvector) vs Elasticsearch (inverted index + BM25 + geo BKD tree) on ~2,000 restaurants across SF, Manhattan, and Bangalore.

## Stack

| Layer | Tech | Version |
|---|---|---|
| App | Spring Boot | 3.3.2 |
| Language | Java | 21 |
| DB (source of truth) | Postgres + PostGIS | 16-3.4 |
| Search engine | Elasticsearch | 8.14.0 |
| Client | Vanilla JS | — |
| Build | Maven | 3.x |
| ES Java client | elasticsearch-java | 8.14.0 |
| Env | Docker Compose | — |

## Architecture

```
                    ┌─────────────────────┐
                    │   Browser (vanilla  │
                    │   JS — index.html)  │
                    └────────┬────────────┘
                             │ HTTP :8086
                             ▼
                    ┌─────────────────────┐
                    │   Spring Boot       │
                    │   (port 8086)       │
                    │  ┌───────────────┐  │
                    │  │ BenchmarkService│  │
                    │  │ ES vs PG timing │  │
                    │  └──────┬────────┘  │
                    │         │            │
                    │  ┌──────┴────────┐  │
                    │  │ SearchService  │  │
                    │  │ PG + ES impls  │  │
                    │  └──────┬────────┘  │
                    └─────────┼───────────┘
                              │  ┌─────────────────┐
                 ┌────────────┼─▶│ Postgres :5434   │
                 │            │  │ PostGIS + GiST   │
                 │            │  │ tsvector + GIN   │
                 │            │  │ Source of truth  │
                 │            │  └─────────────────┘
                 │            │  ┌─────────────────┐
                 │            └─▶│ Elasticsearch    │
                 │               │ :9201            │
                 │               │ Inverted index   │
                 │               │ BM25 + BKD geo   │
                 │               │ Derived index    │
                 └───────────────┘  (reindex on startup)
```

- **Postgres is source of truth** — all writes go there; `DataInitializer` creates `geom` (geography), `search_vector` (tsvector), GiST/GIN indexes, and seeds ~2,000 businesses + 2-5 reviews each across three city clusters.
- **Elasticsearch is derived** — `ElasticsearchConfig` creates `businesses` index with `edge_ngram` analyzer + `geo_point`; `DataInitializer` calls `reindexAll()` to bulk-index every PG row into ES on startup.
- **Two search paths**: `PostgresSearchService` (PostGIS `ST_DWithin` + `ts_rank`) and `ElasticsearchSearchService` (multi_match + geo_distance); `BenchmarkService` runs both and returns wall-clock `tookMs` for comparison.
- See [INTERVIEW_NOTES.md](INTERVIEW_NOTES.md) for mapping JSON and Query DSL examples.

## How to Run

```bash
# from this directory
./start.sh          # Docker up (PG + ES) -> wait -> mvn compile -> spring-boot:run
# open http://localhost:8086

./stop.sh           # kills app on :8086 + docker compose down
```

What `start.sh` does:

1. `docker compose up -d` for `es-demo-postgres` + `es-demo-elasticsearch`.
2. Polls PG with `pg_isready` (up to 30s) and ES with `/_cluster/health` (up to 60s).
3. `./mvnw clean compile` then `./mvnw spring-boot:run` on `$SERVER_PORT` (default `8086`).

**Via launcher** (all 7 demos in one dashboard):

```bash
cd ../launcher
./start.sh          # open http://localhost:8790 -> "Elastic Search Lab" card -> Start
```

The launcher passes `SERVER_PORT` through, polls the port, and shows the live URL. Port overrides persist in `launcher/config.json` and survive restarts.

## API

| Method | Path | Description |
|---|---|---|
| GET | `/api/businesses?q=&lat=&lon=&radius=&category=&location=&sortBy=&page=&size=` | Search (geo if `lat`/`lon` present, else by `location` name) |
| GET | `/api/businesses/{id}` | Business detail + reviews |
| GET | `/api/categories` | All distinct categories |
| GET | `/api/suggest?q=` | Autocomplete (edge_ngram on `name.ngram`, 8 results) |
| GET | `/api/benchmark/text?q=&category=&page=&size=` | Benchmark: text search PG vs ES |
| GET | `/api/benchmark/geo?lat=&lon=&radius=&q=&category=&sortBy=&page=&size=` | Benchmark: geo search PG vs ES |
| GET | `/api/benchmark/combined?q=&lat=&lon=&radius=&category=&sortBy=&page=&size=` | Benchmark: combined (delegates to geo or text) |
| GET | `/api/capabilities/aggregations?lat=&lon=&radius=` | ES aggs: `by_category` terms + `avg_rating_histogram` |
| GET | `/api/capabilities/fuzzy?q=&page=&size=` | ES fuzzy search (`fuzziness: AUTO` on name/description) |
| GET | `/api/stats` | Counts: `postgresCount`, `elasticsearchCount`, `esHealth`, `indexExists` |
| POST | `/api/businesses/{businessId}/reviews` | Create review body `{ rating, text, userId }` |

All endpoints allow `*` CORS. Default `radius` is `5000m` (search) / `1000m` (benchmark geo). Sort with `sortBy=distance` for geo-distance order, otherwise `rating`. Pages default to `page=0, size=20`.

## Benchmark Interpretation

- **`tookMs`** (in `BenchmarkResult`) is **wall-clock time** measured in `BenchmarkService` via `System.nanoTime()` around each engine call — includes network + serialization — with a warm-up call first.
- **ES `took`** (inside ES `_search` response, not surfaced separately here) is **engine-internal time** only — Lucene execution without network.
- This lab reports `tookMs` for both engines so the comparison is apples-to-apples (same JVM, same network hop to localhost).
- **Why ES wins on text+geo**: inverted index gives O(1) term lookup vs PG `LIKE`/`ts_rank` scan; BKD tree prunes geo candidates without scanning all rows; BM25 + boosting ranks without extra sorting.
- **When PG is fine**: dataset < ~100K rows, simple filters, no fuzzy/typo tolerance, no distance-ranked text search, or when strong consistency matters more than search speed.

## Demo Walkthrough (5 steps)

1. **Search** — enter "sushi" near SF (`37.7749, -122.4194`), filter by `restaurant`, toggle sort `rating` vs `distance` and watch geo-distance sorting live.
2. **Benchmark** — hit `/api/benchmark/combined?q=sushi&lat=37.7749&lon=-122.4194&radius=5000` and compare `postgres.tookMs` vs `elasticsearch.tookMs` side by side.
3. **Capabilities** — try `/api/capabilities/fuzzy?q=sushii` (typo) and `/api/capabilities/aggregations?lat=37.7749&lon=-122.4194&radius=5000` (category + rating histogram).
4. **Interview notes** — open [INTERVIEW_NOTES.md](INTERVIEW_NOTES.md) for the 2-minute ES pitch + "how would you design Yelp search?" answer and mapping/Query DSL snippets.
5. **Tweak mapping** — edit `ElasticsearchConfig.java` (e.g. change `minGram`/`maxGram`, add a `search_as_you_type` field), delete the index, restart, and re-run a suggest/benchmark query.

## Where to Tweak

| What | File |
|---|---|
| ES mapping & analyzer | `src/main/java/com/example/esdemo/config/ElasticsearchConfig.java` |
| Seed data (cities, counts, jitter, reviews) | `src/main/java/com/example/esdemo/config/DataInitializer.java` |
| Benchmark timing & warm-up | `src/main/java/com/example/esdemo/service/BenchmarkService.java` |
| PG search (PostGIS/tsvector) | `src/main/java/com/example/esdemo/service/PostgresSearchService.java` |
| ES search (multi_match/geo/fuzzy/aggs) | `src/main/java/com/example/esdemo/service/ElasticsearchSearchService.java` |
| UI | `src/main/resources/static/index.html` |

> Do not overwrite `src/main/resources/static/index.html` when regenerating docs — it is the lab UI.

## Ports

| Service | Port | URL / DSN |
|---|---|---|
| Spring Boot app | `8086` | http://localhost:8086 |
| Postgres (PostGIS) | `5434` | `jdbc:postgresql://localhost:5434/esdemo` (user `esdemo` / `esdemo123`) |
| Elasticsearch | `9201` | http://localhost:9201 |

Override the app port with `SERVER_PORT=8087 ./start.sh` or via the launcher's port field. PG and ES ports are fixed in `docker-compose.yml`.

## Links

- Interview notes: [INTERVIEW_NOTES.md](INTERVIEW_NOTES.md)
- Launcher: [../launcher/README.md](../launcher/README.md)
- Elasticsearch docs: https://www.elastic.co/guide/en/elasticsearch/reference/8.14/index.html

## Requirements

- Java 21, Docker, Maven (wrapper included as `./mvnw`).
- ES heap: `ES_JAVA_OPTS=-Xms256m -Xmx256m` (tuned for local dev in `docker-compose.yml`).
