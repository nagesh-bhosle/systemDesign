package com.example.blobupload.controller;

import com.example.blobupload.service.BlobStorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/files")
public class FileUploadController {

    private static final Logger log = LoggerFactory.getLogger(FileUploadController.class);

    private final BlobStorageService blobStorageService;

    public FileUploadController(BlobStorageService blobStorageService) {
        this.blobStorageService = blobStorageService;
    }

    /**
     * Upload a single file via multipart/form-data.
     * The file is streamed to blob storage — never fully loaded in memory.
     *
     * curl -X POST http://localhost:8080/api/files/upload \
     *   -F "file=@/path/to/large-file.zip" \
     *   -F "blobName=optional-custom-name.zip"
     */
    @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<BlobStorageService.UploadResult> uploadFile(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "blobName", required = false) String blobName) throws Exception {

        if (file.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }

        log.info("Received upload request: filename={}, size={} bytes",
                file.getOriginalFilename(), file.getSize());

        BlobStorageService.UploadResult result = blobStorageService.uploadFile(file, blobName);
        return ResponseEntity.ok(result);
    }

    /**
     * Upload multiple files at once.
     *
     * curl -X POST http://localhost:8080/api/files/upload-batch \
     *   -F "files=@file1.zip" \
     *   -F "files=@file2.zip"
     */
    @PostMapping(value = "/upload-batch", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<List<BlobStorageService.UploadResult>> uploadBatch(
            @RequestParam("files") MultipartFile[] files) throws Exception {

        log.info("Received batch upload: {} files", files.length);

        List<BlobStorageService.UploadResult> results = new ArrayList<>();
        for (MultipartFile file : files) {
            if (!file.isEmpty()) {
                results.add(blobStorageService.uploadFile(file, null));
            }
        }
        return ResponseEntity.ok(results);
    }

    /**
     * List all uploaded blobs.
     */
    @GetMapping
    public ResponseEntity<List<BlobStorageService.BlobInfo>> listBlobs() {
        return ResponseEntity.ok(blobStorageService.listBlobs());
    }

    /**
     * Get info about a specific blob.
     */
    @GetMapping("/{blobName}")
    public ResponseEntity<BlobStorageService.BlobInfo> getBlobInfo(@PathVariable String blobName) {
        try {
            return ResponseEntity.ok(blobStorageService.getBlobInfo(blobName));
        } catch (Exception e) {
            log.error("Blob not found: {}", blobName, e);
            return ResponseEntity.notFound().build();
        }
    }

    /**
     * Download a blob (streams the data back).
     */
    @GetMapping("/{blobName}/download")
    public ResponseEntity<InputStreamResource> downloadBlob(@PathVariable String blobName) {
        try {
            InputStream stream = blobStorageService.downloadBlob(blobName);
            BlobStorageService.BlobInfo info = blobStorageService.getBlobInfo(blobName);

            return ResponseEntity.ok()
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                            "attachment; filename=\"" + blobName + "\"")
                    .contentLength(info.sizeBytes())
                    .body(new InputStreamResource(stream));
        } catch (Exception e) {
            log.error("Download failed for blob '{}'", blobName, e);
            return ResponseEntity.notFound().build();
        }
    }

    /**
     * Delete a blob.
     */
    @DeleteMapping("/{blobName}")
    public ResponseEntity<Map<String, Boolean>> deleteBlob(@PathVariable String blobName) {
        boolean deleted = blobStorageService.deleteBlob(blobName);
        return ResponseEntity.ok(Map.of("deleted", deleted));
    }

    /**
     * Health check endpoint.
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of(
                "status", "UP",
                "service", "blob-upload-demo"
        ));
    }
}