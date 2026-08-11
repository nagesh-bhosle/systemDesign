package com.example.yelp.dto;

import lombok.*;

import java.time.LocalDateTime;

/**
 * Review response DTO.
 */
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class ReviewDto {
    private Long id;
    private Long businessId;
    private Long userId;
    private String userDisplayName;
    private Integer rating;
    private String text;
    private LocalDateTime createdAt;
}