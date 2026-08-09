# Blob Upload Demo — Spring Boot Large File Upload to Azure Blob Storage

A Spring Boot application that demonstrates **multipart file uploads of GB-sized files** to Azure Blob Storage using **Azurite** (Azure Storage emulator) running in Docker.

## How It Works

```
┌──────────┐     multipart/form-data     ┌──────────────┐     streaming blocks     ┌──────────┐
│  Client   │ ──────────────────────────► │ Spring Boot  │ ──────────────────────► │  Azurite  │
│ (curl/UI) │                             │  REST API    │   (8MB blocks, parallel) │ (Docker)  │
└──────────┘                             └──────────────┘                          └──────────┘
                                               │
                                         File is NEVER fully
                                         loaded in memory —
                                         streamed in chunks
```

### Key Design Decisions for Large Files

1. **Streaming upload** — `MultipartFile.getInputStream()` is passed directly to the Azure SDK's `uploadWithResponse()`. The SDK reads in blocks (default 8MB), so the JVM heap stays small even for multi-GB files.

2. **Block blob strategy** — Large files are split into blocks, uploaded in parallel (`maxConcurrency=8`), and committed at the end. If a block fails, only that block is retried.

3. **Tomcat tuning** — `maxPostSize=-1` removes the default 2MB post limit. Connection timeout set to 10 minutes for slow networks.

4. **Multipart config** — `file-size-threshold=0` forces Spring to write to temp disk immediately (not buffer in memory). `max-file-size=10GB` allows very large uploads.

## Quick Start

### 1. Start Azurite (Blob Storage emulator)

```bash
cd blob-upload-demo
docker compose up -d
```

Verify it's running:
```bash
docker ps | grep azurite
```

### 2. Build & Run the Spring Boot app

```bash
cd blob-upload-demo
./mvnw spring-boot:run
```

Or if you have Maven installed:
```bash
mvn spring-boot:run
```

The app starts on `http://localhost:8080`.

### 3. Test the APIs

#### Health check
```bash
curl http://localhost:8080/api/files/health
```

#### Upload a file
```bash
# Small file
curl -X POST http://localhost:8080/api/files/upload \
  -F "file=@some-file.txt"

# Large file (GBs) — with custom blob name
curl -X POST http://localhost:8080/api/files/upload \
  -F "file=@/path/to/huge-file.iso" \
  -F "blobName=my-large-file.iso"
```

#### Upload multiple files
```bash
curl -X POST http://localhost:8080/api/files/upload-batch \
  -F "files=@file1.zip" \
  -F "files=@file2.zip"
```

#### List all uploaded blobs
```bash
curl http://localhost:8080/api/files
```

#### Get info about a specific blob
```bash
curl http://localhost:8080/api/files/my-large-file.iso
```

#### Download a blob
```bash
curl -OJ http://localhost:8080/api/files/my-large-file.iso/download
```

#### Delete a blob
```bash
curl -X DELETE http://localhost:8080/api/files/my-large-file.iso
```

### 4. Generate a large test file (optional)

```bash
# Create a 1GB test file
dd if=/dev/zero of=test-1gb.bin bs=1m count=1024

# Create a 5GB test file
dd if=/dev/zero of=test-5gb.bin bs=1m count=5120
```

Then upload it:
```bash
curl -X POST http://localhost:8080/api/files/upload \
  -F "file=@test-1gb.bin"
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/files/upload` | Upload a single file (multipart/form-data) |
| `POST` | `/api/files/upload-batch` | Upload multiple files at once |
| `GET` | `/api/files` | List all blobs in the container |
| `GET` | `/api/files/{blobName}` | Get metadata for a specific blob |
| `GET` | `/api/files/{blobName}/download` | Download a blob (streamed) |
| `DELETE` | `/api/files/{blobName}` | Delete a blob |
| `GET` | `/api/files/health` | Health check |

## Project Structure

```
blob-upload-demo/
├── docker-compose.yml          # Azurite (Azure Storage emulator)
├── pom.xml                     # Maven dependencies
├── README.md                   # This file
└── src/main/
    ├── java/com/example/blobupload/
    │   ├── BlobUploadApplication.java       # Main entry point
    │   ├── config/
    │   │   ├── AzureBlobConfig.java          # BlobServiceClient bean
    │   │   └── TomcatConfig.java             # Tomcat tuning for large uploads
    │   ├── controller/
    │   │   └── FileUploadController.java     # REST API endpoints
    │   └── service/
    │       └── BlobStorageService.java       # Core upload/download logic
    └── resources/
        └── application.yml                   # Configuration
```

## How Multipart Upload Works (Under the Hood)

1. **Client sends** a `multipart/form-data` request with the file attached.

2. **Spring's `MultipartResolver`** intercepts the request. Because `file-size-threshold=0`, it writes the file data to a temp file on disk (not memory).

3. **Controller** receives a `MultipartFile` which is backed by that temp file. Calling `file.getInputStream()` gives a stream that reads from disk.

4. **Azure SDK** `BlobClient.uploadWithResponse()` reads from that stream in blocks (8MB each by default). Each block is uploaded as a separate PUT request to Azurite. Blocks are uploaded in parallel (8 concurrent threads).

5. **After all blocks are uploaded**, the SDK sends a "Put Block List" request to commit the blob.

6. **The temp file is deleted** by Spring after the request completes.

```
MultipartFile → Temp File → InputStream → [8MB Block 1] → Azurite
                                         → [8MB Block 2] → Azurite
                                         → [8MB Block 3] → Azurite
                                         → ...
                                         → Put Block List  → Commit blob
```

## Azurite Connection String

Azurite uses a well-known fixed connection string (emulator):

```
DefaultEndpointsProtocol=http;
AccountName=devstoreaccount1;
AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;
BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;
```

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

Just update the connection string in `application.yml`:

```yaml
azure:
  blob:
    connection-string: "DefaultEndpointsProtocol=https;AccountName=YOUR_ACCOUNT;AccountKey=YOUR_KEY;BlobEndpoint=https://YOUR_ACCOUNT.blob.core.windows.net;"
    container-name: "uploads"
```

Everything else stays the same — the code is identical for emulator and production.