package com.example.blobupload.controller;

import com.example.blobupload.entity.ChunkStatus;
import com.example.blobupload.entity.FileMetadata;
import com.example.blobupload.entity.FileShare;
import com.example.blobupload.entity.User;
import com.example.blobupload.repository.UserRepository;
import com.example.blobupload.service.DropboxFileService;
import com.example.blobupload.service.SyncService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.InputStream;
import java.time.Instant;
import java.util.*;

/**
 * Dropbox-like REST API controller.
 *
 * Implements all four functional requirements from the article:
 *   1. Upload a file from any device (simple + chunked)
 *   2. Download a file from any device
 *   3. Share a file with other users
 *   4. Automatically sync files across devices (SSE + polling)
 *
 * For simplicity, we use a header "X-User-Id" for authentication.
 * In production, this would be a JWT token or session cookie.
 */
@RestController
@RequestMapping("/api/dropbox")
public class DropboxController {

    private static final Logger log = LoggerFactory.getLogger(DropboxController.class);

    private final DropboxFileService fileService;
    private final SyncService syncService;
    private final UserRepository userRepo;

    public DropboxController(DropboxFileService fileService, SyncService syncService,
                             UserRepository userRepo) {
        this.fileService = fileService;
        this.syncService = syncService;
        this.userRepo = userRepo;
    }

    // ============================================================
    // USER MANAGEMENT (simplified)
    // ============================================================

    /**
     * Register or get a user by email.
     *
     * curl -X POST http://localhost:8080/api/dropbox/users -H "Content-Type: application/json" \
     *   -d '{"email":"alice@example.com","name":"Alice"}'
     */
    @PostMapping("/users")
    public ResponseEntity<User> createOrUpdateUser(@RequestBody Map<String, String> body) {
        String email = body.get("email");
        String name = body.get("name");

        User user = userRepo.findByEmail(email).orElseGet(() -> new User(email, name));
        if (user.getName() == null) user.setName(name);
        user = userRepo.save(user);
        return ResponseEntity.ok(user);
    }

    // ============================================================
    // 1) UPLOAD
    // ============================================================

    /**
     * Simple upload for small files (no chunking).
     *
     * curl -X POST http://localhost:8080/api/dropbox/files/upload \
     *   -H "X-User-Id: <uuid>" \
     *   -H "Content-Type: application/octet-stream" \
     *   --data-binary @small-file.txt
     */
    @PostMapping(value = "/files/upload", consumes = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    public ResponseEntity<FileMetadata> simpleUpload(
            @RequestHeader("X-User-Id") UUID userId,
            @RequestParam(value = "name", required = false) String name,
            @RequestParam(value = "mimeType", required = false, defaultValue = "application/octet-stream") String mimeType,
            @RequestBody byte[] data) {

        if (name == null) name = "unnamed-file";
        FileMetadata metadata = fileService.simpleUpload(data, name, mimeType, userId);

        // Notify via SSE
        syncService.notifyChange(userId, new DropboxFileService.ChangeEvent(
                metadata.getId(), metadata.getName(), metadata.getSize(),
                metadata.getMimeType(), metadata.getStatus(), metadata.getUpdatedAt()));

        return ResponseEntity.ok(metadata);
    }

    /**
     * Initialize a chunked upload (for large files).
     *
     * From the article:
     *   "The client will send a request to check if a file with the same fingerprint
     *    already exists for this user. If it does and has a status of 'uploading',
     *    the client can resume the upload by fetching the existing chunk statuses."
     *
     * curl -X POST http://localhost:8080/api/dropbox/files/chunk/init \
     *   -H "X-User-Id: <uuid>" -H "Content-Type: application/json" \
     *   -d '{"fingerprint":"sha256hash","name":"big-video.mp4","size":10737418240,"mimeType":"video/mp4"}'
     */
    @PostMapping("/files/chunk/init")
    public ResponseEntity<Map<String, Object>> initChunkedUpload(
            @RequestHeader("X-User-Id") UUID userId,
            @RequestBody Map<String, Object> body) {

        String fingerprint = (String) body.get("fingerprint");
        String name = (String) body.get("name");
        long size = ((Number) body.get("size")).longValue();
        String mimeType = (String) body.getOrDefault("mimeType", "application/octet-stream");

        FileMetadata metadata = fileService.initChunkedUpload(fingerprint, name, size, mimeType, userId);

        // Return metadata + chunk status (so client knows which chunks to resume)
        List<ChunkStatus> chunkStatuses = fileService.getChunkStatus(metadata.getId());

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("fileId", metadata.getId());
        response.put("blobName", metadata.getBlobName());
        response.put("status", metadata.getStatus());
        response.put("dedup", !metadata.getUploadedBy().equals(userId) || "UPLOADED".equals(metadata.getStatus()));
        response.put("totalChunks", chunkStatuses.size());
        response.put("uploadedChunks", chunkStatuses.stream()
                .filter(c -> "UPLOADED".equals(c.getStatus()))
                .map(ChunkStatus::getPartNumber)
                .toList());

        return ResponseEntity.ok(response);
    }

    /**
     * Upload a single chunk.
     *
     * curl -X POST "http://localhost:8080/api/dropbox/files/chunk/upload?fileId=<uuid>&partNumber=1&chunkHash=sha256" \
     *   -H "X-User-Id: <uuid>" --data-binary @chunk_001.bin
     */
    @PostMapping(value = "/files/chunk/upload", consumes = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    public ResponseEntity<Map<String, Object>> uploadChunk(
            @RequestHeader("X-User-Id") UUID userId,
            @RequestParam("fileId") UUID fileId,
            @RequestParam("partNumber") int partNumber,
            @RequestParam(value = "chunkHash", required = false) String chunkHash,
            @RequestBody byte[] chunkData) throws Exception {

        ChunkStatus chunk = fileService.uploadChunk(fileId, partNumber, chunkData, chunkHash);

        return ResponseEntity.ok(Map.of(
                "fileId", fileId,
                "partNumber", partNumber,
                "status", chunk.getStatus(),
                "chunkHash", chunk.getChunkHash() != null ? chunk.getChunkHash() : "",
                "size", chunk.getChunkSize()
        ));
    }

    /**
     * Complete a chunked upload — assemble the final blob.
     *
     * curl -X POST "http://localhost:8080/api/dropbox/files/chunk/complete?fileId=<uuid>" \
     *   -H "X-User-Id: <uuid>"
     */
    @PostMapping("/files/chunk/complete")
    public ResponseEntity<FileMetadata> completeChunkedUpload(
            @RequestHeader("X-User-Id") UUID userId,
            @RequestParam("fileId") UUID fileId) {

        FileMetadata metadata = fileService.completeChunkedUpload(fileId);

        // Notify via SSE
        syncService.notifyChange(userId, new DropboxFileService.ChangeEvent(
                metadata.getId(), metadata.getName(), metadata.getSize(),
                metadata.getMimeType(), metadata.getStatus(), metadata.getUpdatedAt()));

        return ResponseEntity.ok(metadata);
    }

    // ============================================================
    // 2) DOWNLOAD
    // ============================================================

    /**
     * Download a file (streams the content).
     *
     * curl -OJ http://localhost:8080/api/dropbox/files/<uuid>/download -H "X-User-Id: <uuid>"
     */
    @GetMapping("/files/{fileId}/download")
    public ResponseEntity<InputStreamResource> downloadFile(
            @RequestHeader("X-User-Id") UUID userId,
            @PathVariable UUID fileId) {

        FileMetadata metadata = fileService.getFileMetadataForUser(fileId, userId);
        InputStream stream = fileService.downloadFile(fileId, userId);

        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"" + metadata.getName() + "\"")
                .contentLength(metadata.getSize())
                .body(new InputStreamResource(stream));
    }

    // ============================================================
    // FILE METADATA
    // ============================================================

    /**
     * List all files owned by the user.
     *
     * curl http://localhost:8080/api/dropbox/files -H "X-User-Id: <uuid>"
     */
    @GetMapping("/files")
    public ResponseEntity<List<FileMetadata>> listFiles(@RequestHeader("X-User-Id") UUID userId) {
        return ResponseEntity.ok(fileService.listFiles(userId));
    }

    /**
     * List all files shared with the user.
     *
     * curl http://localhost:8080/api/dropbox/files/shared -H "X-User-Id: <uuid>"
     */
    @GetMapping("/files/shared")
    public ResponseEntity<List<FileMetadata>> listSharedFiles(@RequestHeader("X-User-Id") UUID userId) {
        return ResponseEntity.ok(fileService.listSharedFiles(userId));
    }

    /**
     * Get metadata for a specific file.
     *
     * curl http://localhost:8080/api/dropbox/files/<uuid> -H "X-User-Id: <uuid>"
     */
    @GetMapping("/files/{fileId}")
    public ResponseEntity<FileMetadata> getFileMetadata(
            @RequestHeader("X-User-Id") UUID userId,
            @PathVariable UUID fileId) {
        return ResponseEntity.ok(fileService.getFileMetadataForUser(fileId, userId));
    }

    /**
     * Delete a file (soft delete).
     *
     * curl -X DELETE http://localhost:8080/api/dropbox/files/<uuid> -H "X-User-Id: <uuid>"
     */
    @DeleteMapping("/files/{fileId}")
    public ResponseEntity<Map<String, Boolean>> deleteFile(
            @RequestHeader("X-User-Id") UUID userId,
            @PathVariable UUID fileId) {

        fileService.deleteFile(fileId, userId);

        // Notify via SSE
        FileMetadata metadata = fileService.getFileMetadata(fileId);
        syncService.notifyChange(userId, new DropboxFileService.ChangeEvent(
                metadata.getId(), metadata.getName(), metadata.getSize(),
                metadata.getMimeType(), "DELETED", metadata.getUpdatedAt()));

        return ResponseEntity.ok(Map.of("deleted", true));
    }

    // ============================================================
    // 3) SHARING
    // ============================================================

    /**
     * Share a file with another user.
     *
     * curl -X POST http://localhost:8080/api/dropbox/files/<uuid>/share \
     *   -H "X-User-Id: <uuid>" -H "Content-Type: application/json" \
     *   -d '{"sharedWithUserId":"<uuid>"}'
     */
    @PostMapping("/files/{fileId}/share")
    public ResponseEntity<FileShare> shareFile(
            @RequestHeader("X-User-Id") UUID userId,
            @PathVariable UUID fileId,
            @RequestBody Map<String, String> body) {

        UUID sharedWithUserId = UUID.fromString(body.get("sharedWithUserId"));
        FileShare share = fileService.shareFile(fileId, sharedWithUserId, userId);

        // Notify the shared user via SSE
        FileMetadata metadata = fileService.getFileMetadata(fileId);
        syncService.notifyChange(sharedWithUserId, new DropboxFileService.ChangeEvent(
                metadata.getId(), metadata.getName(), metadata.getSize(),
                metadata.getMimeType(), "SHARED", metadata.getUpdatedAt()));

        return ResponseEntity.ok(share);
    }

    /**
     * List all shares for a file.
     *
     * curl http://localhost:8080/api/dropbox/files/<uuid>/shares -H "X-User-Id: <uuid>"
     */
    @GetMapping("/files/{fileId}/shares")
    public ResponseEntity<List<FileShare>> listShares(
            @RequestHeader("X-User-Id") UUID userId,
            @PathVariable UUID fileId) {
        return ResponseEntity.ok(fileService.getFileShares(fileId));
    }

    // ============================================================
    // 4) SYNC
    // ============================================================

    /**
     * SSE endpoint for real-time sync notifications.
     *
     * From the article:
     *   "The server maintains an open connection with each client and pushes
     *    notifications when changes occur."
     *
     * curl -N http://localhost:8080/api/dropbox/sync/events -H "X-User-Id: <uuid>"
     */
    @GetMapping(value = "/sync/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter syncEvents(
            @RequestHeader(value = "X-User-Id", required = false) UUID userIdHeader,
            @RequestParam(value = "userId", required = false) UUID userIdParam) {
        UUID userId = userIdHeader != null ? userIdHeader : userIdParam;
        return syncService.register(userId);
    }

    /**
     * Polling fallback for sync — get all changes since a timestamp.
     *
     * From the article:
     *   "Periodic polling as a safety net: WebSocket connections can drop, and
     *    messages can be missed. To handle this, the client also periodically
     *    polls the server using GET /files/changes?since={timestamp}."
     *
     * curl "http://localhost:8080/api/dropbox/sync/changes?since=2024-01-01T00:00:00Z" \
     *   -H "X-User-Id: <uuid>"
     */
    @GetMapping("/sync/changes")
    public ResponseEntity<List<DropboxFileService.ChangeEvent>> getChanges(
            @RequestHeader("X-User-Id") UUID userId,
            @RequestParam(value = "since", required = false) String sinceStr) {

        Instant since = sinceStr != null ? Instant.parse(sinceStr) : Instant.EPOCH;
        return ResponseEntity.ok(fileService.getChanges(userId, since));
    }
}