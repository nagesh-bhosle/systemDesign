package com.example.cassandrademo.service;

import org.springframework.stereotype.Service;

import java.util.concurrent.atomic.AtomicLong;

@Service
public class SnowflakeIdService {
    private final long epoch = 1609459200000L; // Custom epoch (January 1, 2021)
    private final AtomicLong sequence = new AtomicLong(0);
    private final long sequenceBits = 12; // Sequence bits
    private final long maxSequence = ~(-1L << sequenceBits); // Max sequence value
    private long lastTimestamp = -1L;

    public synchronized long generateId() {
        long timestamp = System.currentTimeMillis();

        if (timestamp < lastTimestamp) {
            throw new RuntimeException("Clock moved backwards. Refusing to generate id for " + (lastTimestamp - timestamp) + " milliseconds");
        }

        if (lastTimestamp == timestamp) {
            sequence.compareAndSet(maxSequence, 0);
        } else {
            sequence.set(0);
        }

        lastTimestamp = timestamp;

        return ((timestamp - epoch) << sequenceBits) | sequence.getAndIncrement();
    }

    public com.example.cassandrademo.model.SnowflakeId generateSnowflakeId() {
        long id = generateId();
        return new com.example.cassandrademo.model.SnowflakeId(id, 1L, id & maxSequence);
    }

    public java.util.List<com.example.cassandrademo.model.SnowflakeId> generateBatchSnowflakeIds(int count) {
        java.util.List<com.example.cassandrademo.model.SnowflakeId> ids = new java.util.ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            ids.add(generateSnowflakeId());
        }
        return ids;
    }
}