package com.example.cassandrademo.demo;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.repository.SensorReadingRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class PartitionKeyDemo {

    @Autowired
    private SensorReadingRepository sensorReadingRepository;

    @GetMapping("/demo/partition-key")
    public List<SensorReading> getSensorReadingsByPartitionKey(@RequestParam String partitionKey) {
        return sensorReadingRepository.findAll();
    }

    // Additional methods to demonstrate partition key usage can be added here
}