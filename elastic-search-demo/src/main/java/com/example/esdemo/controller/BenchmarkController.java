package com.example.esdemo.controller;

import com.example.esdemo.dto.BenchmarkResult;
import com.example.esdemo.service.BenchmarkService;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/benchmark")
@CrossOrigin(origins = "*")
public class BenchmarkController {

    private final BenchmarkService benchmarkService;

    public BenchmarkController(BenchmarkService benchmarkService) {
        this.benchmarkService = benchmarkService;
    }

    @GetMapping("/text")
    public BenchmarkResult text(
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String category,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return benchmarkService.benchmarkText(q, category, page, size);
    }

    @GetMapping("/geo")
    public BenchmarkResult geo(
            @RequestParam double lat,
            @RequestParam double lon,
            @RequestParam(defaultValue = "1000") double radius,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String category,
            @RequestParam(required = false, defaultValue = "rating") String sortBy,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return benchmarkService.benchmarkGeo(lat, lon, radius, q, category, sortBy, page, size);
    }

    @GetMapping("/combined")
    public BenchmarkResult combined(
            @RequestParam(required = false) String q,
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lon,
            @RequestParam(required = false) Double radius,
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String sortBy,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return benchmarkService.benchmarkCombined(q, lat, lon, radius, category, sortBy, page, size);
    }
}
