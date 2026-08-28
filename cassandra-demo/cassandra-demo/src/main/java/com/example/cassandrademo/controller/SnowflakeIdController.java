package com.example.cassandrademo.controller;

import com.example.cassandrademo.service.SnowflakeIdService;
import com.example.cassandrademo.model.SnowflakeId;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class SnowflakeIdController {

    @Autowired
    private SnowflakeIdService snowflakeIdService;

    @GetMapping("/snowflake/generate")
    public SnowflakeId generateSnowflakeId() {
        return snowflakeIdService.generateSnowflakeId();
    }

    @GetMapping("/snowflake/generateBatch")
    public List<SnowflakeId> generateBatchSnowflakeIds(@RequestParam(defaultValue = "5") int count) {
        int safe = Math.max(1, Math.min(count, 1000));
        return snowflakeIdService.generateBatchSnowflakeIds(safe);
    }

    @GetMapping("/snowflake/demo")
    public String demoSnowflakeId() {
        return "Snowflake ID generation is based on a unique combination of timestamp, machine ID, and sequence number.";
    }
}