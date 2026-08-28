package com.example.cassandrademo.service;

import org.springframework.stereotype.Service;

@Service
public class ConsistencyService {

    public String performEventualConsistencyDemo() {
        // Simulates writes at low consistency and later reads
        return "Eventual consistency demo: write at QUORUM, read at ONE - "
                + "replicas converge once hinted handoff completes.";
    }
}
