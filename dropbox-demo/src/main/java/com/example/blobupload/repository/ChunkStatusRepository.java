package com.example.blobupload.repository;

import com.example.blobupload.entity.ChunkStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface ChunkStatusRepository extends JpaRepository<ChunkStatus, UUID> {

    List<ChunkStatus> findByFileIdOrderByPartNumberAsc(UUID fileId);

    List<ChunkStatus> findByFileIdAndStatus(UUID fileId, String status);

    long countByFileIdAndStatus(UUID fileId, String status);
}