package com.example.esdemo.dto;

import lombok.*;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class CreateReviewRequest {
    private Long userId;
    private Integer rating;   // 1-5
    private String text;      // optional
}
