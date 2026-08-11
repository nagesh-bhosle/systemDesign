package com.example.yelp.repository;

import com.example.yelp.entity.Business;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * Business repository with geospatial + full-text search queries.
 *
 * All queries use PostGIS functions:
 *  - ST_DWithin: finds businesses within a radius (in meters) from a point
 *  - ST_MakePoint: creates a geography point from lon/lat
 *  - to_tsquery / plainto_tsquery: PostgreSQL full-text search on name + description
 *  - ts_rank: ranks results by text relevance
 *
 * The search pipeline mirrors the design doc:
 *   1. Filter by distance (most restrictive) → reduces search space fast
 *   2. Filter by text query (name/description)
 *   3. Filter by category
 *   4. Order by rating or distance
 */
@Repository
public interface BusinessRepository extends JpaRepository<Business, Long> {

    /**
     * Full search: text query + radius + optional category.
     * Uses PostGIS ST_DWithin for geospatial filtering and ts_vector for full-text.
     */
    @Query(value = """
        SELECT * FROM businesses b
        WHERE ST_DWithin(
                  geography(ST_MakePoint(b.longitude, b.latitude)),
                  geography(ST_MakePoint(:lon, :lat)),
                  :radiusMeters
              )
          AND (:query IS NULL OR :query = '' OR
               b.search_vector @@ plainto_tsquery('english', :query))
          AND (:category IS NULL OR :category = '' OR
               b.category = :category)
        ORDER BY
          CASE WHEN :sortBy = 'rating' THEN b.avg_rating END DESC,
          CASE WHEN :sortBy = 'distance' THEN
               ST_Distance(geography(ST_MakePoint(b.longitude, b.latitude)),
                           geography(ST_MakePoint(:lon, :lat)))
          END ASC,
          b.avg_rating DESC
        """,
        countQuery = """
        SELECT count(*) FROM businesses b
        WHERE ST_DWithin(
                  geography(ST_MakePoint(b.longitude, b.latitude)),
                  geography(ST_MakePoint(:lon, :lat)),
                  :radiusMeters
              )
          AND (:query IS NULL OR :query = '' OR
               b.search_vector @@ plainto_tsquery('english', :query))
          AND (:category IS NULL OR :category = '' OR
               b.category = :category)
        """,
        nativeQuery = true)
    Page<Business> searchBusinesses(
            @Param("query") String query,
            @Param("lat") double lat,
            @Param("lon") double lon,
            @Param("radiusMeters") double radiusMeters,
            @Param("category") String category,
            @Param("sortBy") String sortBy,
            Pageable pageable
    );

    /**
     * Search by named location (e.g. "san_francisco").
     * Uses the pre-computed locationNames field with a LIKE filter.
     */
    @Query(value = """
        SELECT * FROM businesses b
        WHERE (:locationName IS NULL OR :locationName = '' OR
               b.location_names ILIKE %:locationName%)
          AND (:query IS NULL OR :query = '' OR
               b.search_vector @@ plainto_tsquery('english', :query))
          AND (:category IS NULL OR :category = '' OR
               b.category = :category)
        ORDER BY b.avg_rating DESC
        """,
        countQuery = """
        SELECT count(*) FROM businesses b
        WHERE (:locationName IS NULL OR :locationName = '' OR
               b.location_names ILIKE %:locationName%)
          AND (:query IS NULL OR :query = '' OR
               b.search_vector @@ plainto_tsquery('english', :query))
          AND (:category IS NULL OR :category = '' OR
               b.category = :category)
        """,
        nativeQuery = true)
    Page<Business> searchByLocationName(
            @Param("query") String query,
            @Param("locationName") String locationName,
            @Param("category") String category,
            Pageable pageable
    );

    /**
     * Simple category-based search (no geo).
     */
    List<Business> findByCategoryIgnoreCase(String category);
}