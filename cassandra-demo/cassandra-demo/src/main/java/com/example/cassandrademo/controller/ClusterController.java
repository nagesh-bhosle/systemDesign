package com.example.cassandrademo.controller;

import com.example.cassandrademo.service.ClusterService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/cluster")
public class ClusterController {

    private final ClusterService clusterService;

    @Autowired
    public ClusterController(ClusterService clusterService) {
        this.clusterService = clusterService;
    }

    @PostMapping("/addNode")
    public String addNode(@RequestParam String nodeAddress) {
        return clusterService.addNode(nodeAddress);
    }

    @PostMapping("/removeNode")
    public String removeNode(@RequestParam String nodeAddress) {
        return clusterService.removeNode(nodeAddress);
    }

    @GetMapping("/status")
    public String getClusterStatus() {
        return clusterService.getClusterStatus();
    }
}