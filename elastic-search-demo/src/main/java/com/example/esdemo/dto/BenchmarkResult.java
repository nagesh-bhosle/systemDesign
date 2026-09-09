package com.example.esdemo.dto;

import lombok.*;

import java.util.List;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class BenchmarkResult {
    private Object query;
    private EngineResult postgres;
    private EngineResult elasticsearch;

    @Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
    public static class EngineResult {
        private long tookMs;
        private Long took;
        private long total;
        private List<BusinessDto> results;
    }
}
