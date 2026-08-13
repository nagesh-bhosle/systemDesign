package com.example.gopuff.service.inventory;

import java.util.Collection;
import java.util.List;

public interface InventoryReadService {
    List<InventorySnapshot> loadForDcs(Collection<Long> dcIds);

    void invalidateDcs(Collection<Long> dcIds);
}
