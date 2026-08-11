package com.example.yelp.service;

import com.example.yelp.dto.BusinessDto;
import com.example.yelp.dto.SearchResult;
import com.example.yelp.entity.Business;

import java.util.List;
import java.util.Optional;

/**
 * Abstraction for the search backend.
 *
 * Two implementations:
 *   - PostgresSearchService  → PostgreSQL + PostGIS (existing setup)
 *   - ElasticsearchSearchService → Elasticsearch with geo_point + text analyzers
 *
 * The active implementation is selected by the `search.backend` property in application.yml.
 */
public interface SearchService {

    /**
     * Search businesses by text query + lat/lon radius + optional category.
     */
    SearchResult<BusinessDto> searchByGeo(String query, double lat, double lon,
                                          double radiusMeters, String category,
                                          String sortBy, int page, int pageSize);

    /**
     * Search businesses by named location (e.g. "san_francisco").
     */
    SearchResult<BusinessDto> searchByLocationName(String query, String locationName,
                                                    String category, int page, int pageSize);

    /**
     * Get a single business by ID.
     */
    Optional<Business> getById(Long id);

    /**
     * Get all distinct categories.
     */
    List<String> getAllCategories();

    /**
     * Convert entity to DTO, computing distance if lat/lon provided.
     */
    BusinessDto toDto(Business b, Double lat, Double lon);

    /**
     * Index or re-index a business (used by Elasticsearch backend; no-op for Postgres).
     */
    void indexBusiness(Business business);

    /**
     * Remove a business from the search index (no-op for Postgres).
     */
    void deleteBusiness(Long id);

    /**
     * Re-index all businesses (called on startup for Elasticsearch).
     */
    void reindexAll(Iterable<Business> businesses);
}