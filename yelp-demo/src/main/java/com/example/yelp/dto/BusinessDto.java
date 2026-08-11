package com.example.yelp.dto;

import lombok.*;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Business response DTO — includes computed distance when searching by lat/lon.
 */
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class BusinessDto {
    private Long id;
    private String name;
    private String description;
    private String address;
    private Double latitude;
    private Double longitude;
    private String category;
    private Double avgRating;
    private Integer numRatings;
    private String phone;
    private String priceRange;
    private String imageUrl;
    private List<String> locationNames;
    private Double distanceMeters;  // populated only for geo searches
}