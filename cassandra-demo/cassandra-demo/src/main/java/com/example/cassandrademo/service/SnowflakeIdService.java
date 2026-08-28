package com.example.cassandrademo.service;

import com.example.cassandrademo.model.SnowflakeId;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Standard Snowflake layout (64-bit signed):
 * <pre>
 *   41 bits timestamp (ms since epoch) | 10 bits worker | 12 bits sequence
 * </pre>
 * Uniqueness holds for one configured worker per JVM. Distributed deployments
 * need a shared worker-id registry — out of scope for this demo.
 */
@Service
public class SnowflakeIdService {

    private static final long EPOCH = 1609459200000L; // 2021-01-01T00:00:00Z
    private static final long SEQUENCE_BITS = 12L;
    private static final long WORKER_BITS = 10L;
    private static final long MAX_SEQUENCE = ~(-1L << SEQUENCE_BITS);
    private static final long MAX_WORKER = ~(-1L << WORKER_BITS);

    private final long workerId;
    private final AtomicLong sequence = new AtomicLong(0);
    private long lastTimestamp = -1L;

    public SnowflakeIdService(@Value("${snowflake.worker-id:1}") long workerId) {
        if (workerId < 0 || workerId > MAX_WORKER) {
            throw new IllegalArgumentException(
                    "snowflake.worker-id must be between 0 and " + MAX_WORKER + ", got " + workerId);
        }
        this.workerId = workerId;
    }

    public synchronized long generateId() {
        long timestamp = System.currentTimeMillis();

        if (timestamp < lastTimestamp) {
            long drift = lastTimestamp - timestamp;
            if (drift > 5000) {
                throw new IllegalStateException(
                        "Clock moved backwards by " + drift + " ms; refusing to generate ids");
            }
            // Small backwards drift: wait until the clock catches up.
            do {
                timestamp = System.currentTimeMillis();
            } while (timestamp < lastTimestamp);
        }

        if (lastTimestamp == timestamp) {
            long seq = sequence.incrementAndGet() & MAX_SEQUENCE;
            if (seq == 0) {
                // Sequence exhausted within this millisecond: wait for the next one.
                timestamp = waitNextMillis(lastTimestamp);
            }
        } else {
            sequence.set(0);
        }

        lastTimestamp = timestamp;

        return ((timestamp - EPOCH) << (WORKER_BITS + SEQUENCE_BITS))
                | (workerId << SEQUENCE_BITS)
                | sequence.get();
    }

    private long waitNextMillis(long current) {
        long timestamp = System.currentTimeMillis();
        while (timestamp <= current) {
            timestamp = System.currentTimeMillis();
        }
        return timestamp;
    }

    public SnowflakeId generateSnowflakeId() {
        long id = generateId();
        long timestamp = (id >> (WORKER_BITS + SEQUENCE_BITS)) + EPOCH;
        long worker = (id >> SEQUENCE_BITS) & MAX_WORKER;
        long seq = id & MAX_SEQUENCE;
        return new SnowflakeId(id, worker, seq, timestamp);
    }

    public List<SnowflakeId> generateBatchSnowflakeIds(int count) {
        List<SnowflakeId> ids = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            ids.add(generateSnowflakeId());
        }
        return ids;
    }
}