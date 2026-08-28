package com.example.cassandrademo.config;

import com.datastax.oss.driver.api.core.CqlSession;
import com.datastax.oss.driver.api.core.metadata.Metadata;
import com.datastax.oss.driver.api.core.metadata.Node;
import com.datastax.oss.driver.api.core.metadata.NodeState;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.stereotype.Component;

import java.util.Collection;

/**
 * Reports Cassandra reachability to Spring Boot Actuator so Docker/CI can
 * wait on /actuator/health instead of guessing a sleep duration.
 */
@Component
public class CassandraHealthIndicator implements HealthIndicator {

    private final CqlSession session;

    public CassandraHealthIndicator(CqlSession session) {
        this.session = session;
    }

    @Override
    public Health health() {
        try {
            if (session == null || session.isClosed()) {
                return Health.down().withDetail("session", "closed").build();
            }
            Metadata metadata = session.getMetadata();
            Collection<Node> nodes = metadata.getNodes() == null
                    ? java.util.Collections.emptyList()
                    : metadata.getNodes().values();
            long up = nodes.stream()
                    .filter(n -> n.getState() == NodeState.UP)
                    .count();
            String cluster = String.valueOf(metadata.getClusterName())
                    .replaceAll("^Optional\\[(.*)\\]$", "$1");
            if (up > 0) {
                return Health.up()
                        .withDetail("cluster", cluster)
                        .withDetail("nodes", up)
                        .build();
            }
            return Health.down()
                    .withDetail("cluster", cluster)
                    .withDetail("nodes", nodes.size())
                    .build();
        } catch (Exception e) {
            return Health.down(e).build();
        }
    }
}
