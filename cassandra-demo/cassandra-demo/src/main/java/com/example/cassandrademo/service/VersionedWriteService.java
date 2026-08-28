package com.example.cassandrademo.service;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.repository.SensorReadingRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;

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

    public SensorReading findLatestById(String id) {
        return sensorReadingRepository.findById(id).orElse(null);
    }

    public SensorReading update(SensorReading sensorReading) {
        return sensorReadingRepository.save(sensorReading);
    }
}