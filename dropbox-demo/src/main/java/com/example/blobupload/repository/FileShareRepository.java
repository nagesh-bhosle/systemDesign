package com.example.blobupload.repository;

import com.example.blobupload.entity.FileShare;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface FileShareRepository extends JpaRepository<FileShare, UUID> {

    List<FileShare> findByFileId(UUID fileId);

    List<FileShare> findBySharedWithUserId(UUID userId);

    boolean existsByFileIdAndSharedWithUserId(UUID fileId, UUID userId);
}