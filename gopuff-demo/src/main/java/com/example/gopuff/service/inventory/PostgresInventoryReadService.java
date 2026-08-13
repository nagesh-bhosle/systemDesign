package com.example.gopuff.service.inventory;

import com.example.gopuff.entity.Inventory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.Collection;
import java.util.List;

@Service
@ConditionalOnProperty(name = "gopuff.inventory.read-path", havingValue = "postgres")
public class PostgresInventoryReadService implements InventoryReadService {

    private final DbInventoryLoader loader;

    public PostgresInventoryReadService(DbInventoryLoader loader) {
        this.loader = loader;
    }

    @Override
    public List<InventorySnapshot> loadForDcs(Collection<Long> dcIds) {
        return loader.loadForDcs(dcIds);
    }

    @Override
    public void invalidateDcs(Collection<Long> dcIds) {
        // no cache
    }

    static InventorySnapshot toSnapshot(Inventory row) {
        return new InventorySnapshot(
                row.getId(),
                row.getItem().getId(),
                row.getItem().getSku(),
                row.getItem().getName(),
                row.getItem().getDescription(),
                row.getDistributionCenter().getId(),
                row.getDistributionCenter().getName(),
                row.getQuantity()
        );
    }
}
