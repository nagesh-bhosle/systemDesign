package com.example.cassandrademo.repository;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.model.SensorReadingKey;
import org.springframework.data.cassandra.repository.CassandraRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface SensorReadingRepository extends CassandraRepository<SensorReading, SensorReadingKey> {

    /**
     * Bounded partition-key query: all readings for one sensor, newest first
     * (clustering order of the table).
     */
    List<SensorReading> findByKeySensorId(String sensorId);
}