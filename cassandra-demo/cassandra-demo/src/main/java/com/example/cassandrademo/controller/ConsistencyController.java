package com.example.cassandrademo.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/consistency")
public class ConsistencyController {

    @GetMapping
    public String getConsistencyInfo() {
        return "This endpoint provides information about eventual consistency and replication factors in Cassandra.";
    }

    @GetMapping("/replication-factor")
    public String getReplicationFactor() {
        return "Replication factor determines how many copies of data are stored across the cluster.";
    }

    @GetMapping("/eventual-consistency")
    public String getEventualConsistency() {
        return "Cassandra provides eventual consistency, meaning that updates will propagate to all replicas eventually.";
    }
}