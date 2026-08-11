package com.example.yelp.service;

import co.elastic.clients.elasticsearch.ElasticsearchClient;
import co.elastic.clients.elasticsearch._types.DistanceUnit;
import co.elastic.clients.elasticsearch._types.SortOrder;
import co.elastic.clients.elasticsearch._types.query_dsl.Query;
import co.elastic.clients.elasticsearch.core.SearchResponse;
import co.elastic.clients.elasticsearch.core.search.Hit;
import co.elastic.clients.json.jackson.JacksonJsonpMapper;
import co.elastic.clients.transport.rest_client.RestClientTransport;
import com.example.yelp.dto.BusinessDto;
import com.example.yelp.dto.SearchResult;
import com.example.yelp.entity.Business;
import com.example.yelp.repository.BusinessRepository;
import jakarta.annotation.PostConstruct;
import org.apache.http.HttpHost;
import org.elasticsearch.client.RestClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Elasticsearch implementation of SearchService.
 *
 * Uses Elasticsearch's geo_point type + geo_distance query for geospatial search,
 * and multi_match + text analyzers for full-text search.
 *
 * Key differences from Postgres:
 *   - Full-text search uses ES analyzers (stemming, tokenization) instead of PostgreSQL tsvector
 *   - Geo search uses geo_distance query instead of PostGIS ST_DWithin
 *   - Results come from the ES index, not the DB (DB is still source of truth for reviews)
 *   - Business must be indexed into ES before it can be searched
 *
 * Active when search.backend = elasticsearch.
 */
@Service
@ConditionalOnProperty(name = "search.backend", havingValue = "elasticsearch")
public class ElasticsearchSearchService implements SearchService {

    private static final Logger log = LoggerFactory.getLogger(ElasticsearchSearchService.class);

    private final BusinessRepository businessRepository;
    private final String esHost;
    private final int esPort;
    private final String esScheme;
    private final String esIndex;

    private ElasticsearchClient esClient;

    public ElasticsearchSearchService(BusinessRepository businessRepository,
                                       @Value("${elasticsearch.host:localhost}") String esHost,
                                       @Value("${elasticsearch.port:9200}") int esPort,
                                       @Value("${elasticsearch.scheme:http}") String esScheme,
                                       @Value("${elasticsearch.index:businesses}") String esIndex) {
        this.businessRepository = businessRepository;
        this.esHost = esHost;
        this.esPort = esPort;
        this.esScheme = esScheme;
        this.esIndex = esIndex;
    }

    @PostConstruct
    public void init() {
        log.info("🔍 Elasticsearch search backend enabled — connecting to {}://{}:{}", esScheme, esHost, esPort);

        RestClient restClient = RestClient.builder(new HttpHost(esHost, esPort, esScheme))
                .setRequestConfigCallback(builder -> builder
                        .setConnectTimeout(5000)
                        .setSocketTimeout(60000))
                .build();

        esClient = new ElasticsearchClient(new RestClientTransport(restClient, new JacksonJsonpMapper()));

        // Create the index with proper mapping if it doesn't exist
        try {
            boolean exists = esClient.indices().exists(e -> e.index(esIndex)).value();
            if (!exists) {
                esClient.indices().create(c -> c
                        .index(esIndex)
                        .mappings(m -> m
                                .properties("name", p -> p.text(t -> t.analyzer("standard").boost(3.0)))
                                .properties("description", p -> p.text(t -> t.analyzer("english")))
                                .properties("category", p -> p.keyword(k -> k))
                                .properties("address", p -> p.text(t -> t.analyzer("standard")))
                                .properties("location", p -> p.geoPoint(g -> g))
                                .properties("locationNames", p -> p.keyword(k -> k))
                                .properties("avgRating", p -> p.double_(d -> d))
                                .properties("numRatings", p -> p.integer(i -> i))
                                .properties("priceRange", p -> p.keyword(k -> k))
                        )
                );
                log.info("✅ Created Elasticsearch index '{}' with geo_point mapping", esIndex);
            } else {
                log.info("ℹ️ Elasticsearch index '{}' already exists", esIndex);
            }
        } catch (IOException e) {
            log.error("Failed to create Elasticsearch index: {}", e.getMessage(), e);
        }
    }

    @Override
    public SearchResult<BusinessDto> searchByGeo(String query, double lat, double lon,
                                                  double radiusMeters, String category,
                                                  String sortBy, int page, int pageSize) {
        try {
            List<Query> mustQueries = new ArrayList<>();
            List<Query> filterQueries = new ArrayList<>();

            // Full-text search
            if (query != null && !query.isBlank()) {
                mustQueries.add(Query.of(q -> q
                        .multiMatch(m -> m
                                .query(query)
                                .fields("name^3", "description^2", "category", "address")
                        )
                ));
            }

            // Category filter
            if (category != null && !category.isBlank()) {
                filterQueries.add(Query.of(q -> q.term(t -> t.field("category").value(category))));
            }

            // Geo distance filter
            double radiusKm = radiusMeters / 1000.0;
            filterQueries.add(Query.of(q -> q.geoDistance(g -> g
                    .field("location")
                    .distance(radiusKm + "km")
                    .location(l -> l.latlon(ll -> ll.lat(lat).lon(lon)))
            )));

            // Sorting
            final List<Query> finalMust = mustQueries;
            final List<Query> finalFilter = filterQueries;

            SearchResponse<BusinessDocument> response;
            if ("distance".equals(sortBy)) {
                final double finalLat = lat;
                final double finalLon = lon;
                response = esClient.search(s -> s
                        .index(esIndex)
                        .from(page * pageSize)
                        .size(pageSize)
                        .query(q -> q.bool(b -> b.must(finalMust).filter(finalFilter)))
                        .sort(so -> so.geoDistance(g -> g.field("location")
                                .location(l -> l.latlon(ll -> ll.lat(finalLat).lon(finalLon)))
                                .order(SortOrder.Asc)
                                .unit(DistanceUnit.Kilometers))),
                        BusinessDocument.class
                );
            } else {
                response = esClient.search(s -> s
                        .index(esIndex)
                        .from(page * pageSize)
                        .size(pageSize)
                        .query(q -> q.bool(b -> b.must(finalMust).filter(finalFilter)))
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
                    .results(dtos)
                    .total(total)
                    .page(page)
                    .pageSize(pageSize)
                    .totalPages(totalPages)
                    .build();

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

            // Full-text search
            if (query != null && !query.isBlank()) {
                mustQueries.add(Query.of(q -> q
                        .multiMatch(m -> m
                                .query(query)
                                .fields("name^3", "description^2", "category", "address")
                        )
                ));
            }

            // Named location filter (exact match on keyword field)
            if (locationName != null && !locationName.isBlank()) {
                filterQueries.add(Query.of(q -> q.term(t -> t.field("locationNames").value(locationName))));
            }

            // Category filter
            if (category != null && !category.isBlank()) {
                filterQueries.add(Query.of(q -> q.term(t -> t.field("category").value(category))));
            }

            SearchResponse<BusinessDocument> response = esClient.search(s -> s
                    .index(esIndex)
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
                    .results(dtos)
                    .total(total)
                    .page(page)
                    .pageSize(pageSize)
                    .totalPages(totalPages)
                    .build();

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

    // --- Indexing ---

    @Override
    public void indexBusiness(Business business) {
        try {
            BusinessDocument doc = toDocument(business);
            esClient.index(i -> i.index(esIndex).id(String.valueOf(business.getId())).document(doc));
        } catch (IOException e) {
            log.warn("Failed to index business {}: {}", business.getId(), e.getMessage());
        }
    }

    @Override
    public void deleteBusiness(Long id) {
        try {
            esClient.delete(d -> d.index(esIndex).id(String.valueOf(id)));
        } catch (IOException e) {
            log.warn("Failed to delete business {} from ES: {}", id, e.getMessage());
        }
    }

    @Override
    public void reindexAll(Iterable<Business> businesses) {
        log.info("🔄 Re-indexing all businesses into Elasticsearch...");
        int count = 0;
        for (Business b : businesses) {
            indexBusiness(b);
            count++;
        }
        log.info("  ✅ Indexed {} businesses", count);
    }

    // --- Helpers ---

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
        doc.location = new double[]{b.getLongitude(), b.getLatitude()}; // [lon, lat] — GeoJSON order
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

    /**
     * Document model for Elasticsearch.
     * location is [lon, lat] in GeoJSON order — required by ES geo_point type.
     */
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