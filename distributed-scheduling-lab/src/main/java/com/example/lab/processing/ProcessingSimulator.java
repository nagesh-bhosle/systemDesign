package com.example.lab.processing;

import com.example.lab.domain.Message;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.concurrent.ThreadLocalRandom;

/**
 * Simulates downstream work by sleeping a random 500-1500ms (configurable via
 * lab.processing-delay-min-ms / lab.processing-delay-max-ms).
 *
 * Script D hook: if lab.slow-message-id is set and matches the message id,
 * sleep 40s — longer than any lease — so the claim expires, another instance
 * reprocesses and completes the message, and the original instance's late
 * completion is rejected by the guarded write (LATE_WRITE_REJECTED).
 */
@Component
public class ProcessingSimulator {

    private static final Logger log = LoggerFactory.getLogger(ProcessingSimulator.class);
    private static final long SLOW_MESSAGE_SLEEP_MS = 40_000;

    private final long minDelayMs;
    private final long maxDelayMs;
    private final Long slowMessageId;

    public ProcessingSimulator(@Value("${lab.processing-delay-min-ms:500}") long minDelayMs,
                               @Value("${lab.processing-delay-max-ms:1500}") long maxDelayMs,
                               @Value("${lab.slow-message-id:}") String slowMessageId) {
        this.minDelayMs = minDelayMs;
        this.maxDelayMs = Math.max(minDelayMs, maxDelayMs);
        this.slowMessageId = parseSlowMessageId(slowMessageId);
    }

    public void process(Message m) throws InterruptedException {
        long sleepMs = ThreadLocalRandom.current().nextLong(minDelayMs, maxDelayMs + 1);
        if (slowMessageId != null && slowMessageId.equals(m.getId())) {
            log.info("message {} is the configured slow message — sleeping {}ms (beyond any lease)",
                    m.getId(), SLOW_MESSAGE_SLEEP_MS);
            sleepMs = SLOW_MESSAGE_SLEEP_MS;
        }
        Thread.sleep(sleepMs);
    }

    private static Long parseSlowMessageId(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            return Long.parseLong(raw.trim());
        } catch (NumberFormatException ex) {
            log.warn("lab.slow-message-id '{}' is not a number — ignoring", raw);
            return null;
        }
    }
}
