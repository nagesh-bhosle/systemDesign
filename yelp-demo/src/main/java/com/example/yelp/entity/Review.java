package com.example.yelp.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * Represents a review left by a user for a business.
 *
 * Design constraint from the doc: each user can leave only one review per business.
 * This is enforced via a unique constraint on (userId, businessId) — applied as
 * close to the persistence layer as possible.
 */
@Entity
@Table(
    name = "reviews",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_user_business",
        columnNames = {"userId", "businessId"}
    )
)
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Review {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Integer rating;  // 1-5

    @Column(length = 4000)
    private String text;

    @Column(nullable = false)
    private LocalDateTime createdAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "businessId", nullable = false)
    @JsonIgnore
    private Business business;

    @Column(nullable = false)
    private Long userId;

    /** Denormalized for convenience in API responses */
    private String userDisplayName;
}