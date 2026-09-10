package com.example.esdemo.controller;

import co.elastic.clients.elasticsearch.ElasticsearchClient;
import com.example.esdemo.dto.StatsDto;
import com.example.esdemo.repository.BusinessRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class StatsController {

    private static final Logger log = LoggerFactory.getLogger(StatsController.class);

    private final BusinessRepository businessRepository;
    private final ElasticsearchClient esClient;
    private final String index;

    public StatsController(BusinessRepository businessRepository,
                           ElasticsearchClient esClient,
                           @Value("${elasticsearch.index:businesses}") String index) {
        this.businessRepository = businessRepository;
        this.esClient = esClient;
        this.index = index;
    }

    @GetMapping("/stats")
    public StatsDto stats() {
        long pgCount = businessRepository.count();
        long esCount = 0;
        String esHealth = "red";
        boolean indexExists = false;
        try {
            indexExists = esClient.indices().exists(e -> e.index(index)).value();
            var healthResp = esClient.cluster().health(h -> h);
            esHealth = healthResp.status() != null ? healthResp.status().jsonValue() : "unknown";
            if (indexExists) {
                var countResp = esClient.count(c -> c.index(index));
                esCount = countResp.count();
            }
        } catch (Exception e) {
            log.warn("ES unavailable for stats: {}", e.getMessage());
            esHealth = "red";
            esCount = 0;
            indexExists = false;
        }
        return StatsDto.builder()
                .postgresCount(pgCount)
                .elasticsearchCount(esCount)
                .esHealth(esHealth)
                .indexExists(indexExists)
                .build();
    }
}
