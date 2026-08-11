package com.example.yelp.service;

import com.example.yelp.dto.CreateReviewRequest;
import com.example.yelp.dto.ReviewDto;
import com.example.yelp.entity.Business;
import com.example.yelp.entity.Review;
import com.example.yelp.entity.User;
import com.example.yelp.repository.BusinessRepository;
import com.example.yelp.repository.ReviewRepository;
import com.example.yelp.repository.UserRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Review service — handles review creation and retrieval.
 *
 * Key design decisions from the Yelp doc:
 *
 * 1. One review per user per business:
 *    Enforced via a DB unique constraint (uk_user_business) + application-level check.
 *    The constraint is as close to the persistence layer as possible.
 *
 * 2. Synchronous avgRating update:
 *    The write volume is tiny (~1 write/sec), so we update avgRating and numRatings
 *    synchronously on the Business entity. No message queue needed — simplicity wins.
 *
 * 3. Search index sync:
 *    After updating the business rating, we call searchService.indexBusiness() to
 *    keep the Elasticsearch index in sync (no-op when using Postgres backend).
 */
@Service
public class ReviewService {

    private final ReviewRepository reviewRepository;
    private final BusinessRepository businessRepository;
    private final UserRepository userRepository;
    private final SearchService searchService;

    public ReviewService(ReviewRepository reviewRepository,
                         BusinessRepository businessRepository,
                         UserRepository userRepository,
                         SearchService searchService) {
        this.reviewRepository = reviewRepository;
        this.businessRepository = businessRepository;
        this.userRepository = userRepository;
        this.searchService = searchService;
    }

    /**
     * Create a review. Enforces one-review-per-user-per-business.
     */
    @Transactional
    public ReviewDto createReview(Long businessId, CreateReviewRequest request) {
        // Validate rating
        if (request.getRating() == null || request.getRating() < 1 || request.getRating() > 5) {
            throw new IllegalArgumentException("Rating must be between 1 and 5");
        }

        // Check business exists
        Business business = businessRepository.findById(businessId)
                .orElseThrow(() -> new IllegalArgumentException("Business not found: " + businessId));

        // Check user exists
        User user = userRepository.findById(request.getUserId())
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + request.getUserId()));

        // Enforce one-review-per-business constraint (application-level check)
        if (reviewRepository.findByUserIdAndBusinessId(request.getUserId(), businessId).isPresent()) {
            throw new IllegalStateException(
                "User " + request.getUserId() + " has already reviewed business " + businessId
            );
        }

        // Create review
        Review review = Review.builder()
                .rating(request.getRating())
                .text(request.getText())
                .business(business)
                .userId(user.getId())
                .userDisplayName(user.getDisplayName())
                .createdAt(LocalDateTime.now())
                .build();

        review = reviewRepository.save(review);

        // Synchronously update avgRating and numRatings on the business
        updateBusinessRating(business);

        return toDto(review);
    }

    /**
     * Get paginated reviews for a business.
     */
    public List<ReviewDto> getReviewsForBusiness(Long businessId, int page, int pageSize) {
        Pageable pageable = PageRequest.of(page, pageSize);
        Page<Review> reviews = reviewRepository.findByBusinessIdOrderByCreatedAtDesc(businessId, pageable);
        return reviews.getContent().stream().map(this::toDto).toList();
    }

    /**
     * Synchronously recalculate and persist avgRating + numRatings.
     *
     * This is the "simple" approach the design doc advocates for:
     * write volume is ~1/sec, so no message queue is needed.
     */
    private void updateBusinessRating(Business business) {
        long count = reviewRepository.countByBusinessId(business.getId());
        if (count == 0) {
            business.setAvgRating(0.0);
            business.setNumRatings(0);
        } else {
            // Recalculate from all reviews
            List<Review> allReviews = reviewRepository.findByBusinessIdOrderByCreatedAtDesc(
                    business.getId(), PageRequest.of(0, Integer.MAX_VALUE)
            ).getContent();
            double avg = allReviews.stream()
                    .mapToInt(Review::getRating)
                    .average()
                    .orElse(0.0);
            business.setAvgRating(Math.round(avg * 10.0) / 10.0);
            business.setNumRatings((int) count);
        }
        businessRepository.save(business);
        // Keep search index in sync (no-op for Postgres, re-indexes for Elasticsearch)
        searchService.indexBusiness(business);
    }

    private ReviewDto toDto(Review r) {
        return ReviewDto.builder()
                .id(r.getId())
                .businessId(r.getBusiness().getId())
                .userId(r.getUserId())
                .userDisplayName(r.getUserDisplayName())
                .rating(r.getRating())
                .text(r.getText())
                .createdAt(r.getCreatedAt())
                .build();
    }
}