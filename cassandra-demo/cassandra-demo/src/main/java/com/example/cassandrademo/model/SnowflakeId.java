package com.example.cassandrademo.model;

import java.time.Instant;

public class SnowflakeId {
    private long id;
    private long timestamp;
    private long workerId;
    private long sequence;

    public SnowflakeId(long id, long workerId, long sequence) {
        this.id = id;
        this.timestamp = Instant.now().toEpochMilli();
        this.workerId = workerId;
        this.sequence = sequence;
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

    @Override
    public String toString() {
        return "SnowflakeId{" +
                "id=" + id +
                ", timestamp=" + timestamp +
                ", workerId=" + workerId +
                ", sequence=" + sequence +
                '}';
    }
}