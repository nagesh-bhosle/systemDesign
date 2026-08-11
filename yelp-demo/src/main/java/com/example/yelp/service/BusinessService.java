package com.example.yelp.service;

import com.example.yelp.dto.BusinessDto;
import com.example.yelp.dto.SearchResult;
import com.example.yelp.entity.Business;
import com.example.yelp.repository.BusinessRepository;
import com.example.yelp.repository.LocationAreaRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

/**
 * Business service — handles search and view operations.
 *
 * Implements the search pipeline from the design doc:
 *   1. If lat/lon provided → geospatial search via PostGIS ST_DWithin
 *   2. If locationName provided → search by pre-computed location identifiers
 *   3. Text query → PostgreSQL full-text search (ts_vector)
 *   4. Category filter
 *   5. Sort by rating or distance
 */
@Service
public class BusinessService {

    private final BusinessRepository businessRepository;
    private final LocationAreaRepository locationAreaRepository;

    public BusinessService(BusinessRepository businessRepository,
                           LocationAreaRepository locationAreaRepository) {
        this.businessRepository = businessRepository;
        this.locationAreaRepository = locationAreaRepository;
    }

    /**
     * Search businesses by text query + lat/lon radius + optional category.
     *
     * @param query       text search term (name/description), may be null/empty
     * @param lat         latitude of search center
     * @param lon         longitude of search center
     * @param radiusMeters search radius in meters (default 5000 = 5km)
     * @param category    optional category filter
     * @param sortBy      "rating" or "distance"
     * @param page        zero-based page number
     * @param pageSize    results per page
     */
    public SearchResult<BusinessDto> searchByGeo(String query, double lat, double lon,
                                                  double radiusMeters, String category,
                                                  String sortBy, int page, int pageSize) {
        Pageable pageable = PageRequest.of(page, pageSize);
        Page<Business> businesses = businessRepository.searchBusinesses(
                query, lat, lon, radiusMeters, category, sortBy, pageable
        );

        List<BusinessDto> dtos = businesses.getContent().stream()
                .map(b -> toDto(b, lat, lon))
                .toList();

        return SearchResult.<BusinessDto>builder()
                .results(dtos)
                .total(businesses.getTotalElements())
                .page(page)
                .pageSize(pageSize)
                .totalPages(businesses.getTotalPages())
                .build();
    }

    /**
     * Search businesses by named location (e.g. "san_francisco").
     */
    public SearchResult<BusinessDto> searchByLocationName(String query, String locationName,
                                                          String category, int page, int pageSize) {
        Pageable pageable = PageRequest.of(page, pageSize);
        Page<Business> businesses = businessRepository.searchByLocationName(
                query, locationName, category, pageable
        );

        List<BusinessDto> dtos = businesses.getContent().stream()
                .map(b -> toDto(b, null, null))
                .toList();

        return SearchResult.<BusinessDto>builder()
                .results(dtos)
                .total(businesses.getTotalElements())
                .page(page)
                .pageSize(pageSize)
                .totalPages(businesses.getTotalPages())
                .build();
    }

    /**
     * Get a single business by ID.
     */
    public Optional<Business> getById(Long id) {
        return businessRepository.findById(id);
    }

    /**
     * Get all distinct categories (for the UI filter dropdown).
     */
    public List<String> getAllCategories() {
        return businessRepository.findAll().stream()
                .map(Business::getCategory)
                .distinct()
                .sorted()
                .toList();
    }

    /**
     * Convert entity to DTO, computing distance if lat/lon provided.
     */
    public BusinessDto toDto(Business b, Double lat, Double lon) {
        Double distance = null;
        if (lat != null && lon != null) {
            distance = haversine(lat, lon, b.getLatitude(), b.getLongitude());
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

    /**
     * Haversine formula — calculates distance between two lat/lon points in meters.
     * Used for second-pass filtering and display.
     */
    public static double haversine(double lat1, double lon1, double lat2, double lon2) {
        final int R = 6371000; // Earth radius in meters
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }
}