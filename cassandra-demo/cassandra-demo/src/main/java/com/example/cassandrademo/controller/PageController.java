package com.example.cassandrademo.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * Serves the demo pages (Thymeleaf templates).
 * Named /pages/* to avoid clashing with the /consistency REST controller.
 */
@Controller
public class PageController {

    @GetMapping("/pages/partitioning")
    public String partitioning() { return "partitioning"; }

    @GetMapping("/pages/clustering")
    public String clustering() { return "clustering"; }

    @GetMapping("/pages/cluster-topology")
    public String clusterTopology() { return "cluster-topology"; }

    @GetMapping("/pages/consistency")
    public String consistency() { return "consistency"; }

    @GetMapping("/pages/snowflake")
    public String snowflake() { return "snowflake"; }

    @GetMapping("/pages/versioned-writes")
    public String versionedWrites() { return "versioned-writes"; }

    @GetMapping("/pages/sql-vs-cql")
    public String sqlVsCql() { return "sql-vs-cql"; }
}
