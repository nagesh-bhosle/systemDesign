package com.example.blobupload.entity;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * Tracks the status of each chunk during a chunked upload.
 *
 * From the article's deep dive:
 *   "We can do this by saving the state of the upload in the database,
 *    specifically in our FileMetadata table. Let's update the FileMetadata
 *    schema to include a chunks field."
 *
 * Each chunk has:
 *   - partNumber: 1-based index
 *   - blockId: the Azure Block Blob ID (base64-encoded)
 *   - status: NOT_UPLOADED, UPLOADED
 *   - chunkHash: SHA-256 of this chunk (for server-side verification)
 */
@Entity
@Table(name = "chunk_status")
public class ChunkStatus {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private UUID fileId;

    @Column(nullable = false)
    private int partNumber;

    private String blockId;

    @Column(nullable = false)
    private String status = "NOT_UPLOADED";

    private String chunkHash;

    private long chunkSize;

    private Instant uploadedAt;

    // --- Constructors ---

    public ChunkStatus() {}

    public ChunkStatus(UUID fileId, int partNumber, long chunkSize) {
        this.fileId = fileId;
        this.partNumber = partNumber;
        this.chunkSize = chunkSize;
    }

    // --- Getters & Setters ---

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }

    public UUID getFileId() { return fileId; }
    public void setFileId(UUID fileId) { this.fileId = fileId; }

    public int getPartNumber() { return partNumber; }
    public void setPartNumber(int partNumber) { this.partNumber = partNumber; }

    public String getBlockId() { return blockId; }
    public void setBlockId(String blockId) { this.blockId = blockId; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getChunkHash() { return chunkHash; }
    public void setChunkHash(String chunkHash) { this.chunkHash = chunkHash; }

    public long getChunkSize() { return chunkSize; }
    public void setChunkSize(long chunkSize) { this.chunkSize = chunkSize; }

    public Instant getUploadedAt() { return uploadedAt; }
    public void setUploadedAt(Instant uploadedAt) { this.uploadedAt = uploadedAt; }
}