package com.example.cassandrademo.model;

import org.springframework.data.cassandra.core.mapping.Column;
import org.springframework.data.cassandra.core.mapping.PrimaryKey;
import org.springframework.data.cassandra.core.mapping.Table;

import java.time.Instant;

@Table("sensor_readings")
public class SensorReading {

    @PrimaryKey
    private SensorReadingKey key;

    @Column("temperature")
    private double temperature;

    @Column("humidity")
    private double humidity;

    public SensorReading() {
    }

    public SensorReading(SensorReadingKey key, double temperature, double humidity) {
        this.key = key;
        this.temperature = temperature;
        this.humidity = humidity;
    }

    public SensorReadingKey getKey() {
        return key;
    }

    public void setKey(SensorReadingKey key) {
        this.key = key;
    }

    public double getTemperature() {
        return temperature;
    }

    public void setTemperature(double temperature) {
        this.temperature = temperature;
    }

    public double getHumidity() {
        return humidity;
    }

    public void setHumidity(double humidity) {
        this.humidity = humidity;
    }

    // Convenience accessors so templates/JSON stay readable without touching key.getX().

    public String getSensorId() {
        return key == null ? null : key.getSensorId();
    }

    public String getId() {
        return key == null ? null : key.getId();
    }

    public Instant getTimestamp() {
        return key == null ? null : key.getTimestamp();
    }
}