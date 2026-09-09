package com.example.esdemo.dto;

import lombok.*;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class SuggestResult {
    private String text;
    private String category;
    private Long id;
}
