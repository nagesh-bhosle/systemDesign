package com.example.yelp.repository;

import com.example.yelp.entity.Review;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ReviewRepository extends JpaRepository<Review, Long> {

    Page<Review> findByBusinessIdOrderByCreatedAtDesc(Long businessId, Pageable pageable);

    /** Used to enforce the one-review-per-business constraint */
    Optional<Review> findByUserIdAndBusinessId(Long userId, Long businessId);

    long countByBusinessId(Long businessId);
}