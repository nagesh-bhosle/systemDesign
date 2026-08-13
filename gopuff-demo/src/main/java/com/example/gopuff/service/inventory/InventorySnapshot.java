package com.example.gopuff.service.inventory;

public record InventorySnapshot(
        Long inventoryId,
        Long itemId,
        String sku,
        String name,
        String description,
        Long dcId,
        String dcName,
        int quantity
) {
}
