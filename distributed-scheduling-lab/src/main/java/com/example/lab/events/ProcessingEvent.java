package com.example.lab.events;

import com.example.lab.domain.Message;

import java.time.Instant;

/**
 * One immutable fact about the processing pipeline, broadcast to all connected
 * dashboards over SSE.
 *
 * Kinds: RECEIVED | CLAIMED | COMPLETED | LATE_WRITE_REJECTED | REQUEUED |
 * INSTANCE_KILLED | INSTANCE_REVIVED.
 *
 * Note: the spec's 5-field record has no home for the REQUEUED batch count, so
 * an extra nullable {@code count} component was appended (null for every other
 * kind). Field order of the spec is preserved.
 */
public record ProcessingEvent(
        String kind,
        Long messageId,
        String messageType,
        String instance,    // null for RECEIVED
        Instant at,
        Integer count       // only set for REQUEUED (number of lease-expired rows)
) {
    public static ProcessingEvent received(Message m) {
        return new ProcessingEvent("RECEIVED", m.getId(), m.getType().name(), null, Instant.now(), null);
    }

    public static ProcessingEvent claimed(Message m, String inst) {
        return new ProcessingEvent("CLAIMED", m.getId(), m.getType().name(), inst, Instant.now(), null);
    }

    public static ProcessingEvent completed(Message m, String inst) {
        return new ProcessingEvent("COMPLETED", m.getId(), m.getType().name(), inst, Instant.now(), null);
    }

    public static ProcessingEvent lateWriteRejected(Message m, String inst) {
        return new ProcessingEvent("LATE_WRITE_REJECTED", m.getId(), m.getType().name(), inst, Instant.now(), null);
    }

    public static ProcessingEvent requeued(int requeuedCount) {
        return new ProcessingEvent("REQUEUED", null, null, null, Instant.now(), requeuedCount);
    }

    public static ProcessingEvent instanceKilled(String inst) {
        return new ProcessingEvent("INSTANCE_KILLED", null, null, inst, Instant.now(), null);
    }

    public static ProcessingEvent instanceRevived(String inst) {
        return new ProcessingEvent("INSTANCE_REVIVED", null, null, inst, Instant.now(), null);
    }
}
