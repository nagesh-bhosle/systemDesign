package com.example.cassandrademo.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SqlVsCqlDemo {

    @GetMapping("/sql-vs-cql")
    public String compareSqlAndCql() {
        return "SQL vs CQL: CQL has no JOINs, requires a primary key per table, "
                + "supports WHERE only on partition/clustering keys, and orders rows "
                + "by clustering columns defined in the schema.";
    }
}