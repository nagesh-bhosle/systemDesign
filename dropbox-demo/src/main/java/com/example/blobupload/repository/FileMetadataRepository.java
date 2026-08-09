package com.example.blobupload.repository;

import com.example.blobupload.entity.FileMetadata;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FileMetadataRepository extends JpaRepository<FileMetadata, UUID> {

    Optional<FileMetadata> findByFingerprint(String fingerprint);

    List<FileMetadata> findByUploadedBy(UUID uploadedBy);

    /**
     * Find all files owned by or shared with a user that changed after a timestamp.
     * Used by the sync API: GET /files/changes?since={timestamp}
     */
    List<FileMetadata> findByUploadedByAndUpdatedAtAfter(UUID uploadedBy, Instant after);
}