package com.example.blobupload.entity;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * File metadata — the "control plane" record for each file.
 *
 * This mirrors the Dropbox design from the article:
 *   - fingerprint: SHA-256 hash of file content (for dedup + resumability)
 *   - status: UPLOADING → UPLOADED → DELETED
 *   - uploadedBy: the user who owns the file
 *   - blobName: the key in Azure Blob Storage where the actual bytes live
 *
 * In the article's deep dive, this also includes a `chunks` array tracking
 * per-chunk status. We track that via the ChunkStatus entity.
 */
@Entity
@Table(name = "file_metadata")
public class FileMetadata {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private String name;

    private long size;

    private String mimeType;

    @Column(nullable = false)
    private String blobName;

    /**
     * SHA-256 fingerprint of the entire file content.
     * Used for deduplication and resumable upload detection.
     */
    @Column(nullable = false, unique = true)
    private String fingerprint;

    /**
     * UPLOADING, UPLOADED, or DELETED
     */
    @Column(nullable = false)
    private String status;

    @Column(nullable = false)
    private UUID uploadedBy;

    private Instant createdAt;
    private Instant updatedAt;

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
        updatedAt = Instant.now();
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }

    // --- Constructors ---

    public FileMetadata() {}

    public FileMetadata(String name, long size, String mimeType, String blobName,
                        String fingerprint, String status, UUID uploadedBy) {
        this.name = name;
        this.size = size;
        this.mimeType = mimeType;
        this.blobName = blobName;
        this.fingerprint = fingerprint;
        this.status = status;
        this.uploadedBy = uploadedBy;
    }

    // --- Getters & Setters ---

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public long getSize() { return size; }
    public void setSize(long size) { this.size = size; }

    public String getMimeType() { return mimeType; }
    public void setMimeType(String mimeType) { this.mimeType = mimeType; }

    public String getBlobName() { return blobName; }
    public void setBlobName(String blobName) { this.blobName = blobName; }

    public String getFingerprint() { return fingerprint; }
    public void setFingerprint(String fingerprint) { this.fingerprint = fingerprint; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public UUID getUploadedBy() { return uploadedBy; }
    public void setUploadedBy(UUID uploadedBy) { this.uploadedBy = uploadedBy; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}