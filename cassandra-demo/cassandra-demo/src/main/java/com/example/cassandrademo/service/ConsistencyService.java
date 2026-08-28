package com.example.cassandrademo.service;

import com.datastax.oss.driver.api.core.ConsistencyLevel;
import com.datastax.oss.driver.api.core.CqlSession;
import com.datastax.oss.driver.api.core.cql.SimpleStatement;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.UUID;

/**
 * A controlled, illustrative consistency experiment. It writes one row using a
 * chosen consistency level and reads it back with another, reporting both the
 * configured levels and the observed value. This is NOT a guarantee about
 * convergence behavior — it is a demo of the API surface.
 */
@Service
public class ConsistencyService {

    private final CqlSession session;

    public ConsistencyService(CqlSession session) {
        this.session = session;
    }

    public String performEventualConsistencyDemo() {
        String id = "cons-" + UUID.randomUUID();
        ConsistencyLevel writeLevel = ConsistencyLevel.QUORUM;
        ConsistencyLevel readLevel = ConsistencyLevel.ONE;
        try {
            session.execute(SimpleStatement.builder(
                            "INSERT INTO cassandra_demo.consistency_demo (id, value, written_at) VALUES (?, ?, ?)")
                    .addPositionalValues(id, "hello-from-" + writeLevel, Instant.now())
                    .setConsistencyLevel(writeLevel)
                    .build());

            var row = session.execute(SimpleStatement.builder(
                            "SELECT value FROM cassandra_demo.consistency_demo WHERE id = ?")
                    .addPositionalValue(id)
                    .setConsistencyLevel(readLevel)
                    .build())
                    .one();

            return "Wrote at " + writeLevel + ", read at " + readLevel
                    + ", observed value = " + (row == null ? "<not found>" : row.getString("value"));
        } catch (Exception e) {
            return "Consistency demo failed: " + e.getMessage();
        }
    }
}
