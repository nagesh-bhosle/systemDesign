package com.example.yelp.config;

import com.example.yelp.entity.Business;
import com.example.yelp.entity.LocationArea;
import com.example.yelp.entity.Review;
import com.example.yelp.entity.User;
import com.example.yelp.repository.BusinessRepository;
import com.example.yelp.repository.LocationAreaRepository;
import com.example.yelp.repository.ReviewRepository;
import com.example.yelp.repository.UserRepository;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Random;

/**
 * DataInitializer — runs on application startup.
 *
 * Responsibilities (from the Yelp design doc):
 * 1. Enable PostGIS extension for geospatial queries
 * 2. Create a full-text search vector column (search_vector) on businesses
 * 3. Create a GiST index on the geography point for fast ST_DWithin queries
 * 4. Create a GIN index on the search_vector for fast full-text queries
 * 5. Seed sample data: users, businesses, reviews, location areas
 *
 * This makes the app "one command to run" — everything is preloaded.
 */
@Component
public class DataInitializer {

    private static final Logger log = LoggerFactory.getLogger(DataInitializer.class);

    private final JdbcTemplate jdbcTemplate;
    private final BusinessRepository businessRepository;
    private final ReviewRepository reviewRepository;
    private final UserRepository userRepository;
    private final LocationAreaRepository locationAreaRepository;

    public DataInitializer(JdbcTemplate jdbcTemplate,
                           BusinessRepository businessRepository,
                           ReviewRepository reviewRepository,
                           UserRepository userRepository,
                           LocationAreaRepository locationAreaRepository) {
        this.jdbcTemplate = jdbcTemplate;
        this.businessRepository = businessRepository;
        this.reviewRepository = reviewRepository;
        this.userRepository = userRepository;
        this.locationAreaRepository = locationAreaRepository;
    }

    @PostConstruct
    public void init() {
        try {
            // 1. Enable PostGIS extension
            jdbcTemplate.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            log.info("✅ PostGIS extension enabled");

            // 2. Add a geography column for spatial indexing (if not exists)
            try {
                jdbcTemplate.execute(
                    "ALTER TABLE businesses ADD COLUMN IF NOT EXISTS geom geography(Point, 4326)"
                );
                jdbcTemplate.execute(
                    "UPDATE businesses SET geom = ST_MakePoint(longitude, latitude)::geography " +
                    "WHERE geom IS NULL"
                );
                log.info("✅ Geography column 'geom' added and populated");
            } catch (Exception e) {
                log.warn("Could not add geom column: {}", e.getMessage());
            }

            // 3. Create GiST spatial index for fast ST_DWithin queries
            try {
                jdbcTemplate.execute(
                    "CREATE INDEX IF NOT EXISTS idx_businesses_geom ON businesses USING GIST (geom)"
                );
                log.info("✅ GiST spatial index created");
            } catch (Exception e) {
                log.warn("Could not create GiST index: {}", e.getMessage());
            }

            // 4. Add full-text search vector column
            try {
                jdbcTemplate.execute(
                    "ALTER TABLE businesses ADD COLUMN IF NOT EXISTS search_vector tsvector"
                );
                jdbcTemplate.execute(
                    "UPDATE businesses SET search_vector = " +
                    "to_tsvector('english', coalesce(name,'') || ' ' || coalesce(description,'') || ' ' || coalesce(category,''))"
                );
                log.info("✅ Full-text search_vector column added and populated");
            } catch (Exception e) {
                log.warn("Could not add search_vector: {}", e.getMessage());
            }

            // 5. Create GIN index for full-text search
            try {
                jdbcTemplate.execute(
                    "CREATE INDEX IF NOT EXISTS idx_businesses_search ON businesses USING GIN (search_vector)"
                );
                log.info("✅ GIN full-text search index created");
            } catch (Exception e) {
                log.warn("Could not create GIN index: {}", e.getMessage());
            }

            // 6. Create index on location_names for named-location search
            try {
                jdbcTemplate.execute(
                    "CREATE INDEX IF NOT EXISTS idx_businesses_location_names ON businesses USING gin (lower(location_names) gin_trgm_ops)"
                );
            } catch (Exception e) {
                // trigram extension might not be available — create a simpler index
                try {
                    jdbcTemplate.execute(
                        "CREATE INDEX IF NOT EXISTS idx_businesses_loc_names ON businesses (location_names)"
                    );
                } catch (Exception ignored) {}
            }

            // 7. Seed data if tables are empty
            if (businessRepository.count() == 0) {
                seedData();
            } else {
                log.info("ℹ️ Data already exists — skipping seed");
            }

            // 8. Refresh search vectors after seeding
            jdbcTemplate.execute(
                "UPDATE businesses SET search_vector = " +
                "to_tsvector('english', coalesce(name,'') || ' ' || coalesce(description,'') || ' ' || coalesce(category,''))"
            );
            jdbcTemplate.execute(
                "UPDATE businesses SET geom = ST_MakePoint(longitude, latitude)::geography " +
                "WHERE geom IS NULL"
            );

        } catch (Exception e) {
            log.error("Data initialization failed: {}", e.getMessage(), e);
        }
    }

    /**
     * Seed sample data: 5 users, 20 businesses across SF/NYC, 60+ reviews, 4 location areas.
     */
    private void seedData() {
        log.info("🌱 Seeding sample data...");

        // --- Users ---
        List<User> users = List.of(
            User.builder().username("alice").displayName("Alice Chen").avatarUrl("👩").createdAt(LocalDateTime.now()).build(),
            User.builder().username("bob").displayName("Bob Martinez").avatarUrl("👨").createdAt(LocalDateTime.now()).build(),
            User.builder().username("carol").displayName("Carol Johnson").avatarUrl("👩‍🦰").createdAt(LocalDateTime.now()).build(),
            User.builder().username("dave").displayName("Dave Kim").avatarUrl("👨‍🦱").createdAt(LocalDateTime.now()).build(),
            User.builder().username("eve").displayName("Eve Patel").avatarUrl("👩‍🦳").createdAt(LocalDateTime.now()).build()
        );
        userRepository.saveAll(users);
        log.info("  ✅ Created {} users", users.size());

        // --- Location Areas (bounding boxes for named locations) ---
        List<LocationArea> locations = List.of(
            LocationArea.builder().name("san_francisco").displayName("San Francisco").type("city")
                .minLat(37.70).minLon(-122.52).maxLat(37.83).maxLon(-122.35).build(),
            LocationArea.builder().name("mission_district").displayName("Mission District").type("neighborhood")
                .minLat(37.748).minLon(-122.424).maxLat(37.764).maxLon(-122.408).build(),
            LocationArea.builder().name("manhattan").displayName("Manhattan").type("city")
                .minLat(40.70).minLon(-74.02).maxLat(40.88).maxLon(-73.90).build(),
            LocationArea.builder().name("bay_area").displayName("Bay Area").type("region")
                .minLat(37.40).minLon(-122.60).maxLat(38.00).maxLon(-121.80).build()
        );
        locationAreaRepository.saveAll(locations);
        log.info("  ✅ Created {} location areas", locations.size());

        // --- Businesses (20 across SF and NYC) ---
        List<Business> businesses = List.of(
            // San Francisco — Mission District
            Business.builder().name("Mission Dolores Taco").description("Authentic Mexican tacos and burritos in the heart of the Mission. Famous for carnitas and homemade salsa.").address("2849 24th St, San Francisco, CA").latitude(37.7522).longitude(-122.4157).category("restaurant").priceRange("$$").phone("(415) 555-0101").imageUrl("🌮").locationNames("san_francisco,mission_district,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Dolores Park Cafe").description("Coffee shop overlooking Dolores Park. Great espresso, pastries, and people-watching.").address("501 Dolores St, San Francisco, CA").latitude(37.7619).longitude(-122.4270).category("cafe").priceRange("$").phone("(415) 555-0102").imageUrl("☕").locationNames("san_francisco,mission_district,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Bi-Rite Creamery").description("Small-batch ice cream with seasonal flavors. Lines can be long but worth it.").address("3692 18th St, San Francisco, CA").latitude(37.7618).longitude(-122.4247).category("dessert").priceRange("$$").phone("(415) 555-0103").imageUrl("🍦").locationNames("san_francisco,mission_district,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Foreign Cinema").description("Outdoor courtyard dining with Mediterranean cuisine and projected films in the evening.").address("706 Valencia St, San Francisco, CA").latitude(37.7625).longitude(-122.4218).category("restaurant").priceRange("$$$").phone("(415) 555-0104").imageUrl("🍽️").locationNames("san_francisco,mission_district,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Trick Dog").description("Award-winning cocktail bar with a rotating menu theme. Great vibe and creative drinks.").address("3010 20th St, San Francisco, CA").latitude(37.7597).longitude(-122.4186).category("bar").priceRange("$$").phone("(415) 555-0105").imageUrl("🍸").locationNames("san_francisco,mission_district,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),

            // San Francisco — Other neighborhoods
            Business.builder().name("Tartine Bakery").description("Legendary bread and pastries. The morning bun is a must-try.").address("600 Guerrero St, San Francisco, CA").latitude(37.7615).longitude(-122.4240).category("bakery").priceRange("$$").phone("(415) 555-0106").imageUrl("🥐").locationNames("san_francisco,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Blue Bottle Coffee").description("Single-origin pour-over coffee. Minimalist aesthetic and serious about quality.").address("66 Mint St, San Francisco, CA").latitude(37.7870).longitude(-122.4010).category("cafe").priceRange("$$").phone("(415) 555-0107").imageUrl("☕").locationNames("san_francisco,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("House of Prime Rib").description("Classic San Francisco steakhouse serving only prime rib. Old-school charm.").address("1906 Van Ness Ave, San Francisco, CA").latitude(37.7859).longitude(-122.4210).category("restaurant").priceRange("$$$").phone("(415) 555-0108").imageUrl("🥩").locationNames("san_francisco,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Golden Gate Park Botanical").description("Beautiful botanical garden with rare plants from around the world. Free for SF residents.").address("1199 9th Ave, San Francisco, CA").latitude(37.7670).longitude(-122.4660).category("park").priceRange("$").phone("(415) 555-0109").imageUrl("🌿").locationNames("san_francisco,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Fisherman's Wharf Seafood").description("Fresh Dungeness crab and clam chowder in sourdough bowls. Touristy but iconic.").address("286 Jefferson St, San Francisco, CA").latitude(37.8080).longitude(-122.4170).category("restaurant").priceRange("$$").phone("(415) 555-0110").imageUrl("🦀").locationNames("san_francisco,bay_area").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),

            // Manhattan — NYC
            Business.builder().name("Joe's Pizza").description("Classic New York slice. Thin crust, foldable, and perfectly charred. A Greenwich Village institution.").address("7 Carmine St, New York, NY").latitude(40.7308).longitude(-74.0023).category("restaurant").priceRange("$").phone("(212) 555-0201").imageUrl("🍕").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Katz's Delicatessen").description("Pastrami on rye since 1888. Legendary deli and cultural icon. Send that to me!").address("205 E Houston St, New York, NY").latitude(40.7223).longitude(-73.9874).category("restaurant").priceRange("$$").phone("(212) 555-0202").imageUrl("🥪").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Blue Bottle Coffee NYC").description("Third-wave coffee in Chelsea. Carefully sourced and expertly brewed.").address("76 8th Ave, New York, NY").latitude(40.7411).longitude(-74.0040).category("cafe").priceRange("$$").phone("(212) 555-0203").imageUrl("☕").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Le Bernardin").description("Three-Michelin-star seafood restaurant. Elegant tasting menus and impeccable service.").address("155 W 51st St, New York, NY").latitude(40.7614).longitude(-73.9820).category("restaurant").priceRange("$$$$").phone("(212) 555-0204").imageUrl("🐟").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Central Park Boathouse").description("Romantic lakeside dining in Central Park. Seasonal American cuisine with stunning views.").address("E 72nd St & Park Dr N, New York, NY").latitude(40.7740).longitude(-73.9700).category("restaurant").priceRange("$$$").phone("(212) 555-0205").imageUrl("🚣").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Dead Rabbit Grocery").description("Award-winning cocktail bar in the Financial District. Irish-inspired with an extensive drink menu.").address("30 Water St, New York, NY").latitude(40.7030).longitude(-74.0090).category("bar").priceRange("$$").phone("(212) 555-0206").imageUrl("🍺").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Dominique Ansel Bakery").description("Home of the Cronut. Innovative pastries and desserts from a James Beard winner.").address("189 Spring St, New York, NY").latitude(40.7258).longitude(-74.0036).category("bakery").priceRange("$$").phone("(212) 555-0207").imageUrl("🧁").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Chelsea Market Food Hall").description("Indoor food hall with diverse vendors. Everything from tacos to lobster to artisanal chocolate.").address("75 9th Ave, New York, NY").latitude(40.7420).longitude(-74.0060).category("restaurant").priceRange("$$").phone("(212) 555-0208").imageUrl("🏪").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("Washington Square Diner").description("Classic NYC diner experience. Cheap eats, generous portions, open late.").address("147 W 4th St, New York, NY").latitude(40.7300).longitude(-74.0000).category("restaurant").priceRange("$").phone("(212) 555-0209").imageUrl("🍽️").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build(),
            Business.builder().name("High Line Park Walk").description("Elevated park built on a historic freight rail line. Beautiful views and public art installations.").address("Gansevoort St, New York, NY").latitude(40.7400).longitude(-74.0090).category("park").priceRange("$").phone("(212) 555-0210").imageUrl("🌳").locationNames("manhattan,new_york").avgRating(0.0).numRatings(0).createdAt(LocalDateTime.now()).build()
        );
        businessRepository.saveAll(businesses);
        log.info("  ✅ Created {} businesses", businesses.size());

        // --- Reviews (60+ reviews across businesses) ---
        Random random = new Random(42); // deterministic for reproducibility
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
        for (Business business : businesses) {
            // Each business gets 2-6 reviews
            int numReviews = 2 + random.nextInt(5);
            for (int i = 0; i < numReviews; i++) {
                User user = users.get(random.nextInt(users.size()));
                // Skip if user already reviewed this business (enforce constraint in seed too)
                if (reviewRepository.findByUserIdAndBusinessId(user.getId(), business.getId()).isPresent()) {
                    continue;
                }
                int rating = 3 + random.nextInt(3); // 3-5 stars (skew positive)
                if (random.nextDouble() < 0.15) rating = 1 + random.nextInt(2); // 15% chance of low rating
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
            // Update business avgRating
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