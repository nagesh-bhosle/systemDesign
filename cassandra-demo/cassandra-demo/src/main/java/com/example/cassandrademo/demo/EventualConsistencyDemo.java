package com.example.cassandrademo.demo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import com.example.cassandrademo.service.ConsistencyService;

@RestController
public class EventualConsistencyDemo {

    @Autowired
    private ConsistencyService consistencyService;

    @GetMapping("/eventual-consistency")
    public String demonstrateEventualConsistency() {
        // Simulate writes with different consistency levels
        String result = consistencyService.performEventualConsistencyDemo();
        return result;
    }
}