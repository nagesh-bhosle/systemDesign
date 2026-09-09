package com.example.esdemo.service;

import com.example.esdemo.dto.CreateReviewRequest;
import com.example.esdemo.dto.ReviewDto;
import com.example.esdemo.entity.Business;
import com.example.esdemo.entity.Review;
import com.example.esdemo.entity.User;
import com.example.esdemo.repository.BusinessRepository;
import com.example.esdemo.repository.ReviewRepository;
import com.example.esdemo.repository.UserRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

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

    @Transactional
    public ReviewDto createReview(Long businessId, CreateReviewRequest request) {
        if (request.getRating() == null || request.getRating() < 1 || request.getRating() > 5) {
            throw new IllegalArgumentException("Rating must be between 1 and 5");
        }
        Business business = businessRepository.findById(businessId)
                .orElseThrow(() -> new IllegalArgumentException("Business not found: " + businessId));
        User user = userRepository.findById(request.getUserId())
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + request.getUserId()));
        if (reviewRepository.findByUserIdAndBusinessId(request.getUserId(), businessId).isPresent()) {
            throw new IllegalStateException(
                "User " + request.getUserId() + " has already reviewed business " + businessId
            );
        }
        Review review = Review.builder()
                .rating(request.getRating())
                .text(request.getText())
                .business(business)
                .userId(user.getId())
                .userDisplayName(user.getDisplayName())
                .createdAt(LocalDateTime.now())
                .build();
        review = reviewRepository.save(review);
        updateBusinessRating(business);
        return toDto(review);
    }

    public List<ReviewDto> getReviewsForBusiness(Long businessId, int page, int pageSize) {
        Pageable pageable = PageRequest.of(page, pageSize);
        Page<Review> reviews = reviewRepository.findByBusinessIdOrderByCreatedAtDesc(businessId, pageable);
        return reviews.getContent().stream().map(this::toDto).toList();
    }

    private void updateBusinessRating(Business business) {
        long count = reviewRepository.countByBusinessId(business.getId());
        if (count == 0) {
            business.setAvgRating(0.0);
            business.setNumRatings(0);
        } else {
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
