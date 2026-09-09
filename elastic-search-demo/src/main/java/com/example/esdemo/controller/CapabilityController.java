package com.example.esdemo.controller;

import com.example.esdemo.dto.BusinessDto;
import com.example.esdemo.dto.SearchResult;
import com.example.esdemo.service.ElasticsearchSearchService;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/capabilities")
@CrossOrigin(origins = "*")
public class CapabilityController {

    private final ElasticsearchSearchService esService;

    public CapabilityController(ElasticsearchSearchService esService) {
        this.esService = esService;
    }

    @GetMapping("/aggregations")
    public Map<String, Object> aggregations(
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lon,
            @RequestParam(required = false, defaultValue = "5000") Double radius) {
        return esService.aggregations(lat, lon, radius);
    }

    @GetMapping("/fuzzy")
    public SearchResult<BusinessDto> fuzzy(
            @RequestParam(required = false) String q,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return esService.fuzzySearch(q, page, size);
    }
}
