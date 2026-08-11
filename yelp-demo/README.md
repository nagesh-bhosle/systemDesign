# 🍴 Yelp Demo — Business Search & Review System

A working implementation of a Yelp-like application based on the [Yelp system design doc](./Yelp.md). Built with **Spring Boot + PostgreSQL/PostGIS** to demonstrate real-world system design concepts.

---

## 🚀 Quick Start (One Command)

```bash
cd yelp-demo
./start.sh
```

This will:
1. Start PostgreSQL + PostGIS in Docker
2. Build the Spring Boot application
3. Start the app on `http://localhost:8081`
4. **Preload 20 businesses, 5 users, 60+ reviews, and 4 location areas**

Open **http://localhost:8081** in your browser.

### Stop

```bash
./stop.sh
```

---

## 📋 Prerequisites

- **Docker** (running locally)
- **Java 21+** (install via `brew install openjdk@21`)
- **Maven** (wrapper included — no need to install)

---

## 🏗️ What's Implemented

This project implements every concept from the Yelp system design document:

### Functional Requirements
| Requirement | Implementation |
|---|---|
| Search businesses by name, location, category | `GET /api/businesses` with PostGIS + full-text search |
| View business details & reviews | `GET /api/businesses/{id}` returns business + paginated reviews |
| Leave a review (1-5 stars + optional text) | `POST /api/businesses/{id}/reviews` |

### Non-Functional Requirements
| Requirement | Implementation |
|---|---|
| Low latency search (<500ms) | PostGIS GiST spatial index + PostgreSQL GIN full-text index |
| High availability, eventual consistency | Read-heavy architecture with synchronous writes |
| Scalable to 100M users, 10M businesses | Geospatial indexing, precomputed avg ratings |

### Deep Dives from the Design Doc

#### 1. Precomputed Average Rating
- `avgRating` and `numRatings` are stored as columns on the `Business` entity
- Updated **synchronously** on each new review (no message queue needed — write volume is ~1/sec)
- Search results return the precomputed value — no aggregation on the fly

#### 2. One Review Per User Per Business
- Enforced via a **unique database constraint** (`uk_user_business` on `userId, businessId`)
- Application-level check in `ReviewService` for a clean error message
- Constraint is as close to the persistence layer as possible

#### 3. Efficient Geospatial Search (PostGIS)
- **PostGIS extension** enables `ST_DWithin` for radius-based search
- **GiST spatial index** on a `geography(Point, 4326)` column for fast lookups
- **Haversine formula** used for second-pass distance calculation and display
- Search pipeline: distance filter → text filter → category filter → sort

#### 4. Full-Text Search
- PostgreSQL `tsvector` column (`search_vector`) on businesses
- **GIN index** for fast `@@ plainto_tsquery` lookups
- Searches across name, description, and category

#### 5. Search by Named Location
- `LocationArea` entity maps location names (e.g. "san_francisco") to bounding boxes
- `Business.locationNames` stores pre-computed area identifiers (e.g. "san_francisco,mission_district,bay_area")
- Avoids polygon math on every request — just a simple string filter

---

## 📊 Data Model

```
users
  ├── id (PK)
  ├── username (unique)
  ├── displayName
  └── avatarUrl

businesses
  ├── id (PK)
  ├── name
  ├── description
  ├── address
  ├── latitude, longitude
  ├── category
  ├── avgRating (precomputed)
  ├── numRatings (precomputed)
  ├── priceRange
  ├── imageUrl
  ├── locationNames (comma-separated pre-computed areas)
  ├── geom (PostGIS geography Point — spatial index)
  └── search_vector (PostgreSQL tsvector — full-text index)

reviews
  ├── id (PK)
  ├── userId
  ├── businessId (FK)
  ├── rating (1-5)
  ├── text (optional)
  ├── userDisplayName (denormalized)
  └── UNIQUE(userId, businessId) — one review per user per business

locations
  ├── id (PK)
  ├── name (unique, e.g. "san_francisco")
  ├── displayName (e.g. "San Francisco")
  ├── type (city/neighborhood/region)
  └── minLat, minLon, maxLat, maxLon (bounding box)
```

---

## 🔌 API Reference

### Search Businesses
```
GET /api/businesses?query=pizza&lat=37.75&lon=-122.41&radius=5000&category=restaurant&sortBy=rating&page=0&size=20
```
Two search modes:
- **Geo search**: provide `lat` + `lon` (uses PostGIS `ST_DWithin`)
- **Named location**: provide `location=san_francisco` (uses pre-computed `locationNames`)

Parameters:
| Param | Description | Default |
|---|---|---|
| `query` | Full-text search term | null |
| `lat`, `lon` | Search center coordinates | null |
| `radius` | Search radius in meters | 5000 |
| `location` | Named location (e.g. "manhattan") | null |
| `category` | Category filter | null |
| `sortBy` | "rating" or "distance" | "rating" |
| `page`, `size` | Pagination | 0, 20 |

### View Business + Reviews
```
GET /api/businesses/{businessId}
```
Returns `{ business: BusinessDto, reviews: ReviewDto[] }`

### Get Reviews (Paginated)
```
GET /api/businesses/{businessId}/reviews?page=0&size=20
```

### Create Review
```
POST /api/businesses/{businessId}/reviews
Content-Type: application/json

{
  "userId": 1,
  "rating": 5,
  "text": "Amazing food!"
}
```
- Returns `201 Created` on success
- Returns `409 Conflict` if user already reviewed this business
- Returns `400 Bad Request` if rating is invalid or user/business doesn't exist
- **Synchronously updates** the business's `avgRating` and `numRatings`

### Get All Categories
```
GET /api/categories
```

---

## 🗂️ Project Structure

```
yelp-demo/
├── start.sh                    # One-command startup
├── stop.sh                     # Stop everything
├── docker-compose.yml          # PostgreSQL + PostGIS
├── pom.xml                     # Maven config
├── mvnw / mvnw.cmd             # Maven wrapper
├── Yelp.md                     # Original design doc
└── src/
    └── main/
        ├── java/com/example/yelp/
        │   ├── YelpApplication.java
        │   ├── entity/
        │   │   ├── Business.java       # Precomputed avgRating, locationNames
        │   │   ├── Review.java         # Unique constraint on (userId, businessId)
        │   │   ├── User.java
        │   │   └── LocationArea.java   # Named location → bounding box
        │   ├── repository/
        │   │   ├── BusinessRepository.java   # PostGIS + full-text queries
        │   │   ├── ReviewRepository.java
        │   │   ├── UserRepository.java
        │   │   └── LocationAreaRepository.java
        │   ├── service/
        │   │   ├── BusinessService.java  # Search pipeline + Haversine
        │   │   └── ReviewService.java    # One-review constraint + sync avgRating
        │   ├── controller/
        │   │   ├── BusinessController.java
        │   │   └── ReviewController.java
        │   ├── dto/
        │   │   ├── BusinessDto.java
        │   │   ├── ReviewDto.java
        │   │   ├── CreateReviewRequest.java
        │   │   └── SearchResult.java
        │   └── config/
        │       └── DataInitializer.java  # PostGIS setup + data seeding
        └── resources/
            ├── application.yml
            └── static/
                └── index.html            # Yelp-like UI
```

---

## 🧪 Try These Scenarios

1. **Full-text search**: Type "pizza" in the search box, set location to "manhattan"
2. **Geospatial search**: Click "📍 Near Mission (geo)" — results show distance in meters
3. **Category filter**: Select "cafe" from the dropdown to filter
4. **Sort by distance**: After a geo search, change sort to "Distance"
5. **Write a review**: Click any business → write a review → see avg rating update
6. **One review constraint**: Try reviewing the same business twice as the same user → 409 error
7. **Named location search**: Click "Mission District" to see pre-computed location filtering

---

## 🐛 Troubleshooting

| Issue | Solution |
|---|---|
| `./start.sh` fails | Ensure Docker is running: `docker info` |
| Port 8081 in use | `./stop.sh` then retry, or change port in `application.yml` |
| Port 5433 in use | Another PostgreSQL is running. Stop it or change port in `docker-compose.yml` |
| Database not ready | The script waits 30s. If your machine is slow, increase the timeout |
| Build fails | Ensure Java 17+: `java -version` |

---

## 📚 Design Decisions Explained

### Why PostgreSQL + PostGIS instead of Elasticsearch?
The design doc notes that staff-level candidates should recognize when simplicity wins. PostgreSQL with PostGIS handles both geospatial and full-text search in a single database. For 10M businesses, this is sufficient. Elasticsearch would add operational complexity and consistency challenges.

### Why synchronous avgRating updates?
The read:write ratio is ~1000:1. With 100M users, that's ~100K writes/day or ~1 write/second. Modern databases handle thousands of writes/second. A message queue would add complexity with no benefit.

### Why pre-computed locationNames?
Instead of doing polygon-in-bounding-box math on every search request, we pre-compute which areas each business belongs to at creation time. Search then becomes a simple string match — much faster.

### Why a unique constraint instead of application logic?
Database constraints are bulletproof — they work even if application logic has bugs. The design doc says: "enforce that constraint as close to the persistence layer as possible."