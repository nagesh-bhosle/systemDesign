package com.example.esdemo.service;

import com.example.esdemo.dto.BusinessDto;
import com.example.esdemo.dto.SearchResult;
import com.example.esdemo.dto.SuggestResult;
import com.example.esdemo.entity.Business;
import com.example.esdemo.repository.BusinessRepository;
import com.example.esdemo.repository.LocationAreaRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
public class PostgresSearchService implements SearchService {

    private final BusinessRepository businessRepository;
    private final LocationAreaRepository locationAreaRepository;

    public PostgresSearchService(BusinessRepository businessRepository,
                                 LocationAreaRepository locationAreaRepository) {
        this.businessRepository = businessRepository;
        this.locationAreaRepository = locationAreaRepository;
    }

    @Override
    public SearchResult<BusinessDto> searchByGeo(String query, double lat, double lon,
                                                  double radiusMeters, String category,
                                                  String sortBy, int page, int pageSize) {
        Pageable pageable = PageRequest.of(page, pageSize);
        Page<Business> businesses = businessRepository.searchBusinesses(
                query, lat, lon, radiusMeters, category, sortBy, pageable
        );
        List<BusinessDto> dtos = businesses.getContent().stream()
                .map(b -> toDto(b, lat, lon))
                .toList();
        return SearchResult.<BusinessDto>builder()
                .results(dtos)
                .total(businesses.getTotalElements())
                .page(page)
                .pageSize(pageSize)
                .totalPages(businesses.getTotalPages())
                .build();
    }

    @Override
    public SearchResult<BusinessDto> searchByLocationName(String query, String locationName,
                                                          String category, int page, int pageSize) {
        Pageable pageable = PageRequest.of(page, pageSize);
        Page<Business> businesses = businessRepository.searchByLocationName(
                query, locationName, category, pageable
        );
        List<BusinessDto> dtos = businesses.getContent().stream()
                .map(b -> toDto(b, null, null))
                .toList();
        return SearchResult.<BusinessDto>builder()
                .results(dtos)
                .total(businesses.getTotalElements())
                .page(page)
                .pageSize(pageSize)
                .totalPages(businesses.getTotalPages())
                .build();
    }

    @Override
    public Optional<Business> getById(Long id) {
        return businessRepository.findById(id);
    }

    @Override
    public List<String> getAllCategories() {
        return businessRepository.findAll().stream()
                .map(Business::getCategory)
                .distinct()
                .sorted()
                .toList();
    }

    @Override
    public BusinessDto toDto(Business b, Double lat, Double lon) {
        Double distance = null;
        if (lat != null && lon != null) {
            distance = haversine(lat, lon, b.getLatitude(), b.getLongitude());
        }
        return BusinessDto.builder()
                .id(b.getId())
                .name(b.getName())
                .description(b.getDescription())
                .address(b.getAddress())
                .latitude(b.getLatitude())
                .longitude(b.getLongitude())
                .category(b.getCategory())
                .avgRating(b.getAvgRating())
                .numRatings(b.getNumRatings())
                .phone(b.getPhone())
                .priceRange(b.getPriceRange())
                .imageUrl(b.getImageUrl())
                .locationNames(b.getLocationNameList())
                .distanceMeters(distance)
                .build();
    }

    @Override
    public List<SuggestResult> suggest(String q) {
        if (q == null || q.isBlank()) return List.of();
        String lower = q.toLowerCase();
        return businessRepository.findAll().stream()
                .filter(b -> b.getName() != null && b.getName().toLowerCase().contains(lower))
                .limit(8)
                .map(b -> SuggestResult.builder()
                        .text(b.getName())
                        .category(b.getCategory())
                        .id(b.getId())
                        .build())
                .toList();
    }

    @Override
    public Map<String, Object> aggregations(Double lat, Double lon, Double radius) {
        Map<String, Long> categoryCounts = businessRepository.findAll().stream()
                .collect(Collectors.groupingBy(Business::getCategory, Collectors.counting()));
        return Map.of(
                "note", "Postgres aggregations via SQL GROUP BY",
                "categories", categoryCounts
        );
    }

    @Override
    public SearchResult<BusinessDto> fuzzySearch(String q, int page, int pageSize) {
        Pageable pageable = PageRequest.of(page, pageSize);
        Page<Business> businesses = businessRepository.searchByLocationName(q, null, null, pageable);
        List<BusinessDto> dtos = businesses.getContent().stream()
                .map(b -> toDto(b, null, null))
                .toList();
        return SearchResult.<BusinessDto>builder()
                .results(dtos)
                .total(businesses.getTotalElements())
                .page(page)
                .pageSize(pageSize)
                .totalPages(businesses.getTotalPages())
                .build();
    }

    @Override
    public void indexBusiness(Business business) {
        // no-op for Postgres
    }

    @Override
    public void deleteBusiness(Long id) {
        // no-op for Postgres
    }

    @Override
    public void reindexAll(Iterable<Business> businesses) {
        // no-op — Postgres uses its own GiST + GIN indexes
    }

    public static double haversine(double lat1, double lon1, double lat2, double lon2) {
        final int R = 6371000; // Earth radius in meters
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }
}
