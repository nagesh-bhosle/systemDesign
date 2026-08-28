package com.example.cassandrademo.demo;

import com.example.cassandrademo.service.ClusterService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/demo/node-scaling")
public class NodeScalingDemo {

    private final ClusterService clusterService;

    @Autowired
    public NodeScalingDemo(ClusterService clusterService) {
        this.clusterService = clusterService;
    }

    @PostMapping("/add-node")
    public String addNode(@RequestParam String nodeIp) {
        return clusterService.addNode(nodeIp);
    }

    @PostMapping("/remove-node")
    public String removeNode(@RequestParam String nodeIp) {
        return clusterService.removeNode(nodeIp);
    }

    @GetMapping("/status")
    public String getClusterStatus() {
        return clusterService.getClusterStatus();
    }
}