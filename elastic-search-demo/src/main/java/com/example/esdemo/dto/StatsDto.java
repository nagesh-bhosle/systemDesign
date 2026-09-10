package com.example.esdemo.dto;

import lombok.*;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class StatsDto {
    private long postgresCount;
    private long elasticsearchCount;
    private String esHealth;
    private boolean indexExists;
}
