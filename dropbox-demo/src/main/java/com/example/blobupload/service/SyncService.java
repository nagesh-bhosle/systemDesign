package com.example.blobupload.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Sync service using Server-Sent Events (SSE).
 *
 * From the article:
 *   "Each client maintains a single WebSocket (or SSE) connection to the server,
 *    not one per file, but one per device/session. Through this connection,
 *    the server pushes change notifications for files the user has access to."
 *
 * Hybrid approach:
 *   1. Active notification: Server pushes change events through SSE in real-time
 *   2. Periodic polling as a safety net: GET /files/changes?since={timestamp}
 *
 * We use SSE instead of WebSocket because:
 *   - SSE is simpler (one-way server→client, which is all we need for notifications)
 *   - SSE works over standard HTTP (no upgrade needed)
 *   - SSE has built-in reconnection
 */
@Service
public class SyncService {

    private static final Logger log = LoggerFactory.getLogger(SyncService.class);
    private static final long SSE_TIMEOUT = 10 * 60 * 1000L; // 10 minutes

    /**
     * Map of userId → SseEmitter (one per active device/session).
     * In production, a user could have multiple emitters (one per device).
     */
    private final Map<UUID, SseEmitter> emitters = new ConcurrentHashMap<>();

    /**
     * Register a new SSE connection for a user.
     */
    public SseEmitter register(UUID userId) {
        SseEmitter emitter = new SseEmitter(SSE_TIMEOUT);

        emitters.put(userId, emitter);

        emitter.onCompletion(() -> {
            log.info("SSE connection completed for user {}", userId);
            emitters.remove(userId);
        });

        emitter.onTimeout(() -> {
            log.info("SSE connection timed out for user {}", userId);
            emitters.remove(userId);
        });

        emitter.onError(e -> {
            log.error("SSE error for user {}: {}", userId, e.getMessage());
            emitters.remove(userId);
        });

        // Send an initial connection event
        try {
            emitter.send(SseEmitter.event()
                    .name("connected")
                    .data(Map.of("userId", userId.toString(), "message", "SSE connection established")));
        } catch (IOException e) {
            log.error("Failed to send initial SSE event", e);
        }

        log.info("SSE connection registered for user {}", userId);
        return emitter;
    }

    /**
     * Push a change notification to a user.
     *
     * From the article:
     *   "Active notification: The server pushes change events through the
     *    WebSocket connection in real-time as they happen."
     */
    public void notifyChange(UUID userId, DropboxFileService.ChangeEvent event) {
        SseEmitter emitter = emitters.get(userId);
        if (emitter == null) {
            log.debug("No active SSE connection for user {} — change will be picked up via polling", userId);
            return;
        }

        try {
            emitter.send(SseEmitter.event()
                    .name("file-change")
                    .data(event));
            log.info("Pushed change notification to user {}: file={}", userId, event.name());
        } catch (IOException e) {
            log.error("Failed to push SSE notification to user {}: {}", userId, e.getMessage());
            emitters.remove(userId);
        }
    }

    /**
     * Push a notification to all users who have access to a file
     * (owner + all shared users).
     */
    public void notifyFileChange(UUID ownerId, java.util.List<UUID> sharedUserIds,
                                  DropboxFileService.ChangeEvent event) {
        notifyChange(ownerId, event);
        for (UUID sharedUserId : sharedUserIds) {
            notifyChange(sharedUserId, event);
        }
    }
}