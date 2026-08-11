package com.example.yelp.controller;

import com.example.yelp.dto.BusinessDto;
import com.example.yelp.dto.ReviewDto;
import com.example.yelp.dto.SearchResult;
import com.example.yelp.entity.Business;
import com.example.yelp.service.BusinessService;
import com.example.yelp.service.ReviewService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Business REST controller.
 *
 * Endpoints (from the design doc):
 *   GET  /api/businesses?query&lat&lon&radius&category&location&sortBy&page&size
 *   GET  /api/businesses/{businessId}
 *   GET  /api/businesses/{businessId}/reviews?page&size
 *   POST /api/businesses/{businessId}/reviews
 *   GET  /api/categories
 */
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class BusinessController {

    private final BusinessService businessService;
    private final ReviewService reviewService;

    public BusinessController(BusinessService businessService, ReviewService reviewService) {
        this.businessService = businessService;
        this.reviewService = reviewService;
    }

    /**
     * Search for businesses.
     *
     * Supports two modes:
     * 1. Geo search: provide lat + lon (optionally radius in meters)
     * 2. Named location search: provide location (e.g. "san_francisco")
     *
     * Both modes support: query (text), category, sortBy, pagination.
     */
    @GetMapping("/businesses")
    public SearchResult<BusinessDto> searchBusinesses(
            @RequestParam(required = false) String query,
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lon,
            @RequestParam(required = false, defaultValue = "5000") Double radius,
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String location,
            @RequestParam(required = false, defaultValue = "rating") String sortBy,
            @RequestParam(required = false, defaultValue = "0") int page,
            @RequestParam(required = false, defaultValue = "20") int size
    ) {
        if (lat != null && lon != null) {
            // Geospatial search using PostGIS
            return businessService.searchByGeo(query, lat, lon, radius, category, sortBy, page, size);
        } else if (location != null && !location.isBlank()) {
            // Named location search using pre-computed locationNames
            return businessService.searchByLocationName(query, location, category, page, size);
        } else {
            // Default: search all (no geo filter) — use a large radius from a default point
            return businessService.searchByLocationName(query, null, category, page, size);
        }
    }

    /**
     * View a single business and its reviews.
     */
    @GetMapping("/businesses/{businessId}")
    public ResponseEntity<?> getBusiness(@PathVariable Long businessId) {
        return businessService.getById(businessId)
                .map(b -> {
                    BusinessDto dto = businessService.toDto(b, null, null);
                    List<ReviewDto> reviews = reviewService.getReviewsForBusiness(businessId, 0, 50);
                    Map<String, Object> response = new HashMap<>();
                    response.put("business", dto);
                    response.put("reviews", reviews);
                    return ResponseEntity.ok(response);
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get reviews for a business (paginated).
     */
    @GetMapping("/businesses/{businessId}/reviews")
    public List<ReviewDto> getReviews(
            @PathVariable Long businessId,
            @RequestParam(required = false, defaultValue = "0") int page,
            @RequestParam(required = false, defaultValue = "20") int size
    ) {
        return reviewService.getReviewsForBusiness(businessId, page, size);
    }

    /**
     * Get all available categories (for UI dropdown).
     */
    @GetMapping("/categories")
    public List<String> getCategories() {
        return businessService.getAllCategories();
    }
}