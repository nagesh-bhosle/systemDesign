package com.example.cassandrademo.demo;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.service.VersionedWriteService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/demo/clustering-order")
public class ClusteringOrderDemo {

    private final VersionedWriteService versionedWriteService;

    @Autowired
    public ClusteringOrderDemo(VersionedWriteService versionedWriteService) {
        this.versionedWriteService = versionedWriteService;
    }

    /**
     * Reads ONE partition (sensor) and returns its rows in physical clustering
     * order (newest timestamp first) — no ORDER BY needed.
     */
    @GetMapping("/sensor/{sensorId}")
    public List<SensorReading> readingsForSensor(@PathVariable String sensorId) {
        return versionedWriteService.findBySensorId(sensorId);
    }
}