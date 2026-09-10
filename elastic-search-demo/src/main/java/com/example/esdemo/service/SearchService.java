package com.example.esdemo.service;

import com.example.esdemo.dto.BusinessDto;
import com.example.esdemo.dto.SearchResult;
import com.example.esdemo.dto.SuggestResult;
import com.example.esdemo.entity.Business;

import java.util.List;
import java.util.Map;
import java.util.Optional;

public interface SearchService {

    SearchResult<BusinessDto> searchByGeo(String query, double lat, double lon,
                                          double radiusMeters, String category,
                                          String sortBy, int page, int pageSize);

    SearchResult<BusinessDto> searchByLocationName(String query, String locationName,
                                                    String category, int page, int pageSize);

    Optional<Business> getById(Long id);

    List<String> getAllCategories();

    BusinessDto toDto(Business b, Double lat, Double lon);

    List<SuggestResult> suggest(String q);

    Map<String, Object> aggregations(Double lat, Double lon, Double radius);

    SearchResult<BusinessDto> fuzzySearch(String q, int page, int pageSize);

    void indexBusiness(Business business);

    void deleteBusiness(Long id);

    void reindexAll(Iterable<Business> businesses);
}
