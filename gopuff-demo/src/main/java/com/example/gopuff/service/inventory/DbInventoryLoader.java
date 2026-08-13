package com.example.gopuff.service.inventory;

import com.example.gopuff.repository.InventoryRepository;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.List;

@Component
public class DbInventoryLoader {

    private final InventoryRepository inventoryRepository;

    public DbInventoryLoader(InventoryRepository inventoryRepository) {
        this.inventoryRepository = inventoryRepository;
    }

    public List<InventorySnapshot> loadForDcs(Collection<Long> dcIds) {
        if (dcIds.isEmpty()) {
            return List.of();
        }
        return inventoryRepository.findByDcIds(dcIds).stream()
                .map(PostgresInventoryReadService::toSnapshot)
                .toList();
    }
}
