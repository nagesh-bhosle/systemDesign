package com.example.yelp.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Represents a business listed on Yelp.
 *
 * Key design decisions from the Yelp system design doc:
 * - avgRating and numRatings are stored as columns (precomputed) so search
 *   results don't need to aggregate reviews on the fly.
 * - locationNames is a list of pre-computed area identifiers (e.g. "san_francisco",
 *   "mission_district") so we can filter by named location without polygon math
 *   on every request.
 * - latitude/longitude are stored as plain doubles. PostGIS spatial indexing
 *   is handled via a native geometry column created by DataInitializer.
 */
@Entity
@Table(name = "businesses")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Business {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(length = 2000)
    private String description;

    @Column(nullable = false)
    private String address;

    @Column(nullable = false)
    private Double latitude;

    @Column(nullable = false)
    private Double longitude;

    @Column(nullable = false)
    private String category;

    /** Pre-computed average rating (1-5). Updated synchronously on each new review. */
    @Column(nullable = false)
    private Double avgRating;

    /** Pre-computed review count. Updated synchronously on each new review. */
    @Column(nullable = false)
    private Integer numRatings;

    /** Phone number for the business */
    private String phone;

    /** Price range: "$", "$$", "$$$", "$$$$" */
    private String priceRange;

    /** URL for a representative image */
    private String imageUrl;

    /**
     * Pre-computed location identifiers for fast filtering.
     * Stored as a comma-separated string, e.g. "san_francisco,mission_district,bay_area"
     */
    @Column(length = 500)
    private String locationNames;

    private LocalDateTime createdAt;

    @OneToMany(mappedBy = "business", fetch = FetchType.LAZY)
    @Builder.Default
    private List<Review> reviews = new ArrayList<>();

    /** Convenience: parse locationNames into a List */
    @Transient
    public List<String> getLocationNameList() {
        if (locationNames == null || locationNames.isBlank()) return List.of();
        return List.of(locationNames.split(","));
    }
}