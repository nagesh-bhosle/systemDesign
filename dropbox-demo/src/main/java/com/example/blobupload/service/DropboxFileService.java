package com.example.blobupload.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.specialized.BlockBlobClient;
import com.example.blobupload.entity.ChunkStatus;
import com.example.blobupload.entity.FileMetadata;
import com.example.blobupload.entity.FileShare;
import com.example.blobupload.repository.ChunkStatusRepository;
import com.example.blobupload.repository.FileMetadataRepository;
import com.example.blobupload.repository.FileShareRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

/**
 * Core Dropbox-like file service.
 *
 * Implements the key concepts from the Dropbox system design article:
 *   1. File metadata stored in a database (H2 for demo, DynamoDB/PostgreSQL in prod)
 *   2. File content stored in Blob Storage (Azurite for demo, S3 in prod)
 *   3. Fingerprinting (SHA-256) for deduplication and resumable uploads
 *   4. Chunked upload with per-chunk status tracking
 *   5. Server-side chunk verification
 *   6. Sharing via a separate FileShare table (ACL)
 *   7. Change events for sync (GET /files/changes?since={timestamp})
 */
@Service
public class DropboxFileService {

    private static final Logger log = LoggerFactory.getLogger(DropboxFileService.class);

    private final BlobServiceClient blobServiceClient;
    private final String containerName;
    private final int defaultChunkSize;

    private final FileMetadataRepository fileRepo;
    private final ChunkStatusRepository chunkRepo;
    private final FileShareRepository shareRepo;

    public DropboxFileService(
            BlobServiceClient blobServiceClient,
            @Value("${azure.blob.container-name}") String containerName,
            @Value("${dropbox.chunk-size-bytes:4194304}") int defaultChunkSize,
            FileMetadataRepository fileRepo,
            ChunkStatusRepository chunkRepo,
            FileShareRepository shareRepo) {
        this.blobServiceClient = blobServiceClient;
        this.containerName = containerName;
        this.defaultChunkSize = defaultChunkSize;
        this.fileRepo = fileRepo;
        this.chunkRepo = chunkRepo;
        this.shareRepo = shareRepo;
    }

    // ============================================================
    // FINGERPRINTING (SHA-256)
    // ============================================================

    /**
     * Compute SHA-256 fingerprint of a byte array.
     * Used by the client to identify files for dedup and resumability.
     */
    public String computeFingerprint(byte[] data) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(data);
            return bytesToHex(hash);
        } catch (Exception e) {
            throw new RuntimeException("Failed to compute fingerprint", e);
        }
    }

    /**
     * Compute SHA-256 fingerprint of a chunk.
     */
    public String computeChunkFingerprint(byte[] chunkData) {
        return computeFingerprint(chunkData);
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    // ============================================================
    // CHUNKED UPLOAD (with metadata + fingerprinting)
    // ============================================================

    /**
     * Step 1: Initialize a chunked upload.
     *
     * From the article:
     *   "If the file does not exist, the client will POST a request to initiate
     *    a multipart upload. The backend will save the file metadata in the
     *    FileMetadata table with a status of 'uploading'."
     *
     * @param fingerprint  SHA-256 of the entire file (computed client-side)
     * @param fileName     original file name
     * @param fileSize     total file size in bytes
     * @param mimeType     MIME type
     * @param userId       the uploading user's ID
     * @return the created FileMetadata (status = UPLOADING)
     */
    @Transactional
    public FileMetadata initChunkedUpload(String fingerprint, String fileName, long fileSize,
                                          String mimeType, UUID userId) {

        // Check for dedup — if a file with this fingerprint already exists and is UPLOADED,
        // we can skip the upload entirely
        Optional<FileMetadata> existing = fileRepo.findByFingerprint(fingerprint);
        if (existing.isPresent() && "UPLOADED".equals(existing.get().getStatus())) {
            log.info("Dedup hit: fingerprint={} already uploaded as '{}'", fingerprint, existing.get().getName());
            return existing.get();
        }

        // If there's an in-progress upload with the same fingerprint, resume it
        if (existing.isPresent() && "UPLOADING".equals(existing.get().getStatus())) {
            log.info("Resumable upload detected: fingerprint={} is already in progress", fingerprint);
            return existing.get();
        }

        // Create new file metadata with status = UPLOADING
        String blobName = userId + "/" + UUID.randomUUID() + "/" + fileName;
        FileMetadata metadata = new FileMetadata(
                fileName, fileSize, mimeType, blobName, fingerprint, "UPLOADING", userId);
        metadata = fileRepo.save(metadata);

        // Pre-create chunk status records
        int totalChunks = (int) Math.ceil((double) fileSize / defaultChunkSize);
        for (int i = 1; i <= totalChunks; i++) {
            long chunkSize = Math.min(defaultChunkSize, fileSize - (long)(i - 1) * defaultChunkSize);
            ChunkStatus chunk = new ChunkStatus(metadata.getId(), i, chunkSize);
            chunkRepo.save(chunk);
        }

        log.info("Initialized chunked upload: fileId={}, blobName={}, totalChunks={}, fingerprint={}",
                metadata.getId(), blobName, totalChunks, fingerprint);

        return metadata;
    }

    /**
     * Step 2: Upload a single chunk.
     *
     * From the article:
     *   "After each chunk is uploaded, the client sends a PATCH request to our
     *    backend with the chunk status and ETag. Our backend can then verify the
     *    chunk uploads with S3's ListParts API before updating the chunks field."
     *
     * In our implementation, the client sends the chunk directly to our server
     * (not via presigned URL to S3, for simplicity). We stage it as a block in
     * Azure Blob Storage and update the chunk status.
     *
     * @param fileId      the file metadata ID
     * @param partNumber   1-based chunk index
     * @param chunkData    raw bytes of this chunk
     * @param chunkHash    SHA-256 of this chunk (computed client-side, verified server-side)
     */
    @Transactional
    public ChunkStatus uploadChunk(UUID fileId, int partNumber, byte[] chunkData, String chunkHash) throws IOException {
        FileMetadata metadata = fileRepo.findById(fileId)
                .orElseThrow(() -> new IllegalArgumentException("File not found: " + fileId));

        if (!"UPLOADING".equals(metadata.getStatus())) {
            throw new IllegalStateException("File is not in UPLOADING state: " + metadata.getStatus());
        }

        // Server-side chunk verification — verify the hash matches
        String serverHash = computeChunkFingerprint(chunkData);
        if (chunkHash != null && !chunkHash.equals(serverHash)) {
            throw new IllegalArgumentException(
                    "Chunk hash mismatch! Client=" + chunkHash.substring(0, 16) + "... Server=" + serverHash.substring(0, 16) + "...");
        }

        // Stage the block in Azure Blob Storage
        BlobContainerClient containerClient = blobServiceClient.createBlobContainerIfNotExists(containerName);
        BlockBlobClient blockBlobClient = containerClient
                .getBlobClient(metadata.getBlobName())
                .getBlockBlobClient();

        String blockId = Base64.getEncoder()
                .encodeToString(String.format("%010d", partNumber).getBytes(StandardCharsets.UTF_8));

        try (InputStream chunkStream = new ByteArrayInputStream(chunkData)) {
            blockBlobClient.stageBlock(blockId, chunkStream, chunkData.length);
        }

        // Update chunk status in DB
        List<ChunkStatus> chunks = chunkRepo.findByFileIdOrderByPartNumberAsc(fileId);
        ChunkStatus chunk = chunks.stream()
                .filter(c -> c.getPartNumber() == partNumber)
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Chunk not found: part " + partNumber));

        chunk.setBlockId(blockId);
        chunk.setStatus("UPLOADED");
        chunk.setChunkHash(serverHash);
        chunk.setUploadedAt(Instant.now());
        chunkRepo.save(chunk);

        log.info("Chunk uploaded: fileId={}, part={}/{}, size={} bytes, blockId={}",
                fileId, partNumber, chunks.size(), chunkData.length, blockId);

        return chunk;
    }

    /**
     * Step 3: Complete the chunked upload — commit all blocks and update metadata.
     *
     * From the article:
     *   "Once all chunks in our chunks array are marked as 'uploaded', the backend
     *    calls S3's CompleteMultipartUpload API with the list of part numbers and
     *    ETags. This tells S3 to assemble all the parts into a single object.
     *    Only after S3 confirms successful assembly does the backend update the
     *    FileMetadata table to mark the file as 'uploaded'."
     */
    @Transactional
    public FileMetadata completeChunkedUpload(UUID fileId) {
        FileMetadata metadata = fileRepo.findById(fileId)
                .orElseThrow(() -> new IllegalArgumentException("File not found: " + fileId));

        List<ChunkStatus> chunks = chunkRepo.findByFileIdOrderByPartNumberAsc(fileId);

        // Verify all chunks are uploaded
        long uploadedCount = chunkRepo.countByFileIdAndStatus(fileId, "UPLOADED");
        if (uploadedCount != chunks.size()) {
            throw new IllegalStateException(
                    "Not all chunks uploaded: " + uploadedCount + "/" + chunks.size());
        }

        // Commit the block list — Azure assembles the final blob
        BlobContainerClient containerClient = blobServiceClient.createBlobContainerIfNotExists(containerName);
        BlockBlobClient blockBlobClient = containerClient
                .getBlobClient(metadata.getBlobName())
                .getBlockBlobClient();

        List<String> blockIds = chunks.stream()
                .map(ChunkStatus::getBlockId)
                .filter(Objects::nonNull)
                .toList();

        log.info("Committing block list: fileId={}, blobName={}, totalBlocks={}",
                fileId, metadata.getBlobName(), blockIds.size());

        blockBlobClient.commitBlockList(blockIds);

        // Update metadata status to UPLOADED
        metadata.setStatus("UPLOADED");
        metadata = fileRepo.save(metadata);

        log.info("Chunked upload complete: fileId={}, blobUrl={}", fileId, blockBlobClient.getBlobUrl());

        return metadata;
    }

    /**
     * Get chunk status for a file — used by the client to resume an interrupted upload.
     * Returns which chunks are already uploaded and which still need to be sent.
     */
    @Transactional(readOnly = true)
    public List<ChunkStatus> getChunkStatus(UUID fileId) {
        return chunkRepo.findByFileIdOrderByPartNumberAsc(fileId);
    }

    // ============================================================
    // SIMPLE UPLOAD (small files — no chunking needed)
    // ============================================================

    /**
     * Simple upload for small files. Computes fingerprint, stores in blob,
     * and creates metadata in one shot.
     */
    @Transactional
    public FileMetadata simpleUpload(byte[] data, String fileName, String mimeType, UUID userId) {
        String fingerprint = computeFingerprint(data);

        // Dedup check
        Optional<FileMetadata> existing = fileRepo.findByFingerprint(fingerprint);
        if (existing.isPresent() && "UPLOADED".equals(existing.get().getStatus())) {
            log.info("Dedup hit: fingerprint={} already uploaded", fingerprint);
            return existing.get();
        }

        String blobName = userId + "/" + UUID.randomUUID() + "/" + fileName;
        BlobContainerClient containerClient = blobServiceClient.createBlobContainerIfNotExists(containerName);
        BlobClient blobClient = containerClient.getBlobClient(blobName);

        try (InputStream stream = new ByteArrayInputStream(data)) {
            blobClient.upload(stream, data.length, true);
        } catch (IOException e) {
            throw new RuntimeException("Upload failed", e);
        }

        FileMetadata metadata = new FileMetadata(
                fileName, data.length, mimeType, blobName, fingerprint, "UPLOADED", userId);
        return fileRepo.save(metadata);
    }

    // ============================================================
    // DOWNLOAD
    // ============================================================

    /**
     * Download a file's content as an InputStream.
     *
     * From the article:
     *   "The client gets a single presigned URL (or CDN signed URL) and downloads
     *    the complete file. For very large files, S3 and HTTP natively support
     *    Range requests, which let the client download different byte ranges in
     *    parallel or resume an interrupted download without starting over."
     */
    @Transactional(readOnly = true)
    public InputStream downloadFile(UUID fileId, UUID requestingUserId) {
        FileMetadata metadata = getFileMetadataForUser(fileId, requestingUserId);

        BlobContainerClient containerClient = blobServiceClient.createBlobContainerIfNotExists(containerName);
        BlobClient blobClient = containerClient.getBlobClient(metadata.getBlobName());

        return blobClient.openInputStream();
    }

    // ============================================================
    // FILE METADATA OPERATIONS
    // ============================================================

    @Transactional(readOnly = true)
    public FileMetadata getFileMetadata(UUID fileId) {
        return fileRepo.findById(fileId)
                .orElseThrow(() -> new IllegalArgumentException("File not found: " + fileId));
    }

    /**
     * Get file metadata, checking that the requesting user has access
     * (either owner or shared with them).
     */
    @Transactional(readOnly = true)
    public FileMetadata getFileMetadataForUser(UUID fileId, UUID userId) {
        FileMetadata metadata = getFileMetadata(fileId);

        // Owner always has access
        if (metadata.getUploadedBy().equals(userId)) {
            return metadata;
        }

        // Check if shared with this user
        if (!shareRepo.existsByFileIdAndSharedWithUserId(fileId, userId)) {
            throw new SecurityException("User " + userId + " does not have access to file " + fileId);
        }

        return metadata;
    }

    /**
     * List all files owned by a user.
     */
    @Transactional(readOnly = true)
    public List<FileMetadata> listFiles(UUID userId) {
        return fileRepo.findByUploadedBy(userId);
    }

    /**
     * List all files shared with a user.
     */
    @Transactional(readOnly = true)
    public List<FileMetadata> listSharedFiles(UUID userId) {
        List<FileShare> shares = shareRepo.findBySharedWithUserId(userId);
        List<FileMetadata> files = new ArrayList<>();
        for (FileShare share : shares) {
            fileRepo.findById(share.getFileId()).ifPresent(files::add);
        }
        return files;
    }

    /**
     * Delete a file (soft delete — mark as DELETED, keep the blob for recovery).
     *
     * From the article:
     *   "We should be able to recover files if they are lost or corrupted."
     */
    @Transactional
    public void deleteFile(UUID fileId, UUID userId) {
        FileMetadata metadata = getFileMetadata(fileId);

        if (!metadata.getUploadedBy().equals(userId)) {
            throw new SecurityException("Only the owner can delete this file");
        }

        metadata.setStatus("DELETED");
        fileRepo.save(metadata);

        log.info("File deleted (soft): fileId={}, blobName={}", fileId, metadata.getBlobName());
    }

    // ============================================================
    // SYNC — Change Events
    // ============================================================

    /**
     * Get all file changes since a given timestamp.
     *
     * From the article:
     *   "GET /files/changes?since={timestamp} -> ChangeEvent[]"
     *
     * This is the polling fallback for sync. The primary mechanism is SSE
     * (Server-Sent Events) via the SyncService.
     */
    @Transactional(readOnly = true)
    public List<ChangeEvent> getChanges(UUID userId, Instant since) {
        List<FileMetadata> ownedFiles = fileRepo.findByUploadedByAndUpdatedAtAfter(userId, since);

        List<ChangeEvent> events = new ArrayList<>();
        for (FileMetadata metadata : ownedFiles) {
            String type = "DELETED".equals(metadata.getStatus()) ? "DELETED" : "UPDATED";
            events.add(new ChangeEvent(
                    metadata.getId(),
                    metadata.getName(),
                    metadata.getSize(),
                    metadata.getMimeType(),
                    metadata.getStatus(),
                    metadata.getUpdatedAt()
            ));
        }

        // Also check shared files
        List<FileShare> shares = shareRepo.findBySharedWithUserId(userId);
        for (FileShare share : shares) {
            fileRepo.findById(share.getFileId()).ifPresent(metadata -> {
                if (metadata.getUpdatedAt() != null && metadata.getUpdatedAt().isAfter(since)) {
                    String type = "DELETED".equals(metadata.getStatus()) ? "DELETED" : "UPDATED";
                    events.add(new ChangeEvent(
                            metadata.getId(),
                            metadata.getName(),
                            metadata.getSize(),
                            metadata.getMimeType(),
                            metadata.getStatus(),
                            metadata.getUpdatedAt()
                    ));
                }
            });
        }

        return events;
    }

    // ============================================================
    // SHARING
    // ============================================================

    /**
     * Share a file with another user.
     *
     * From the article:
     *   "Great Solution: Create a separate table for shares"
     */
    @Transactional
    public FileShare shareFile(UUID fileId, UUID sharedWithUserId, UUID sharedByUserId) {
        FileMetadata metadata = getFileMetadata(fileId);

        if (!metadata.getUploadedBy().equals(sharedByUserId)) {
            throw new SecurityException("Only the owner can share this file");
        }

        if (sharedWithUserId.equals(sharedByUserId)) {
            throw new IllegalArgumentException("Cannot share a file with yourself");
        }

        // Check if already shared
        if (shareRepo.existsByFileIdAndSharedWithUserId(fileId, sharedWithUserId)) {
            throw new IllegalStateException("File already shared with this user");
        }

        FileShare share = new FileShare(fileId, sharedWithUserId, sharedByUserId);
        share = shareRepo.save(share);

        log.info("File shared: fileId={}, sharedWith={}, sharedBy={}", fileId, sharedWithUserId, sharedByUserId);

        return share;
    }

    /**
     * List all users a file is shared with.
     */
    @Transactional(readOnly = true)
    public List<FileShare> getFileShares(UUID fileId) {
        return shareRepo.findByFileId(fileId);
    }

    // ============================================================
    // DTO
    // ============================================================

    public record ChangeEvent(
            UUID fileId,
            String name,
            long size,
            String mimeType,
            String status,
            Instant updatedAt
    ) {}
}