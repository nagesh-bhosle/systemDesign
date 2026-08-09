package com.example.blobupload.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobProperties;
import com.azure.storage.blob.models.ParallelTransferOptions;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import com.azure.storage.blob.specialized.BlockBlobClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class BlobStorageService {

    private static final Logger log = LoggerFactory.getLogger(BlobStorageService.class);

    private final BlobServiceClient blobServiceClient;
    private final String containerName;
    private final int blockSizeBytes;
    private final int maxConcurrency;

    public BlobStorageService(
            BlobServiceClient blobServiceClient,
            @Value("${azure.blob.container-name}") String containerName,
            @Value("${azure.blob.block-size-bytes}") int blockSizeBytes,
            @Value("${azure.blob.max-concurrency}") int maxConcurrency) {

        this.blobServiceClient = blobServiceClient;
        this.containerName = containerName;
        this.blockSizeBytes = blockSizeBytes;
        this.maxConcurrency = maxConcurrency;
    }

    /**
     * Upload a file using streaming (block blob upload).
     * This streams the InputStream directly to Azure Blob Storage in chunks,
     * so the entire file is never loaded into memory — critical for GB-sized files.
     */
    public UploadResult uploadFile(MultipartFile file, String blobName) throws IOException {
        // Ensure container exists
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        if (blobName == null || blobName.isBlank()) {
            blobName = file.getOriginalFilename();
        }

        BlobClient blobClient = containerClient.getBlobClient(blobName);

        log.info("Starting upload: blobName={}, size={} bytes, contentType={}",
                blobName, file.getSize(), file.getContentType());

        long startTime = System.currentTimeMillis();

        // Use streaming upload — data flows from InputStream to blob in blocks
        // Block size controls how much data is buffered per chunk
        ParallelTransferOptions transferOptions = new ParallelTransferOptions()
                .setBlockSizeLong((long) blockSizeBytes)
                .setMaxConcurrency(maxConcurrency);

        BlobParallelUploadOptions uploadOptions = new BlobParallelUploadOptions(file.getInputStream())
                .setParallelTransferOptions(transferOptions);

        // Stream the file to blob storage
        blobClient.uploadWithResponse(
                uploadOptions,
                Duration.ofMinutes(30),  // timeout for very large files
                null    // context
        );

        long elapsed = System.currentTimeMillis() - startTime;
        double elapsedSeconds = elapsed / 1000.0;
        double throughput = file.getSize() / (1024.0 * 1024.0) / elapsedSeconds;

        log.info("Upload complete: blobName={}, elapsed={}s, throughput={} MB/s",
                blobName, String.format("%.2f", elapsedSeconds), String.format("%.2f", throughput));

        return new UploadResult(
                blobName,
                blobClient.getBlobUrl(),
                file.getSize(),
                file.getContentType(),
                elapsed,
                throughput
        );
    }

    /**
     * Upload from a raw InputStream with a known size.
     * Useful for programmatic uploads without MultipartFile.
     */
    public UploadResult uploadStream(InputStream inputStream, long size, String blobName, String contentType) {
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        BlobClient blobClient = containerClient.getBlobClient(blobName);

        log.info("Starting stream upload: blobName={}, size={} bytes", blobName, size);

        long startTime = System.currentTimeMillis();

        ParallelTransferOptions transferOptions = new ParallelTransferOptions()
                .setBlockSizeLong((long) blockSizeBytes)
                .setMaxConcurrency(maxConcurrency);

        BlobParallelUploadOptions uploadOptions = new BlobParallelUploadOptions(inputStream)
                .setParallelTransferOptions(transferOptions);

        blobClient.uploadWithResponse(
                uploadOptions,
                Duration.ofMinutes(30),
                null
        );

        long elapsed = System.currentTimeMillis() - startTime;
        double elapsedSeconds = elapsed / 1000.0;
        double throughput = size / (1024.0 * 1024.0) / elapsedSeconds;

        log.info("Stream upload complete: blobName={}, elapsed={}s, throughput={} MB/s",
                blobName, String.format("%.2f", elapsedSeconds), String.format("%.2f", throughput));

        return new UploadResult(
                blobName,
                blobClient.getBlobUrl(),
                size,
                contentType,
                elapsed,
                throughput
            );
    }

    /**
     * List all blobs in the container.
     */
    public List<BlobInfo> listBlobs() {
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        List<BlobInfo> blobs = new ArrayList<>();
        for (BlobItem item : containerClient.listBlobs()) {
            BlobClient blobClient = containerClient.getBlobClient(item.getName());
            BlobProperties props = blobClient.getProperties();
            blobs.add(new BlobInfo(
                    item.getName(),
                    blobClient.getBlobUrl(),
                    props.getBlobSize(),
                    props.getContentType(),
                    props.getLastModified() != null ? props.getLastModified().toString() : "unknown"
            ));
        }
        return blobs;
    }

    /**
     * Delete a blob by name.
     */
    public boolean deleteBlob(String blobName) {
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        BlobClient blobClient = containerClient.getBlobClient(blobName);
        boolean deleted = blobClient.deleteIfExists();
        log.info("Delete blob '{}': {}", blobName, deleted ? "success" : "not found");
        return deleted;
    }

    /**
     * Download a blob as an InputStream (for streaming back to client).
     */
    public InputStream downloadBlob(String blobName) {
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        BlobClient blobClient = containerClient.getBlobClient(blobName);
        return blobClient.openInputStream();
    }

    /**
     * Get blob properties (size, type, last modified).
     */
    public BlobInfo getBlobInfo(String blobName) {
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        BlobClient blobClient = containerClient.getBlobClient(blobName);
        BlobProperties props = blobClient.getProperties();
        return new BlobInfo(
                blobName,
                blobClient.getBlobUrl(),
                props.getBlobSize(),
                props.getContentType(),
                props.getLastModified() != null ? props.getLastModified().toString() : "unknown"
        );
    }

    // ============================================================
    // CHUNKED UPLOAD (Block Blob API: stageBlock + commitBlockList)
    // ============================================================

    /**
     * In-memory tracker for active chunked uploads.
     * Key = uploadId, Value = ordered list of block IDs staged so far.
     * In production you'd use Redis or a database instead of in-memory.
     */
    private final Map<String, List<String>> activeUploads = new ConcurrentHashMap<>();

    /**
     * Start a new chunked upload session.
     * Returns an uploadId that the client uses for all subsequent chunk uploads.
     */
    public String startChunkedUpload(String blobName) {
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        BlobClient blobClient = containerClient.getBlobClient(blobName);

        // Ensure it's a block blob (default type for new blobs)
        BlockBlobClient blockBlobClient = blobClient.getBlockBlobClient();

        String uploadId = java.util.UUID.randomUUID().toString();
        activeUploads.put(uploadId, new ArrayList<>());

        log.info("Started chunked upload: uploadId={}, blobName={}", uploadId, blobName);
        return uploadId;
    }

    /**
     * Stage a single chunk as an uncommitted block in Azure Blob Storage.
     *
     * Azure Block Blob flow:
     *   1. stageBlock  — upload chunk data as an uncommitted block (identified by blockId)
     *   2. commitBlockList — tell Azure the final order of all block IDs → blob is assembled
     *
     * Blocks are NOT visible as part of the blob until commitBlockList is called.
     * Each block can be up to 400 MB. A block blob can have up to 50,000 blocks.
     *
     * @param uploadId  the session ID returned by startChunkedUpload
     * @param blobName  the final blob name in the container
     * @param partNumber  1-based index of this chunk (used to generate a unique blockId)
     * @param chunkData  the raw bytes of this chunk
     * @return the base64 blockId assigned to this chunk
     */
    public String stageChunk(String uploadId, String blobName, int partNumber, byte[] chunkData) throws IOException {
        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        BlockBlobClient blockBlobClient = containerClient
                .getBlobClient(blobName)
                .getBlockBlobClient();

        // Generate a unique block ID — must be base64-encoded, same length for all blocks
        // We pad the part number to 10 digits so all block IDs have equal length
        String blockId = Base64.getEncoder()
                .encodeToString(String.format("%010d", partNumber).getBytes(StandardCharsets.UTF_8));

        log.info("Staging chunk: uploadId={}, blobName={}, partNumber={}, chunkSize={} bytes, blockId={}",
                uploadId, blobName, partNumber, chunkData.length, blockId);

        long startTime = System.currentTimeMillis();

        // Stage the block — data goes to Azure but is NOT part of the blob yet
        try (InputStream chunkStream = new ByteArrayInputStream(chunkData)) {
            blockBlobClient.stageBlock(blockId, chunkStream, chunkData.length);
        }

        long elapsed = System.currentTimeMillis() - startTime;
        double throughput = (chunkData.length / (1024.0 * 1024.0)) / (elapsed / 1000.0);

        log.info("Chunk staged: partNumber={}, elapsed={}ms, throughput={} MB/s",
                partNumber, elapsed, String.format("%.2f", throughput));

        // Track this block ID for later commit
        List<String> blockIds = activeUploads.get(uploadId);
        if (blockIds == null) {
            throw new IllegalStateException("Unknown uploadId: " + uploadId + ". Session may have expired.");
        }
        synchronized (blockIds) {
            // Ensure the list is large enough
            while (blockIds.size() < partNumber) {
                blockIds.add(null);
            }
            blockIds.set(partNumber - 1, blockId);
        }

        return blockId;
    }

    /**
     * Commit all staged blocks — this assembles the final blob.
     * After this call, the blob is visible and downloadable.
     */
    public UploadResult commitChunkedUpload(String uploadId, String blobName, String contentType) {
        List<String> blockIds = activeUploads.remove(uploadId);
        if (blockIds == null || blockIds.isEmpty()) {
            throw new IllegalStateException("No staged blocks found for uploadId: " + uploadId);
        }

        // Remove any nulls (shouldn't happen if client sent all parts)
        blockIds.removeIf(id -> id == null);

        BlobContainerClient containerClient = blobServiceClient
                .createBlobContainerIfNotExists(containerName);

        BlockBlobClient blockBlobClient = containerClient
                .getBlobClient(blobName)
                .getBlockBlobClient();

        log.info("Committing chunked upload: uploadId={}, blobName={}, totalBlocks={}",
                uploadId, blobName, blockIds.size());

        long startTime = System.currentTimeMillis();

        // This is the magic call — Azure assembles all uncommitted blocks
        // into the final blob in the order of the block IDs provided
        blockBlobClient.commitBlockList(blockIds);

        long elapsed = System.currentTimeMillis() - startTime;

        // Get the final blob size
        long blobSize = blockBlobClient.getProperties().getBlobSize();

        log.info("Chunked upload committed: blobName={}, totalBlocks={}, finalSize={} bytes, elapsed={}ms",
                blobName, blockIds.size(), blobSize, elapsed);

        return new UploadResult(
                blobName,
                blockBlobClient.getBlobUrl(),
                blobSize,
                contentType,
                elapsed,
                0.0 // throughput not meaningful for commit (it's just metadata)
        );
    }

    /**
     * Abort a chunked upload — uncommitted blocks are automatically
     * garbage-collected by Azure after a period (typically 7 days).
     */
    public void abortChunkedUpload(String uploadId) {
        activeUploads.remove(uploadId);
        log.info("Aborted chunked upload: uploadId={}", uploadId);
    }

    // --- Result DTOs ---

    public record UploadResult(
            String blobName,
            String blobUrl,
            long sizeBytes,
            String contentType,
            long elapsedMs,
            double throughputMBps
    ) {}

    public record BlobInfo(
            String name,
            String url,
            long sizeBytes,
            String contentType,
            String lastModified
    ) {}
}