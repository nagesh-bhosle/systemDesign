package com.example.cassandrademo.demo;

import com.example.cassandrademo.model.SensorReading;
import com.example.cassandrademo.service.VersionedWriteService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/write-support")
public class WriteSupportDemo {

    private final VersionedWriteService versionedWriteService;

    @Autowired
    public WriteSupportDemo(VersionedWriteService versionedWriteService) {
        this.versionedWriteService = versionedWriteService;
    }

    @PostMapping("/add")
    public SensorReading addSensorReading(@RequestBody SensorReading sensorReading) {
        return versionedWriteService.save(sensorReading);
    }

    @GetMapping("/all")
    public List<SensorReading> getAllSensorReadings() {
        return versionedWriteService.findAll();
    }

    @GetMapping("/latest/{id}")
    public SensorReading getLatestReading(@PathVariable String id) {
        return versionedWriteService.findLatestById(id);
    }

    @PutMapping("/update")
    public SensorReading updateSensorReading(@RequestBody SensorReading sensorReading) {
        return versionedWriteService.update(sensorReading);
    }
}