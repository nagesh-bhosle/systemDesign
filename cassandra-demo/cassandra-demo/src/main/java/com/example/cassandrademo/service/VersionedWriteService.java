package com.example.cassandrademo.service;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.model.SensorReadingKey;
import com.example.cassandrademo.repository.SensorReadingRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * "Versioned" writes in Cassandra are, at their core, last-write-wins upserts:
 * every {@code save} for the same primary key overwrites the previous value,
 * and a read returns whichever write carried the highest timestamp.
 */
@Service
public class VersionedWriteService {

    private final SensorReadingRepository sensorReadingRepository;

    @Autowired
    public VersionedWriteService(SensorReadingRepository sensorReadingRepository) {
        this.sensorReadingRepository = sensorReadingRepository;
    }

    public SensorReading save(SensorReading sensorReading) {
        return sensorReadingRepository.save(sensorReading);
    }

    public List<SensorReading> findAll() {
        return sensorReadingRepository.findAll();
    }

    /** All readings for one sensor partition, newest-first (clustering order). */
    public List<SensorReading> findBySensorId(String sensorId) {
        return sensorReadingRepository.findByKeySensorId(sensorId);
    }

    public SensorReading findLatestById(SensorReadingKey key) {
        return sensorReadingRepository.findById(key).orElse(null);
    }

    public SensorReading update(SensorReading sensorReading) {
        // Same primary key => upsert. The latest write wins.
        return sensorReadingRepository.save(sensorReading);
    }
}