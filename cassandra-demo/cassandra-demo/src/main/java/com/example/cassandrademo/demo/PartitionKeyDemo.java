package com.example.cassandrademo.demo;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.service.VersionedWriteService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class PartitionKeyDemo {

    private final VersionedWriteService versionedWriteService;

    @Autowired
    public PartitionKeyDemo(VersionedWriteService versionedWriteService) {
        this.versionedWriteService = versionedWriteService;
    }

    /**
     * Real partition-key query: reads a single sensor's partition via its
     * partition key (sensor_id). Bounded to one partition — no full scan.
     */
    @GetMapping("/demo/partition-key")
    public List<SensorReading> getSensorReadingsByPartitionKey(@RequestParam String partitionKey) {
        return versionedWriteService.findBySensorId(partitionKey);
    }
}