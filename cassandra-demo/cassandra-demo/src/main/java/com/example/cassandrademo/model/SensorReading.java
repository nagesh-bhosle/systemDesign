package com.example.cassandrademo.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.cassandra.core.mapping.Table;
import org.springframework.data.cassandra.core.mapping.Column;

import java.time.Instant;

@Table("sensor_readings")
public class SensorReading {

    @Id
    private String id;

    @Column("sensor_id")
    private String sensorId;

    @Column("temperature")
    private double temperature;

    @Column("humidity")
    private double humidity;

    @Column("timestamp")
    private Instant timestamp;

    public SensorReading() {
    }

    public SensorReading(String id, String sensorId, double temperature, double humidity, Instant timestamp) {
        this.id = id;
        this.sensorId = sensorId;
        this.temperature = temperature;
        this.humidity = humidity;
        this.timestamp = timestamp;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getSensorId() {
        return sensorId;
    }

    public void setSensorId(String sensorId) {
        this.sensorId = sensorId;
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

    public Instant getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }
}