package com.example.cassandrademo.demo;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.service.VersionedWriteService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
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

    @GetMapping("/all")
    public List<SensorReading> allReadings() {
        // Rows within a partition are stored in clustering order
        return versionedWriteService.findAll();
    }
}