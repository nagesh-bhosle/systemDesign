package com.example.blobupload.entity;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * Maps files to users who have access (sharing).
 *
 * From the article:
 *   "Great Solution: Create a separate table for shares"
 *
 * This is our ACL (Access Control List). The owner is always implicitly
 * granted access — we don't store an explicit row for the owner.
 */
@Entity
@Table(name = "file_shares")
public class FileShare {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private UUID fileId;

    @Column(nullable = false)
    private UUID sharedWithUserId;

    @Column(nullable = false)
    private UUID sharedByUserId;

    private Instant sharedAt;

    @PrePersist
    void prePersist() {
        if (sharedAt == null) sharedAt = Instant.now();
    }

    // --- Constructors ---

    public FileShare() {}

    public FileShare(UUID fileId, UUID sharedWithUserId, UUID sharedByUserId) {
        this.fileId = fileId;
        this.sharedWithUserId = sharedWithUserId;
        this.sharedByUserId = sharedByUserId;
    }

    // --- Getters & Setters ---

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }

    public UUID getFileId() { return fileId; }
    public void setFileId(UUID fileId) { this.fileId = fileId; }

    public UUID getSharedWithUserId() { return sharedWithUserId; }
    public void setSharedWithUserId(UUID sharedWithUserId) { this.sharedWithUserId = sharedWithUserId; }

    public UUID getSharedByUserId() { return sharedByUserId; }
    public void setSharedByUserId(UUID sharedByUserId) { this.sharedByUserId = sharedByUserId; }

    public Instant getSharedAt() { return sharedAt; }
    public void setSharedAt(Instant sharedAt) { this.sharedAt = sharedAt; }
}