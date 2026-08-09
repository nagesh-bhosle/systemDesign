package com.example.blobupload.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobProperties;
import com.azure.storage.blob.models.ParallelTransferOptions;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

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