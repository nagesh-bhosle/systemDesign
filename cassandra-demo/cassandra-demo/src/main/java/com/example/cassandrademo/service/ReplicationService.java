package com.example.cassandrademo.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.datastax.oss.driver.api.core.CqlSession;

@Service
public class ReplicationService {

    private final CqlSession session;

    @Autowired
    public ReplicationService(CqlSession session) {
        this.session = session;
    }

    public void configureReplication(String keyspace, int replicationFactor) {
        String query = String.format(
            "CREATE KEYSPACE IF NOT EXISTS %s WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : %d };",
            keyspace, replicationFactor);
        session.execute(query);
    }

    public void updateReplicationFactor(String keyspace, int newReplicationFactor) {
        String query = String.format(
            "ALTER KEYSPACE %s WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : %d };",
            keyspace, newReplicationFactor);
        session.execute(query);
    }

    public void dropKeyspace(String keyspace) {
        String query = String.format("DROP KEYSPACE IF EXISTS %s;", keyspace);
        session.execute(query);
    }
}