package com.example.gopuff.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.util.List;

public record PlaceOrderRequest(
        @NotNull String userId,
        double lat,
        double lon,
        @NotEmpty @Valid List<OrderLineRequest> lines
) {
    public record OrderLineRequest(@NotNull Long itemId, @Min(1) int quantity) {
    }
}
