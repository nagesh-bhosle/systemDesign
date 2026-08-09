# Dropbox-like File Storage — Spring Boot + Azure Blob Storage

A Spring Boot application that implements a **Dropbox-like file storage system** with chunked uploads, fingerprinting, deduplication, resumable uploads, file sharing, and real-time sync — all backed by Azure Blob Storage (Azurite for local dev) and H2 (in-memory DB for metadata).

Based on the [Dropbox system design breakdown](https://www.hellointerview.com/learn/system-design/problem-breakdowns/dropbox).

---

## Architecture

```
                              ┌─────────────────────────────────────────────────────┐
                              │                   Spring Boot API                     │
                              │                                                       │
  ┌─────────┐   HTTP/SSE     │  ┌─────────────┐  ┌──────────────┐  ┌───────────┐  │
  │  Client  │──────────────►│  │DropboxCtrl  │─►│DropboxFileSvc│─►│BlobStorage│  │
  │ (script) │               │  │ShareCtrl    │  │ (fingerprint,│  │  (Azure)  │  │
  │ (browser)│               │  │SyncCtrl     │  │  dedup, chunk)│  └───────────┘  │
  └─────────┘               │  └─────────────┘  └──────┬───────┘                  │
                              │                          │                          │
                              │                    ┌─────▼─────┐                   │
                              │                    │SyncService│ (SSE push)       │
                              │                    └─────┬─────┘                   │
                              └──────────────────────────┼─────────────────────────┘
                                                         │
                              ┌──────────────────────────▼─────────────────────────┐
                              │                    H2 Database                      │
                              │  ┌────────────┐ ┌───────────┐ ┌──────────────┐     │
                              │  │FileMetadata│ │ChunkStatus│ │  FileShare   │     │
                              │  │  (files)   │ │ (chunks)  │ │  (ACL table) │     │
                              │  └────────────┘ └───────────┘ └──────────────┘     │
                              └────────────────────────────────────────────────────┘
```

### Four Functional Requirements (from the article)

| # | Requirement | Implementation |
|---|-------------|----------------|
| 1 | **Upload a file** from any device | Simple upload (small files) + chunked upload (large files) with fingerprinting |
| 2 | **Download a file** from any device | Streamed download with access control (owner or shared) |
| 3 | **Share a file** with other users | Separate `FileShare` table (ACL) — owner grants access to specific users |
| 4 | **Sync files across devices** | SSE (real-time push) + polling fallback (`GET /sync/changes?since=`) |

### Key Design Decisions

1. **Fingerprinting (SHA-256)** — Every file gets a SHA-256 fingerprint computed client-side. The server uses this for:
   - **Deduplication**: If a file with the same fingerprint already exists and is `UPLOADED`, skip the upload entirely.
   - **Resumable uploads**: If a file with the same fingerprint is `UPLOADING`, resume from where it left off.

2. **Chunked upload with DB tracking** — Each chunk's status (`NOT_UPLOADED` / `UPLOADED`) is tracked in the `ChunkStatus` table. The client can query which chunks are already uploaded and only send the missing ones.

3. **Server-side chunk verification** — The client sends a SHA-256 hash of each chunk. The server recomputes the hash and verifies it matches before staging the block. This catches data corruption in transit.

4. **Block Blob API** — Azure Blob Storage's Block Blob API is used for chunked uploads:
   - `stageBlock` — upload an uncommitted block
   - `commitBlockList` — assemble all blocks into the final blob (ordered by block ID)

5. **Soft delete** — Files are marked as `DELETED` in the metadata table, but the blob is kept in storage for recovery.

6. **Hybrid sync** — SSE for real-time push (primary) + polling as a safety net (fallback).

---

## Quick Start

### 1. Start Azurite (Blob Storage emulator)

```bash
cd dropbox-demo
docker compose up -d
```

### 2. Build & Run the Spring Boot app

```bash
./mvnw spring-boot:run
```

The app starts on `http://localhost:8080`.
H2 console available at `http://localhost:8080/h2-console` (JDBC URL: `jdbc:h2:mem:dropbox`, user: `sa`, no password).

### 3. Create a user

```bash
node scripts/dropbox-client.mjs user --email alice@example.com --name Alice
# Output: User ID: <uuid>  ← save this!
```

### 4. Upload a file

```bash
# Small file (simple upload)
curl -X POST http://localhost:8080/api/dropbox/files/upload \
  -H "X-User-Id: <uuid>" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @small-file.txt

# Large file (chunked upload with fingerprinting)
node scripts/dropbox-client.mjs upload ./big-video.mp4 --user-id <uuid>
```

### 5. List, download, share, sync

```bash
# List your files
node scripts/dropbox-client.mjs list --user-id <uuid>

# Download a file
node scripts/dropbox-client.mjs download <fileId> --user-id <uuid>

# Share a file
node scripts/dropbox-client.mjs share <fileId> <otherUserId> --user-id <uuid>

# Listen for real-time sync events (SSE)
node scripts/dropbox-client.mjs sync --user-id <uuid>

# Poll for changes (fallback)
node scripts/dropbox-client.mjs changes --since 2024-01-01T00:00:00Z --user-id <uuid>
```

---

## API Endpoints

### User Management

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/dropbox/users` | Create or find a user by email |

### File Operations

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/dropbox/files/upload` | Simple upload (small files, raw body) |
| `POST` | `/api/dropbox/files/chunk/init` | Initialize chunked upload (with fingerprint) |
| `POST` | `/api/dropbox/files/chunk/upload` | Upload a single chunk (with hash verification) |
| `POST` | `/api/dropbox/files/chunk/complete` | Complete chunked upload (assemble blob) |
| `GET` | `/api/dropbox/files` | List files owned by the user |
| `GET` | `/api/dropbox/files/shared` | List files shared with the user |
| `GET` | `/api/dropbox/files/{fileId}` | Get file metadata (with access check) |
| `GET` | `/api/dropbox/files/{fileId}/download` | Download a file (streamed) |
| `DELETE` | `/api/dropbox/files/{fileId}` | Soft-delete a file |

### Sharing

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/dropbox/files/{fileId}/share` | Share a file with another user |
| `GET` | `/api/dropbox/files/{fileId}/shares` | List all shares for a file |

### Sync

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/dropbox/sync/events` | SSE endpoint for real-time change notifications |
| `GET` | `/api/dropbox/sync/changes` | Polling fallback — get changes since timestamp |

### Legacy Endpoints (original blob upload demo)

The original simple upload endpoints are still available at `/api/files/*` (see `FileUploadController.java`).

---

## Chunked Upload Flow (Detailed)

```
┌─────────┐                    ┌─────────┐                  ┌──────────┐  ┌─────┐
│  Client  │                    │  Server  │                  │  Azure   │  │ H2  │
│ (script) │                    │ (Spring) │                  │  Blob    │  │ DB  │
└────┬────┘                    └────┬────┘                  └────┬─────┘  └──┬──┘
     │                              │                            │           │
     │ 1. Compute SHA-256           │                            │           │
     │    of entire file            │                            │           │
     │                              │                            │           │
     │ 2. POST /files/chunk/init   │                            │           │
     │    {fingerprint, name, size}│                            │           │
     │─────────────────────────────>│                            │           │
     │                              │  Check dedup (fingerprint)  │           │
     │                              │───────────────────────────────────────>│
     │                              │  Create FileMetadata       │           │
     │                              │───────────────────────────────────────>│
     │                              │  Create ChunkStatus rows   │           │
     │                              │───────────────────────────────────────>│
     │      {fileId, totalChunks,  │                            │           │
     │       uploadedChunks: []}    │                            │           │
     │<─────────────────────────────│                            │           │
     │                              │                            │           │
     │ 3. For each chunk:           │                            │           │
     │    Compute chunk SHA-256     │                            │           │
     │    POST /files/chunk/upload  │                            │           │
     │    ?fileId=&partNumber=&     │                            │           │
     │    chunkHash=                │                            │           │
     │─────────────────────────────>│                            │           │
     │                              │  Verify hash (server-side) │           │
     │                              │  stageBlock(blockId)       │           │
     │                              │───────────────────────────>│           │
     │                              │  Update ChunkStatus        │           │
     │                              │───────────────────────────────────────>│
     │      200 OK {status:UPLOADED}│                            │           │
     │<─────────────────────────────│                            │           │
     │         ...                  │         ...                │           │
     │                              │                            │           │
     │ 4. POST /files/chunk/complete│                            │           │
     │─────────────────────────────>│                            │           │
     │                              │  commitBlockList(all IDs)  │           │
     │                              │───────────────────────────>│           │
     │                              │  Update FileMetadata       │           │
     │                              │  status → UPLOADED         │           │
     │                              │───────────────────────────────────────>│
     │                              │  Push SSE notification     │           │
     │      200 OK {metadata}       │                            │           │
     │<─────────────────────────────│                            │           │
```

---

## Data Model

### `file_metadata` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `name` | VARCHAR | Original file name |
| `size` | BIGINT | File size in bytes |
| `mime_type` | VARCHAR | MIME type |
| `blob_name` | VARCHAR | Azure Blob Storage blob name |
| `fingerprint` | VARCHAR (unique) | SHA-256 of the entire file |
| `status` | VARCHAR | `UPLOADING`, `UPLOADED`, or `DELETED` |
| `uploaded_by` | UUID | Owner's user ID |
| `created_at` | TIMESTAMP | Creation time |
| `updated_at` | TIMESTAMP | Last update time |

### `chunk_status` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `file_id` | UUID | FK to `file_metadata` |
| `part_number` | INT | 1-based chunk index |
| `block_id` | VARCHAR | Base64-encoded block ID for Azure |
| `status` | VARCHAR | `NOT_UPLOADED` or `UPLOADED` |
| `chunk_hash` | VARCHAR | SHA-256 of this chunk |
| `chunk_size` | BIGINT | Size of this chunk in bytes |
| `uploaded_at` | TIMESTAMP | When this chunk was uploaded |

### `file_shares` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `file_id` | UUID | FK to `file_metadata` |
| `shared_with_user_id` | UUID | The user who received the share |
| `shared_by_user_id` | UUID | The owner who shared the file |
| `shared_at` | TIMESTAMP | When the share was created |

### `users` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `email` | VARCHAR (unique) | User email |
| `name` | VARCHAR | User display name |
| `created_at` | TIMESTAMP | Account creation time |

---

## Project Structure

```
dropbox-demo/
├── docker-compose.yml              # Azurite (Azure Storage emulator)
├── pom.xml                         # Maven dependencies
├── README.md                       # This file
├── scripts/
│   ├── chunked-upload.mjs          # Original chunked upload script
│   └── dropbox-client.mjs          # Full Dropbox client (fingerprint, dedup, sync)
└── src/main/
    ├── java/com/example/blobupload/
    │   ├── BlobUploadApplication.java           # Main entry point
    │   ├── config/
    │   │   ├── AzureBlobConfig.java              # BlobServiceClient bean
    │   │   └── TomcatConfig.java                 # Tomcat tuning for large uploads
    │   ├── controller/
    │   │   ├── DropboxController.java            # Dropbox-like REST API
    │   │   └── FileUploadController.java         # Legacy upload endpoints
    │   ├── entity/
    │   │   ├── User.java                          # JPA entity — users table
    │   │   ├── FileMetadata.java                  # JPA entity — file_metadata table
    │   │   ├── ChunkStatus.java                   # JPA entity — chunk_status table
    │   │   └── FileShare.java                     # JPA entity — file_shares table
    │   ├── repository/
    │   │   ├── UserRepository.java
    │   │   ├── FileMetadataRepository.java
    │   │   ├── ChunkStatusRepository.java
    │   │   └── FileShareRepository.java
    │   └── service/
    │       ├── DropboxFileService.java           # Core Dropbox logic
    │       ├── SyncService.java                   # SSE for real-time sync
    │       └── BlobStorageService.java            # Legacy blob operations
    └── resources/
        └── application.yml                       # Configuration
```

---

## Configuration

### `application.yml` key settings

```yaml
# H2 Database (metadata)
spring:
  datasource:
    url: jdbc:h2:mem:dropbox;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE
  jpa:
    hibernate:
      ddl-auto: update
  h2:
    console:
      enabled: true
      path: /h2-console

# Azure Blob Storage (Azurite)
azure:
  blob:
    connection-string: "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;..."
    container-name: "uploads"
    block-size-bytes: 8388608    # 8 MB
    max-concurrency: 8

# Dropbox-specific
dropbox:
  chunk-size-bytes: 4194304      # 4 MB per chunk
```

---

## Stopping the Services

```bash
# Stop Spring Boot
Ctrl+C

# Stop Azurite
docker compose down

# Stop and remove data
docker compose down -v
```

## Switching to Real Azure Blob Storage

Update the connection string in `application.yml`:

```yaml
azure:
  blob:
    connection-string: "DefaultEndpointsProtocol=https;AccountName=YOUR_ACCOUNT;AccountKey=YOUR_KEY;BlobEndpoint=https://YOUR_ACCOUNT.blob.core.windows.net;"
```

## Switching to a Real Database (PostgreSQL)

Replace the H2 dependency in `pom.xml` with PostgreSQL driver, and update `application.yml`:

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/dropbox
    username: dropbox
    password: dropbox
    driver-class-name: org.postgresql.Driver
  jpa:
    database-platform: org.hibernate.dialect.PostgreSQLDialect
```

Everything else stays the same — the code is identical for H2 and PostgreSQL.