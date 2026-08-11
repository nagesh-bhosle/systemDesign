package com.example.yelp.controller;

import com.example.yelp.dto.CreateReviewRequest;
import com.example.yelp.dto.ReviewDto;
import com.example.yelp.service.ReviewService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Review REST controller.
 *
 * POST /api/businesses/{businessId}/reviews
 *   - Creates a review (1-5 star rating + optional text)
 *   - Enforces one review per user per business
 *   - Synchronously updates business avgRating
 */
@RestController
@RequestMapping("/api/businesses/{businessId}/reviews")
@CrossOrigin(origins = "*")
public class ReviewController {

    private final ReviewService reviewService;

    public ReviewController(ReviewService reviewService) {
        this.reviewService = reviewService;
    }

    @PostMapping
    public ResponseEntity<?> createReview(
            @PathVariable Long businessId,
            @Valid @RequestBody CreateReviewRequest request
    ) {
        try {
            ReviewDto review = reviewService.createReview(businessId, request);
            return ResponseEntity.status(HttpStatus.CREATED).body(review);
        } catch (IllegalStateException e) {
            // One review per business constraint violation
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", e.getMessage()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }
}