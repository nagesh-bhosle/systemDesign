package com.example.gopuff.service;

import com.example.gopuff.dto.AvailabilityResponse;
import com.example.gopuff.dto.AvailabilityResponse.DcQuantityDto;
import com.example.gopuff.dto.AvailabilityResponse.ItemAvailabilityDto;
import com.example.gopuff.dto.AvailabilityResponse.NearbyDcDto;
import com.example.gopuff.service.inventory.InventoryReadService;
import com.example.gopuff.service.inventory.InventorySnapshot;
import com.example.gopuff.service.nearby.NearbyDc;
import com.example.gopuff.service.nearby.NearbyService;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class AvailabilityService {

    private final NearbyService nearbyService;
    private final InventoryReadService inventoryReadService;

    public AvailabilityService(NearbyService nearbyService, InventoryReadService inventoryReadService) {
        this.nearbyService = nearbyService;
        this.inventoryReadService = inventoryReadService;
    }

    public AvailabilityResponse availability(double lat, double lon, int page, int size) {
        List<NearbyDc> nearby = nearbyService.findNearby(lat, lon);
        List<NearbyDcDto> nearbyDtos = nearby.stream()
                .map(n -> new NearbyDcDto(
                        n.dc().getId(),
                        n.dc().getName(),
                        n.dc().getRegionId(),
                        round(n.miles()),
                        round(n.driveMinutes())))
                .toList();

        if (nearby.isEmpty()) {
            return new AvailabilityResponse(lat, lon, nearbyDtos, List.of(), page, size, 0);
        }

        List<Long> dcIds = nearby.stream().map(n -> n.dc().getId()).toList();
        List<InventorySnapshot> stock = inventoryReadService.loadForDcs(dcIds);

        Map<Long, ItemAvailabilityDto> byItem = new LinkedHashMap<>();
        for (InventorySnapshot row : stock) {
            if (row.quantity() <= 0) {
                continue;
            }
            ItemAvailabilityDto existing = byItem.get(row.itemId());
            List<DcQuantityDto> byDc = existing == null ? new ArrayList<>() : new ArrayList<>(existing.byDc());
            byDc.add(new DcQuantityDto(row.dcId(), row.dcName(), row.quantity()));
            int total = (existing == null ? 0 : existing.quantity()) + row.quantity();
            byItem.put(row.itemId(), new ItemAvailabilityDto(
                    row.itemId(), row.sku(), row.name(), row.description(), total, byDc));
        }

        List<ItemAvailabilityDto> items = new ArrayList<>(byItem.values());
        items.sort(Comparator.comparing(ItemAvailabilityDto::name, String.CASE_INSENSITIVE_ORDER));
        long total = items.size();
        int from = Math.min(page * size, items.size());
        int to = Math.min(from + size, items.size());
        return new AvailabilityResponse(lat, lon, nearbyDtos, items.subList(from, to), page, size, total);
    }

    private static double round(double value) {
        return Math.round(value * 10.0) / 10.0;
    }
}
