package com.example.esdemo.service;

import co.elastic.clients.elasticsearch.ElasticsearchClient;
import co.elastic.clients.elasticsearch._types.DistanceUnit;
import co.elastic.clients.elasticsearch._types.SortOrder;
import co.elastic.clients.elasticsearch._types.aggregations.Aggregate;
import co.elastic.clients.elasticsearch._types.query_dsl.Query;
import co.elastic.clients.elasticsearch.core.SearchResponse;
import co.elastic.clients.elasticsearch.core.search.Hit;
import com.example.esdemo.dto.BusinessDto;
import com.example.esdemo.dto.SearchResult;
import com.example.esdemo.dto.SuggestResult;
import com.example.esdemo.entity.Business;
import com.example.esdemo.repository.BusinessRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
@Primary
public class ElasticsearchSearchService implements SearchService {

    private static final Logger log = LoggerFactory.getLogger(ElasticsearchSearchService.class);

    private final ElasticsearchClient esClient;
    private final BusinessRepository businessRepository;
    private final String index;

    public ElasticsearchSearchService(ElasticsearchClient esClient,
                                      BusinessRepository businessRepository,
                                      @Value("${elasticsearch.index:businesses}") String index) {
        this.esClient = esClient;
        this.businessRepository = businessRepository;
        this.index = index;
    }

    @Override
    public SearchResult<BusinessDto> searchByGeo(String query, double lat, double lon,
                                                  double radiusMeters, String category,
                                                  String sortBy, int page, int pageSize) {
        try {
            List<Query> mustQueries = new ArrayList<>();
            List<Query> filterQueries = new ArrayList<>();

            if (query != null && !query.isBlank()) {
                mustQueries.add(Query.of(q -> q
                        .multiMatch(m -> m
                                .query(query)
                                .fields("name^3", "description^2", "category", "address")
                        )
                ));
            }
            if (category != null && !category.isBlank()) {
                filterQueries.add(Query.of(q -> q.term(t -> t.field("category").value(category))));
            }
            double radiusKm = radiusMeters / 1000.0;
            filterQueries.add(Query.of(q -> q.geoDistance(g -> g
                    .field("location")
                    .distance(radiusKm + "km")
                    .location(l -> l.latlon(ll -> ll.lat(lat).lon(lon)))
            )));

            SearchResponse<BusinessDocument> response;
            if ("distance".equals(sortBy)) {
                response = esClient.search(s -> s
                                .index(index)
                                .from(page * pageSize)
                                .size(pageSize)
                                .query(q -> q.bool(b -> b.must(mustQueries).filter(filterQueries)))
                                .sort(so -> so.geoDistance(g -> g.field("location")
                                        .location(l -> l.latlon(ll -> ll.lat(lat).lon(lon)))
                                        .order(SortOrder.Asc)
                                        .unit(DistanceUnit.Kilometers))),
                        BusinessDocument.class
                );
            } else {
                response = esClient.search(s -> s
                                .index(index)
                                .from(page * pageSize)
                                .size(pageSize)
                                .query(q -> q.bool(b -> b.must(mustQueries).filter(filterQueries)))
                                .sort(so -> so.field(f -> f.field("avgRating").order(SortOrder.Desc))),
                        BusinessDocument.class
                );
            }

            List<BusinessDto> dtos = response.hits().hits().stream()
                    .map(h -> toDtoFromHit(h, lat, lon))
                    .toList();
            long total = response.hits().total() != null ? response.hits().total().value() : 0;
            int totalPages = (int) Math.ceil((double) total / pageSize);
            return SearchResult.<BusinessDto>builder()
                    .results(dtos).total(total).page(page).pageSize(pageSize).totalPages(totalPages).build();
        } catch (IOException e) {
            log.error("Elasticsearch geo search failed: {}", e.getMessage(), e);
            return SearchResult.<BusinessDto>builder()
                    .results(List.of()).total(0).page(page).pageSize(pageSize).totalPages(0).build();
        }
    }

    @Override
    public SearchResult<BusinessDto> searchByLocationName(String query, String locationName,
                                                          String category, int page, int pageSize) {
        try {
            List<Query> mustQueries = new ArrayList<>();
            List<Query> filterQueries = new ArrayList<>();

            if (query != null && !query.isBlank()) {
                mustQueries.add(Query.of(q -> q
                        .multiMatch(m -> m
                                .query(query)
                                .fields("name^3", "description^2", "category", "address")
                        )
                ));
            }
            if (locationName != null && !locationName.isBlank()) {
                filterQueries.add(Query.of(q -> q.term(t -> t.field("locationNames").value(locationName))));
            }
            if (category != null && !category.isBlank()) {
                filterQueries.add(Query.of(q -> q.term(t -> t.field("category").value(category))));
            }

            SearchResponse<BusinessDocument> response = esClient.search(s -> s
                            .index(index)
                            .from(page * pageSize)
                            .size(pageSize)
                            .query(q -> q.bool(b -> b.must(mustQueries).filter(filterQueries)))
                            .sort(so -> so.field(f -> f.field("avgRating").order(SortOrder.Desc))),
                    BusinessDocument.class
            );

            List<BusinessDto> dtos = response.hits().hits().stream()
                    .map(h -> toDtoFromHit(h, null, null))
                    .toList();
            long total = response.hits().total() != null ? response.hits().total().value() : 0;
            int totalPages = (int) Math.ceil((double) total / pageSize);
            return SearchResult.<BusinessDto>builder()
                    .results(dtos).total(total).page(page).pageSize(pageSize).totalPages(totalPages).build();
        } catch (IOException e) {
            log.error("Elasticsearch location search failed: {}", e.getMessage(), e);
            return SearchResult.<BusinessDto>builder()
                    .results(List.of()).total(0).page(page).pageSize(pageSize).totalPages(0).build();
        }
    }

    @Override
    public Optional<Business> getById(Long id) {
        return businessRepository.findById(id);
    }

    @Override
    public List<String> getAllCategories() {
        return businessRepository.findAll().stream()
                .map(Business::getCategory)
                .distinct()
                .sorted()
                .toList();
    }

    @Override
    public BusinessDto toDto(Business b, Double lat, Double lon) {
        Double distance = null;
        if (lat != null && lon != null) {
            distance = PostgresSearchService.haversine(lat, lon, b.getLatitude(), b.getLongitude());
        }
        return BusinessDto.builder()
                .id(b.getId())
                .name(b.getName())
                .description(b.getDescription())
                .address(b.getAddress())
                .latitude(b.getLatitude())
                .longitude(b.getLongitude())
                .category(b.getCategory())
                .avgRating(b.getAvgRating())
                .numRatings(b.getNumRatings())
                .phone(b.getPhone())
                .priceRange(b.getPriceRange())
                .imageUrl(b.getImageUrl())
                .locationNames(b.getLocationNameList())
                .distanceMeters(distance)
                .build();
    }

    @Override
    public List<SuggestResult> suggest(String q) {
        if (q == null || q.isBlank()) return List.of();
        try {
            SearchResponse<BusinessDocument> response = esClient.search(s -> s
                            .index(index)
                            .size(8)
                            .query(q2 -> q2.bool(b -> b
                                    .should(sh -> sh.prefix(p -> p.field("name.ngram").value(q)))
                                    .should(sh -> sh.multiMatch(m -> m.query(q).fields("name^3", "description")))
                            )),
                    BusinessDocument.class
            );
            List<SuggestResult> results = response.hits().hits().stream()
                    .map(h -> {
                        BusinessDocument doc = h.source();
                        if (doc == null) return null;
                        return SuggestResult.builder()
                                .text(doc.name)
                                .category(doc.category)
                                .id(doc.id)
                                .build();
                    })
                    .filter(r -> r != null)
                    .toList();
            if (!results.isEmpty()) return results;
        } catch (IOException e) {
            log.warn("ES suggest failed, falling back: {}", e.getMessage());
        }
        // fallback to Postgres LIKE-style filtering
        String lower = q.toLowerCase();
        return businessRepository.findAll().stream()
                .filter(b -> b.getName() != null && b.getName().toLowerCase().contains(lower))
                .limit(8)
                .map(b -> SuggestResult.builder().text(b.getName()).category(b.getCategory()).id(b.getId()).build())
                .toList();
    }

    @Override
    public Map<String, Object> aggregations(Double lat, Double lon, Double radius) {
        try {
            List<Query> filterQueries = new ArrayList<>();
            if (lat != null && lon != null && radius != null) {
                double radiusKm = radius / 1000.0;
                filterQueries.add(Query.of(q -> q.geoDistance(g -> g
                        .field("location")
                        .distance(radiusKm + "km")
                        .location(l -> l.latlon(ll -> ll.lat(lat).lon(lon)))
                )));
            }

            SearchResponse<BusinessDocument> response = esClient.search(s -> {
                var req = s.index(index).size(0)
                        .aggregations("by_category", a -> a.terms(t -> t.field("category").size(20)))
                        .aggregations("avg_rating_histogram", a -> a.histogram(h -> h.field("avgRating").interval(1.0)));
                if (!filterQueries.isEmpty()) {
                    req.query(q -> q.bool(b -> b.filter(filterQueries)));
                }
                return req;
            }, BusinessDocument.class);

            Map<String, Object> result = new LinkedHashMap<>();
            if (response.aggregations() != null) {
                for (Map.Entry<String, Aggregate> entry : response.aggregations().entrySet()) {
                    Aggregate agg = entry.getValue();
                    if (agg.isSterms()) {
                        Map<String, Long> buckets = new LinkedHashMap<>();
                        agg.sterms().buckets().array().forEach(b -> buckets.put(b.key().stringValue(), b.docCount()));
                        result.put(entry.getKey(), buckets);
                    } else if (agg.isLterms()) {
                        Map<String, Long> buckets = new LinkedHashMap<>();
                        agg.lterms().buckets().array().forEach(b -> buckets.put(String.valueOf(b.key()), b.docCount()));
                        result.put(entry.getKey(), buckets);
                    } else if (agg.isHistogram()) {
                        Map<String, Long> buckets = new LinkedHashMap<>();
                        agg.histogram().buckets().array().forEach(b -> buckets.put(String.valueOf(b.key()), b.docCount()));
                        result.put(entry.getKey(), buckets);
                    } else {
                        result.put(entry.getKey(), agg.toString());
                    }
                }
            }
            return result;
        } catch (IOException e) {
            log.error("ES aggregations failed: {}", e.getMessage(), e);
            Map<String, Long> categoryCounts = businessRepository.findAll().stream()
                    .collect(java.util.stream.Collectors.groupingBy(Business::getCategory, java.util.stream.Collectors.counting()));
            Map<String, Object> fallback = new HashMap<>();
            fallback.put("note", "Fallback Postgres aggregations (ES unavailable)");
            fallback.put("categories", categoryCounts);
            return fallback;
        }
    }

    @Override
    public SearchResult<BusinessDto> fuzzySearch(String q, int page, int pageSize) {
        if (q == null || q.isBlank()) {
            return SearchResult.<BusinessDto>builder()
                    .results(List.of()).total(0).page(page).pageSize(pageSize).totalPages(0).build();
        }
        try {
            SearchResponse<BusinessDocument> response = esClient.search(s -> s
                            .index(index)
                            .from(page * pageSize)
                            .size(pageSize)
                            .query(q2 -> q2.multiMatch(m -> m
                                    .query(q)
                                    .fields("name^3", "description^2")
                                    .fuzziness("AUTO")
                            )),
                    BusinessDocument.class
            );
            List<BusinessDto> dtos = response.hits().hits().stream()
                    .map(h -> toDtoFromHit(h, null, null))
                    .toList();
            long total = response.hits().total() != null ? response.hits().total().value() : 0;
            int totalPages = (int) Math.ceil((double) total / pageSize);
            return SearchResult.<BusinessDto>builder()
                    .results(dtos).total(total).page(page).pageSize(pageSize).totalPages(totalPages).build();
        } catch (IOException e) {
            log.error("ES fuzzy search failed: {}", e.getMessage(), e);
            return SearchResult.<BusinessDto>builder()
                    .results(List.of()).total(0).page(page).pageSize(pageSize).totalPages(0).build();
        }
    }

    @Override
    public void indexBusiness(Business business) {
        try {
            BusinessDocument doc = toDocument(business);
            esClient.index(i -> i.index(index).id(String.valueOf(business.getId())).document(doc));
        } catch (IOException e) {
            log.warn("Failed to index business {}: {}", business.getId(), e.getMessage());
        }
    }

    @Override
    public void deleteBusiness(Long id) {
        try {
            esClient.delete(d -> d.index(index).id(String.valueOf(id)));
        } catch (IOException e) {
            log.warn("Failed to delete business {} from ES: {}", id, e.getMessage());
        }
    }

    @Override
    public void reindexAll(Iterable<Business> businesses) {
        log.info("Re-indexing all businesses into Elasticsearch...");
        int count = 0;
        for (Business b : businesses) {
            indexBusiness(b);
            count++;
        }
        log.info("  Indexed {} businesses", count);
    }

    private BusinessDocument toDocument(Business b) {
        BusinessDocument doc = new BusinessDocument();
        doc.id = b.getId();
        doc.name = b.getName();
        doc.description = b.getDescription();
        doc.address = b.getAddress();
        doc.category = b.getCategory();
        doc.avgRating = b.getAvgRating();
        doc.numRatings = b.getNumRatings();
        doc.priceRange = b.getPriceRange();
        doc.imageUrl = b.getImageUrl();
        doc.phone = b.getPhone();
        doc.locationNames = b.getLocationNameList();
        doc.location = new double[]{b.getLongitude(), b.getLatitude()}; // [lon, lat] GeoJSON order
        return doc;
    }

    private BusinessDto toDtoFromHit(Hit<BusinessDocument> hit, Double lat, Double lon) {
        BusinessDocument doc = hit.source();
        if (doc == null) return null;
        Double distance = null;
        if (lat != null && lon != null && doc.location != null) {
            double docLat = doc.location[1];
            double docLon = doc.location[0];
            distance = PostgresSearchService.haversine(lat, lon, docLat, docLon);
        }
        return BusinessDto.builder()
                .id(doc.id)
                .name(doc.name)
                .description(doc.description)
                .address(doc.address)
                .latitude(doc.location != null ? doc.location[1] : null)
                .longitude(doc.location != null ? doc.location[0] : null)
                .category(doc.category)
                .avgRating(doc.avgRating)
                .numRatings(doc.numRatings)
                .phone(doc.phone)
                .priceRange(doc.priceRange)
                .imageUrl(doc.imageUrl)
                .locationNames(doc.locationNames)
                .distanceMeters(distance)
                .build();
    }

    public static class BusinessDocument {
        public Long id;
        public String name;
        public String description;
        public String address;
        public String category;
        public Double avgRating;
        public Integer numRatings;
        public String priceRange;
        public String imageUrl;
        public String phone;
        public List<String> locationNames;
        public double[] location; // [lon, lat]
    }
}
