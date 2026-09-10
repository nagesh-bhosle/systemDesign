package com.example.esdemo.controller;

import com.example.esdemo.dto.BusinessDto;
import com.example.esdemo.dto.ReviewDto;
import com.example.esdemo.dto.SearchResult;
import com.example.esdemo.service.ReviewService;
import com.example.esdemo.service.SearchService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class BusinessController {

    private final SearchService searchService;
    private final ReviewService reviewService;

    public BusinessController(SearchService searchService, ReviewService reviewService) {
        this.searchService = searchService;
        this.reviewService = reviewService;
    }

    @GetMapping("/businesses")
    public SearchResult<BusinessDto> searchBusinesses(
            @RequestParam(required = false, name = "q") String q,
            @RequestParam(required = false, name = "query") String queryAlias,
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lon,
            @RequestParam(required = false, defaultValue = "5000") Double radius,
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String location,
            @RequestParam(required = false, defaultValue = "rating") String sortBy,
            @RequestParam(required = false, defaultValue = "0") int page,
            @RequestParam(required = false, defaultValue = "20") int size
    ) {
        String qEffective = q != null ? q : queryAlias;
        if (lat != null && lon != null) {
            return searchService.searchByGeo(qEffective, lat, lon, radius, category, sortBy, page, size);
        } else {
            return searchService.searchByLocationName(qEffective, location, category, page, size);
        }
    }

    @GetMapping("/businesses/{id}")
    public ResponseEntity<?> getBusiness(@PathVariable Long id) {
        return searchService.getById(id)
                .map(b -> {
                    BusinessDto dto = searchService.toDto(b, null, null);
                    List<ReviewDto> reviews = reviewService.getReviewsForBusiness(id, 0, 50);
                    Map<String, Object> response = new HashMap<>();
                    response.put("business", dto);
                    response.put("reviews", reviews);
                    return ResponseEntity.ok(response);
                })
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/categories")
    public List<String> getCategories() {
        return searchService.getAllCategories();
    }
}
