package com.example.blobupload.entity;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * Simplified user entity for the Dropbox-like demo.
 * In production this would have password hashing, OAuth tokens, etc.
 */
@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String name;

    private Instant createdAt;

    @PrePersist
    void prePersist() {
        if (createdAt == null) createdAt = Instant.now();
    }

    // --- Constructors ---

    public User() {}

    public User(String email, String name) {
        this.email = email;
        this.name = name;
    }

    // --- Getters & Setters ---

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
}