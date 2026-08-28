package com.example.cassandrademo.controller;

import com.example.cassandrademo.service.PartitionService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PartitionController {

    private final PartitionService partitionService;

    @Autowired
    public PartitionController(PartitionService partitionService) {
        this.partitionService = partitionService;
    }

    @GetMapping("/partition/key")
    public String getPartitionKey(@RequestParam String key) {
        return partitionService.getPartitionKeyInfo(key);
    }

    @GetMapping("/partition/demo")
    public String partitionDemo() {
        return partitionService.partitionDemo();
    }
}