package com.example.cassandrademo.model;

import java.time.Instant;

public class SnowflakeId {
    private final long id;
    private final long timestamp;
    private final long workerId;
    private final long sequence;

    public SnowflakeId(long id, long workerId, long sequence, long timestampMillis) {
        this.id = id;
        this.workerId = workerId;
        this.sequence = sequence;
        this.timestamp = timestampMillis;
    }

    public long getId() {
        return id;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public long getWorkerId() {
        return workerId;
    }

    public long getSequence() {
        return sequence;
    }

    public String getTimestampIso() {
        return Instant.ofEpochMilli(timestamp).toString();
    }

    @Override
    public String toString() {
        return "SnowflakeId{" +
                "id=" + id +
                ", timestamp=" + Instant.ofEpochMilli(timestamp) +
                ", workerId=" + workerId +
                ", sequence=" + sequence +
                '}';
    }
}