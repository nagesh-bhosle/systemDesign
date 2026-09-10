package com.example.esdemo.config;

import co.elastic.clients.elasticsearch.ElasticsearchClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;

@Configuration
public class IndexInitializer {

    private static final Logger log = LoggerFactory.getLogger(IndexInitializer.class);

    @Value("${elasticsearch.index:businesses}")
    private String index;

    @Bean
    @Order(5)
    public ApplicationRunner ensureElasticsearchIndex(ElasticsearchClient esClient) {
        return args -> {
            try {
                boolean exists = esClient.indices().exists(e -> e.index(index)).value();
                if (!exists) {
                    esClient.indices().create(c -> c
                            .index(index)
                            .settings(s -> s
                                    .analysis(a -> a
                                            .analyzer("edge_ngram_analyzer", ana -> ana
                                                    .custom(cust -> cust
                                                            .tokenizer("standard")
                                                            .filter("lowercase", "edge_ngram_filter")
                                                    )
                                            )
                                            .filter("edge_ngram_filter", f -> f
                                                    .definition(d -> d
                                                            .edgeNgram(e -> e
                                                                    .minGram(2)
                                                                    .maxGram(15)
                                                            )
                                                    )
                                            )
                                    )
                            )
                            .mappings(m -> m
                                    .properties("name", p -> p
                                            .text(t -> t
                                                    .analyzer("standard")
                                                    .boost(3.0)
                                                    .fields("ngram", fn -> fn
                                                            .text(tt -> tt.analyzer("edge_ngram_analyzer"))
                                                    )
                                            )
                                    )
                                    .properties("description", p -> p.text(t -> t.analyzer("english")))
                                    .properties("category", p -> p.keyword(k -> k))
                                    .properties("address", p -> p.text(t -> t.analyzer("standard")))
                                    .properties("location", p -> p.geoPoint(g -> g))
                                    .properties("locationNames", p -> p.keyword(k -> k))
                                    .properties("avgRating", p -> p.double_(d -> d))
                                    .properties("numRatings", p -> p.integer(i -> i))
                                    .properties("priceRange", p -> p.keyword(k -> k))
                                    .properties("suggest", p -> p.completion(cmp -> cmp))
                            )
                    );
                    log.info("Created Elasticsearch index '{}'", index);
                } else {
                    log.info("Elasticsearch index '{}' already exists", index);
                }
            } catch (Exception e) {
                log.warn("Could not ensure ES index '{}': {}", index, e.getMessage());
            }
        };
    }
}
