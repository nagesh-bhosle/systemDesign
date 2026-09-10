package com.example.esdemo.config;

import com.example.esdemo.entity.Business;
import com.example.esdemo.entity.LocationArea;
import com.example.esdemo.entity.Review;
import com.example.esdemo.entity.User;
import com.example.esdemo.repository.BusinessRepository;
import com.example.esdemo.repository.LocationAreaRepository;
import com.example.esdemo.repository.ReviewRepository;
import com.example.esdemo.repository.UserRepository;
import com.example.esdemo.service.SearchService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Lazy;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * DataInitializer — runs on application startup for elastic-search-demo.
 *
 * Responsibilities:
 * 1. Enable PostGIS extension
 * 2. Create geography column + GiST index
 * 3. Create full-text search_vector + GIN index
 * 4. Create location_names index (gin_trgm_ops with btree fallback)
 * 5. Seed ~2000 synthetic restaurants across SF / Manhattan / Bangalore
 * 6. Refresh search_vector/geom and re-index via SearchService
 */
@Component
@Order(10)
public class DataInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DataInitializer.class);

    private final JdbcTemplate jdbcTemplate;
    private final BusinessRepository businessRepository;
    private final ReviewRepository reviewRepository;
    private final UserRepository userRepository;
    private final LocationAreaRepository locationAreaRepository;
    private final SearchService searchService;

    public DataInitializer(JdbcTemplate jdbcTemplate,
                           BusinessRepository businessRepository,
                           ReviewRepository reviewRepository,
                           UserRepository userRepository,
                           LocationAreaRepository locationAreaRepository,
                           @Lazy SearchService searchService) {
        this.jdbcTemplate = jdbcTemplate;
        this.businessRepository = businessRepository;
        this.reviewRepository = reviewRepository;
        this.userRepository = userRepository;
        this.locationAreaRepository = locationAreaRepository;
        this.searchService = searchService;
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            // 1. Enable PostGIS extension
            jdbcTemplate.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            log.info("✅ PostGIS extension enabled");

            // 2. Add geography column
            try {
                jdbcTemplate.execute(
                        "ALTER TABLE businesses ADD COLUMN IF NOT EXISTS geom geography(Point, 4326)"
                );
                jdbcTemplate.execute(
                        "UPDATE businesses SET geom = ST_MakePoint(longitude, latitude)::geography WHERE geom IS NULL"
                );
                log.info("✅ Geography column 'geom' added and populated");
            } catch (Exception e) {
                log.warn("Could not add geom column: {}", e.getMessage());
            }

            // 3. Create GiST spatial index
            try {
                jdbcTemplate.execute(
                        "CREATE INDEX IF NOT EXISTS idx_esdemo_geom ON businesses USING GIST (geom)"
                );
                log.info("✅ GiST spatial index created");
            } catch (Exception e) {
                log.warn("Could not create GiST index: {}", e.getMessage());
            }

            // 4. Add full-text search vector column and GIN index
            try {
                jdbcTemplate.execute(
                        "ALTER TABLE businesses ADD COLUMN IF NOT EXISTS search_vector tsvector"
                );
                jdbcTemplate.execute(
                        "UPDATE businesses SET search_vector = to_tsvector('english', coalesce(name,'') || ' ' || coalesce(description,'') || ' ' || coalesce(category,''))"
                );
                log.info("✅ Full-text search_vector column added and populated");
            } catch (Exception e) {
                log.warn("Could not add search_vector: {}", e.getMessage());
            }

            try {
                jdbcTemplate.execute(
                        "CREATE INDEX IF NOT EXISTS idx_esdemo_search ON businesses USING GIN (search_vector)"
                );
                log.info("✅ GIN full-text search index created");
            } catch (Exception e) {
                log.warn("Could not create GIN index: {}", e.getMessage());
            }

            // 5. Location index: try gin_trgm_ops, fallback to btree
            try {
                jdbcTemplate.execute(
                        "CREATE INDEX IF NOT EXISTS idx_esdemo_location_names ON businesses USING gin (lower(location_names) gin_trgm_ops)"
                );
            } catch (Exception e) {
                try {
                    jdbcTemplate.execute(
                            "CREATE INDEX IF NOT EXISTS idx_esdemo_loc_names ON businesses (location_names)"
                    );
                } catch (Exception ignored) {
                }
            }

            // 6. Seed data if empty
            if (businessRepository.count() == 0) {
                seedData();
            } else {
                log.info("ℹ️ Data already exists — skipping seed");
            }

            // 8. Refresh search_vector/geom via UPDATE SQL
            jdbcTemplate.execute(
                    "UPDATE businesses SET search_vector = to_tsvector('english', coalesce(name,'') || ' ' || coalesce(description,'') || ' ' || coalesce(category,''))"
            );
            jdbcTemplate.execute(
                    "UPDATE businesses SET geom = ST_MakePoint(longitude, latitude)::geography WHERE geom IS NULL"
            );

            // 9. Re-index all businesses into ES (Postgres is source of truth)
            try {
                searchService.reindexAll(businessRepository.findAll());
            } catch (Exception e) {
                log.warn("Reindex failed (ES may not be ready yet): {}", e.getMessage());
            }

        } catch (Exception e) {
            log.error("Data initialization failed: {}", e.getMessage(), e);
        }
    }

    /**
     * Seed ~2000 synthetic restaurants clustered around SF / Manhattan / Bangalore.
     */
    private void seedData() {
        log.info("🌱 Seeding sample data...");

        // --- Users (5) ---
        List<User> users = List.of(
                User.builder().username("alice").displayName("Alice Chen").avatarUrl("👩").createdAt(LocalDateTime.now()).build(),
                User.builder().username("bob").displayName("Bob Martinez").avatarUrl("👨").createdAt(LocalDateTime.now()).build(),
                User.builder().username("carol").displayName("Carol Johnson").avatarUrl("👩‍🦰").createdAt(LocalDateTime.now()).build(),
                User.builder().username("dave").displayName("Dave Kim").avatarUrl("👨‍🦱").createdAt(LocalDateTime.now()).build(),
                User.builder().username("eve").displayName("Eve Patel").avatarUrl("👩‍🦳").createdAt(LocalDateTime.now()).build()
        );
        userRepository.saveAll(users);
        log.info("  ✅ Created {} users", users.size());

        // --- Location Areas (4) ---
        List<LocationArea> locations = List.of(
                LocationArea.builder().name("san_francisco").displayName("San Francisco").type("city")
                        .minLat(37.70).minLon(-122.52).maxLat(37.83).maxLon(-122.35).build(),
                LocationArea.builder().name("manhattan").displayName("Manhattan").type("city")
                        .minLat(40.70).minLon(-74.02).maxLat(40.88).maxLon(-73.90).build(),
                LocationArea.builder().name("bangalore").displayName("Bangalore").type("city")
                        .minLat(12.90).minLon(77.55).maxLat(13.05).maxLon(77.65).build(),
                LocationArea.builder().name("bay_area").displayName("Bay Area").type("region")
                        .minLat(37.40).minLon(-122.60).maxLat(38.00).maxLon(-121.80).build()
        );
        locationAreaRepository.saveAll(locations);
        log.info("  ✅ Created {} location areas", locations.size());

        // --- Businesses (~2000) ---
        Random random = new Random(42);

        String[] adjectives = {"Spicy", "Golden", "Urban", "Sunny", "Royal", "Crispy", "Fresh", "Happy", "Blue", "Red"};
        String[] cuisines = {"Dragon", "Taco", "Curry", "Sushi", "Pizza", "Burger", "Noodle", "Biryani", "Pasta", "Dosa"};
        String[] suffixes = {"House", "Kitchen", "Grill", "Corner", "Garden", "Express", "Palace", "Hut", "Bar", "Cafe", "Spot"};
        String[] categories = {"restaurant", "cafe", "bakery", "bar", "park"};
        String[] priceRanges = {"$", "$$", "$$$", "$$$$"};
        String[] dishes = {"biryani", "tacos", "sushi", "pizza", "burgers", "noodles", "curry", "pasta", "dosa", "butter chicken"};
        String[] features = {"cozy seating", "live music", "rooftop views", "quick service", "family-friendly vibe", "artisanal bread"};

        double[][] clusterCenters = {
                {37.7749, -122.4194}, // SF
                {40.7128, -74.0060},  // Manhattan
                {12.9716, 77.5946}    // Bangalore
        };
        int[] clusterCounts = {700, 700, 600};
        String[] clusterLocationNames = {"san_francisco,bay_area", "manhattan,new_york", "bangalore,koramangala"};
        String[] clusterCitySuffix = {"San Francisco, CA", "New York, NY", "Bangalore, KA"};

        List<Business> businesses = new ArrayList<>(2000);

        for (int c = 0; c < clusterCenters.length; c++) {
            double centerLat = clusterCenters[c][0];
            double centerLon = clusterCenters[c][1];
            String locationNames = clusterLocationNames[c];
            String citySuffix = clusterCitySuffix[c];

            for (int i = 0; i < clusterCounts[c]; i++) {
                // Jitter: 60% inside ±0.009° (~1km), 40% uniform ±0.04°
                double latJitter;
                double lonJitter;
                if (random.nextDouble() < 0.6) {
                    latJitter = (random.nextDouble() * 2 - 1) * 0.009;
                    lonJitter = (random.nextDouble() * 2 - 1) * 0.009;
                } else {
                    latJitter = (random.nextDouble() * 2 - 1) * 0.04;
                    lonJitter = (random.nextDouble() * 2 - 1) * 0.04;
                }
                double lat = centerLat + latJitter;
                double lon = centerLon + lonJitter;

                String adjective = adjectives[random.nextInt(adjectives.length)];
                String cuisine = cuisines[random.nextInt(cuisines.length)];
                String suffix = suffixes[random.nextInt(suffixes.length)];
                String name = adjective + " " + cuisine + " " + suffix;

                String dish = dishes[random.nextInt(dishes.length)];
                String feature = features[random.nextInt(features.length)];
                String description = "Authentic " + cuisine.toLowerCase() + " flavors with " + adjective.toLowerCase() + " spices. Famous for " + dish + " and " + feature + ".";

                String category = categories[random.nextInt(categories.length)];
                String priceRange = priceRanges[random.nextInt(priceRanges.length)];

                Business business = Business.builder()
                        .name(name)
                        .description(description)
                        .address((100 + random.nextInt(900)) + " Main St, " + citySuffix)
                        .latitude(lat)
                        .longitude(lon)
                        .category(category)
                        .priceRange(priceRange)
                        .phone("(555) 555-" + String.format("%04d", random.nextInt(10000)))
                        .imageUrl("🍽️")
                        .locationNames(locationNames)
                        .avgRating(0.0)
                        .numRatings(0)
                        .createdAt(LocalDateTime.now().minusDays(random.nextInt(365)))
                        .build();
                businesses.add(business);
            }
        }

        businessRepository.saveAll(businesses);
        log.info("  ✅ Created {} businesses", businesses.size());

        // Re-fetch to get generated IDs for review FK
        List<Business> savedBusinesses = businessRepository.findAll();

        // --- Reviews (2-5 per business) ---
        String[] reviewTexts = {
                "Absolutely loved it! The atmosphere was amazing and the staff was super friendly.",
                "Great food, decent prices. Will definitely come back.",
                "Overrated in my opinion. The line was too long and the food was just okay.",
                "Best meal I've had in months. The flavors were incredible.",
                "Solid spot. Nothing mind-blowing but consistently good.",
                "The service was slow but the food made up for it.",
                "Hidden gem! Not many people know about this place but it's fantastic.",
                "Tourist trap. Overpriced and underwhelming.",
                "I've been coming here for years and it never disappoints.",
                "Perfect for a date night. Romantic ambiance and excellent wine list.",
                "The coffee is good but the pastries are dry. Maybe I came on a bad day.",
                "Incredible value for the quality. Highly recommend.",
                "Too noisy and crowded. Could barely hear my conversation.",
                "The staff went above and beyond. Five stars for service alone.",
                "Average experience. Not bad, not great. Just fine."
        };

        int reviewCount = 0;
        for (Business business : savedBusinesses) {
            int numReviews = 2 + random.nextInt(4); // 2-5
            for (int i = 0; i < numReviews; i++) {
                User user = users.get(random.nextInt(users.size()));
                if (reviewRepository.findByUserIdAndBusinessId(user.getId(), business.getId()).isPresent()) {
                    continue;
                }
                int rating = 3 + random.nextInt(3); // 3-5
                if (random.nextDouble() < 0.15) {
                    rating = 1 + random.nextInt(2); // 15% low 1-2
                }
                String text = random.nextDouble() < 0.7 ? reviewTexts[random.nextInt(reviewTexts.length)] : null;

                Review review = Review.builder()
                        .rating(rating)
                        .text(text)
                        .business(business)
                        .userId(user.getId())
                        .userDisplayName(user.getDisplayName())
                        .createdAt(LocalDateTime.now().minusDays(random.nextInt(30)))
                        .build();
                reviewRepository.save(review);
                reviewCount++;
            }
            updateBusinessAvgRating(business);
        }
        log.info("  ✅ Created {} reviews", reviewCount);
        log.info("🎉 Data seeding complete!");
    }

    /**
     * Recalculate and save avg rating for a business.
     */
    private void updateBusinessAvgRating(Business business) {
        List<Review> reviews = reviewRepository.findByBusinessIdOrderByCreatedAtDesc(
                business.getId(), org.springframework.data.domain.PageRequest.of(0, Integer.MAX_VALUE)
        ).getContent();
        if (reviews.isEmpty()) {
            business.setAvgRating(0.0);
            business.setNumRatings(0);
        } else {
            double avg = reviews.stream().mapToInt(Review::getRating).average().orElse(0.0);
            business.setAvgRating(Math.round(avg * 10.0) / 10.0);
            business.setNumRatings(reviews.size());
        }
        businessRepository.save(business);
    }
}
