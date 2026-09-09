package com.example.esdemo.service;
import com.example.esdemo.dto.*;
import org.slf4j.Logger; import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import java.util.LinkedHashMap; import java.util.Map;

@Service
public class BenchmarkService {
    private static final Logger log = LoggerFactory.getLogger(BenchmarkService.class);
    private final PostgresSearchService postgresService;
    private final ElasticsearchSearchService esService;
    public BenchmarkService(PostgresSearchService pg, ElasticsearchSearchService es) { this.postgresService = pg; this.esService = es; }

    public BenchmarkResult benchmarkText(String q, String category, int page, int size) {
        // warm-up call
        try { postgresService.searchByLocationName(q, null, category, 0, 1); } catch(Exception ignored) {}
        try { esService.searchByLocationName(q, null, category, 0, 1); } catch(Exception ignored) {}
        long t0=System.nanoTime();
        var pgResult = postgresService.searchByLocationName(q, null, category, page, size);
        long pgMs=(System.nanoTime()-t0)/1_000_000;
        long t1=System.nanoTime();
        var esResult = esService.searchByLocationName(q, null, category, page, size);
        long esMs=(System.nanoTime()-t1)/1_000_000;
        Map<String,Object> query = new LinkedHashMap<>();
        query.put("q", q); query.put("category", category);
        // Build via helper that measures ES took? For now esMs is wall clock, also try to get esResult took if available
        return BenchmarkResult.builder()
            .query(query)
            .postgres(BenchmarkResult.EngineResult.builder().tookMs(pgMs).total(pgResult.getTotal()).results(pgResult.getResults()).build())
            .elasticsearch(BenchmarkResult.EngineResult.builder().tookMs(esMs).total(esResult.getTotal()).results(esResult.getResults()).build())
            .build();
    }

    public BenchmarkResult benchmarkGeo(double lat, double lon, double radius, String q, String category, String sortBy, int page, int size) {
        try { postgresService.searchByGeo(q, lat, lon, radius, category, sortBy, 0, 1); } catch(Exception ignored) {}
        try { esService.searchByGeo(q, lat, lon, radius, category, sortBy, 0, 1); } catch(Exception ignored) {}
        long t0=System.nanoTime();
        var pgResult = postgresService.searchByGeo(q, lat, lon, radius, category, sortBy, page, size);
        long pgMs=(System.nanoTime()-t0)/1_000_000;
        long t1=System.nanoTime();
        var esResult = esService.searchByGeo(q, lat, lon, radius, category, sortBy, page, size);
        long esMs=(System.nanoTime()-t1)/1_000_000;
        Map<String,Object> query = new LinkedHashMap<>();
        query.put("q", q); query.put("lat", lat); query.put("lon", lon); query.put("radius", radius); query.put("category", category);
        return BenchmarkResult.builder()
            .query(query)
            .postgres(BenchmarkResult.EngineResult.builder().tookMs(pgMs).total(pgResult.getTotal()).results(pgResult.getResults()).build())
            .elasticsearch(BenchmarkResult.EngineResult.builder().tookMs(esMs).total(esResult.getTotal()).results(esResult.getResults()).build())
            .build();
    }

    public BenchmarkResult benchmarkCombined(String q, Double lat, Double lon, Double radius, String category, String sortBy, int page, int size) {
        // Combined: text + geo if lat/lon present, else just text
        if (lat != null && lon != null && radius != null) {
            return benchmarkGeo(lat, lon, radius, q, category, sortBy != null ? sortBy : "rating", page, size);
        } else {
            return benchmarkText(q, category, page, size);
        }
    }
}
