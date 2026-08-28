package com.example.cassandrademo.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.datastax.oss.driver.api.core.CqlSession;

@Service
public class ClusterService {

    private final CqlSession session;

    @Autowired
    public ClusterService(CqlSession session) {
        this.session = session;
    }

    public void addNode(String nodeIp) {
        // Logic to add a node to the Cassandra cluster
        // This typically involves updating the Cassandra configuration
        // and using the appropriate CQL commands to join the cluster
    }

    public void removeNode(String nodeIp) {
        // Logic to remove a node from the Cassandra cluster
        // This typically involves updating the Cassandra configuration
        // and using the appropriate CQL commands to remove the node
    }

    public void scaleCluster(int newSize) {
        // Logic to scale the cluster to a new size
        // This could involve adding or removing nodes based on the new size
    }

    public void displayClusterTopology() {
        // Logic to display the current cluster topology
        // This could involve querying the system tables in Cassandra
    }

    public String getClusterStatus() {
        // Basic status info from the live CQL session
        return "Connected to cluster: " + session.getMetadata().getClusterName()
                + ", nodes: " + session.getMetadata().getNodes().size();
    }
}