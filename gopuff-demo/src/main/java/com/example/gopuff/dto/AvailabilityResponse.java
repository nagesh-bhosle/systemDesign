package com.example.gopuff.dto;

import java.util.List;

public record AvailabilityResponse(
        double lat,
        double lon,
        List<NearbyDcDto> nearbyDcs,
        List<ItemAvailabilityDto> items,
        int page,
        int size,
        long totalItems
) {
    public record NearbyDcDto(Long id, String name, String regionId, double miles, double driveMinutes) {
    }

    public record ItemAvailabilityDto(
            Long itemId,
            String sku,
            String name,
            String description,
            int quantity,
            List<DcQuantityDto> byDc
    ) {
    }

    public record DcQuantityDto(Long dcId, String dcName, int quantity) {
    }
}
