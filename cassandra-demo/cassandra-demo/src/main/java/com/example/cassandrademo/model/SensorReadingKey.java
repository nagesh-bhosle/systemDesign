package com.example.cassandrademo.model;

import org.springframework.data.cassandra.core.cql.PrimaryKeyType;
import org.springframework.data.cassandra.core.mapping.PrimaryKeyClass;
import org.springframework.data.cassandra.core.mapping.PrimaryKeyColumn;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;

/**
 * Composite primary key for sensor_readings.
 * <ul>
 *   <li>sensor_id  -> PARTITION key (all rows for one sensor live in one partition)</li>
 *   <li>timestamp  -> CLUSTERING key (rows physically ordered newest-first)</li>
 *   <li>id         -> CLUSTERING key (disambiguates same-millisecond reads)</li>
 * </ul>
 */
@PrimaryKeyClass
public class SensorReadingKey implements Serializable {

    @PrimaryKeyColumn(name = "sensor_id", type = PrimaryKeyType.PARTITIONED, ordinal = 0)
    private String sensorId;

    @PrimaryKeyColumn(name = "timestamp", type = PrimaryKeyType.CLUSTERED, ordinal = 1)
    private Instant timestamp;

    @PrimaryKeyColumn(name = "id", type = PrimaryKeyType.CLUSTERED, ordinal = 2)
    private String id;

    public SensorReadingKey() {
    }

    public SensorReadingKey(String sensorId, Instant timestamp, String id) {
        this.sensorId = sensorId;
        this.timestamp = timestamp;
        this.id = id;
    }

    public String getSensorId() {
        return sensorId;
    }

    public void setSensorId(String sensorId) {
        this.sensorId = sensorId;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (o == null || getClass() != o.getClass()) {
            return false;
        }
        SensorReadingKey that = (SensorReadingKey) o;
        return Objects.equals(sensorId, that.sensorId)
                && Objects.equals(timestamp, that.timestamp)
                && Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(sensorId, timestamp, id);
    }

    @Override
    public String toString() {
        return "SensorReadingKey{" + "sensorId='" + sensorId + '\''
                + ", timestamp=" + timestamp
                + ", id='" + id + '\'' + '}';
    }
}
