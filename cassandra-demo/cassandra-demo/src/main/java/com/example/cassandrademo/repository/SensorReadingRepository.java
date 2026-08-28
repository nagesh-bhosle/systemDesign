package com.example.cassandrademo.repository;

import com.example.cassandrademo.model.SensorReading;
import org.springframework.data.cassandra.repository.CassandraRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface SensorReadingRepository extends CassandraRepository<SensorReading, String> {
    // Additional query methods can be defined here if needed
}