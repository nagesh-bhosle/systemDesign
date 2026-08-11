package com.example.yelp.dto;

import lombok.*;

import java.util.List;

/**
 * Paginated search response.
 */
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class SearchResult<T> {
    private List<T> results;
    private long total;
    private int page;
    private int pageSize;
    private int totalPages;
}