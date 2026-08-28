package com.example.cassandrademo.service;

import com.datastax.oss.driver.api.core.CqlSession;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * NOTE: real Cassandra nodes cannot be added/removed by issuing CQL from an
 * application. This service therefore reports the REAL cluster status from the
 * driver, but node add/remove is an in-memory SIMULATION clearly labeled as such.
 */
@Service
public class ClusterService {

    private final CqlSession session;
    private final List<String> simulatedNodes = new ArrayList<>();

    public ClusterService(CqlSession session) {
        this.session = session;
    }

    /** Simulated only — returns the operation result text, does not touch the cluster. */
    public String addNode(String nodeIp) {
        if (simulatedNodes.contains(nodeIp)) {
            return "Simulated: node " + nodeIp + " already in the demo cluster.";
        }
        simulatedNodes.add(nodeIp);
        return "Simulated: node " + nodeIp + " added to the demo cluster (in-memory only).";
    }

    /** Simulated only — returns the operation result text, does not touch the cluster. */
    public String removeNode(String nodeIp) {
        if (simulatedNodes.remove(nodeIp)) {
            return "Simulated: node " + nodeIp + " removed from the demo cluster.";
        }
        return "Simulated: node " + nodeIp + " not present in the demo cluster.";
    }

    public String getClusterStatus() {
        String cluster = String.valueOf(session.getMetadata().getClusterName())
                .replaceAll("^Optional\\[(.*)\\]$", "$1");
        return "Connected to cluster: " + cluster
                + ", nodes: " + session.getMetadata().getNodes().size()
                + " | simulated nodes: " + simulatedNodes.size();
    }

    public List<String> getSimulatedNodes() {
        return Collections.unmodifiableList(simulatedNodes);
    }
}