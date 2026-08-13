package com.example.gopuff.service.order;

import com.example.gopuff.dto.PlaceOrderRequest;
import com.example.gopuff.service.inventory.InventorySnapshot;
import com.example.gopuff.service.nearby.NearbyDc;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class StockAllocator {

    private StockAllocator() {
    }

    public record Allocation(Long inventoryId, Long itemId, Long dcId, int quantity) {
    }

    public static List<Allocation> allocate(List<NearbyDc> nearby,
                                            List<PlaceOrderRequest.OrderLineRequest> lines,
                                            List<InventorySnapshot> stock) {
        Map<Long, Integer> dcRank = new HashMap<>();
        for (int i = 0; i < nearby.size(); i++) {
            dcRank.put(nearby.get(i).dc().getId(), i);
        }

        Map<Long, List<InventorySnapshot>> byItem = new HashMap<>();
        for (InventorySnapshot row : stock) {
            if (!dcRank.containsKey(row.dcId()) || row.quantity() <= 0) {
                continue;
            }
            byItem.computeIfAbsent(row.itemId(), k -> new ArrayList<>()).add(row);
        }
        for (List<InventorySnapshot> rows : byItem.values()) {
            rows.sort(Comparator.comparingInt(s -> dcRank.getOrDefault(s.dcId(), Integer.MAX_VALUE)));
        }

        Map<Long, Integer> remainingByInventory = new HashMap<>();
        for (InventorySnapshot row : stock) {
            remainingByInventory.put(row.inventoryId(), row.quantity());
        }

        List<Allocation> plan = new ArrayList<>();
        for (PlaceOrderRequest.OrderLineRequest line : lines) {
            int needed = line.quantity();
            List<InventorySnapshot> rows = byItem.getOrDefault(line.itemId(), List.of());
            for (InventorySnapshot row : rows) {
                if (needed == 0) {
                    break;
                }
                int available = remainingByInventory.getOrDefault(row.inventoryId(), 0);
                if (available <= 0) {
                    continue;
                }
                int take = Math.min(needed, available);
                plan.add(new Allocation(row.inventoryId(), row.itemId(), row.dcId(), take));
                remainingByInventory.put(row.inventoryId(), available - take);
                needed -= take;
            }
            if (needed > 0) {
                throw new InsufficientInventoryException(
                        "Not enough inventory for item " + line.itemId() + " (short " + needed + ")");
            }
        }
        return plan;
    }
}
