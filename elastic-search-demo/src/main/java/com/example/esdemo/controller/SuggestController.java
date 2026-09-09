package com.example.esdemo.controller;

import com.example.esdemo.dto.SuggestResult;
import com.example.esdemo.service.ElasticsearchSearchService;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class SuggestController {

    private final ElasticsearchSearchService esService;

    public SuggestController(ElasticsearchSearchService esService) {
        this.esService = esService;
    }

    @GetMapping("/suggest")
    public List<SuggestResult> suggest(@RequestParam(required = false) String q) {
        if (q == null || q.isBlank()) return List.of();
        return esService.suggest(q);
    }
}
