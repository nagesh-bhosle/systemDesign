package com.example.yelp.dto;

import lombok.*;

/**
 * Request DTO for creating a review.
 * Matches the POST /businesses/:businessId/reviews endpoint from the design doc.
 */
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class CreateReviewRequest {
    private Long userId;
    private Integer rating;   // 1-5
    private String text;      // optional
}