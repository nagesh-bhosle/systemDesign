package com.example.gopuff.dto;

import java.time.Instant;
import java.util.List;

public record OrderDto(
        Long id,
        String userId,
        String status,
        Instant createdAt,
        double lat,
        double lon,
        List<OrderLineDto> lines
) {
    public record OrderLineDto(Long itemId, String itemName, Long dcId, String dcName, int quantity) {
    }
}
