package com.example.cassandrademo.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.datastax.oss.driver.api.core.CqlSession;
import com.datastax.oss.driver.api.core.cql.SimpleStatement;

@Service
public class PartitionService {

    private final CqlSession session;

    @Autowired
    public PartitionService(CqlSession session) {
        this.session = session;
    }

    public void createPartition(String keyspace, String table, String partitionKey, String value) {
        String query = String.format("INSERT INTO %s.%s (%s) VALUES (?)", keyspace, table, partitionKey);
        session.execute(SimpleStatement.newInstance(query, value));
    }

    public void deletePartition(String keyspace, String table, String partitionKey, String value) {
        String query = String.format("DELETE FROM %s.%s WHERE %s = ?", keyspace, table, partitionKey);
        session.execute(SimpleStatement.newInstance(query, value));
    }

    public void updatePartition(String keyspace, String table, String partitionKey, String value, String newValue) {
        String query = String.format("UPDATE %s.%s SET value = ? WHERE %s = ?", keyspace, table, partitionKey);
        session.execute(SimpleStatement.newInstance(query, newValue, value));
    }

    public void readPartition(String keyspace, String table, String partitionKey, String value) {
        String query = String.format("SELECT * FROM %s.%s WHERE %s = ?", keyspace, table, partitionKey);
        session.execute(SimpleStatement.newInstance(query, value));
    }

    public String getPartitionKeyInfo(String key) {
        // Explain how a partition key is hashed with Murmur3
        return "Partition key '" + key + "' is hashed (Murmur3) to determine token placement.";
    }

    public String partitionDemo() {
        // Demonstrates partition-key based routing
        return "Partition demo: rows sharing a partition key co-locate on the same node.";
    }
}