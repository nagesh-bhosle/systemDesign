package com.example.cassandrademo.service;

import org.springframework.stereotype.Service;

/**
 * Explanatory partition-key helpers. Note: this deliberately does NOT expose
 * generic create/delete/update-by-arbitrary-identifier operations, because
 * interpolating client-supplied keyspace/table/column names into CQL is unsafe.
 */
@Service
public class PartitionService {

    public String getPartitionKeyInfo(String key) {
        // Explain how a partition key is hashed with Murmur3
        return "Partition key '" + key + "' is hashed (Murmur3) to determine token placement.";
    }

    public String partitionDemo() {
        // Demonstrates partition-key based routing
        return "Partition demo: rows sharing a partition key co-locate on the same node.";
    }
}