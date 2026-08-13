package com.example.gopuff.service.order;

import com.example.gopuff.dto.PlaceOrderRequest;
import com.example.gopuff.entity.DistributionCenter;
import com.example.gopuff.service.inventory.InventorySnapshot;
import com.example.gopuff.service.nearby.NearbyDc;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class StockAllocatorTest {

    @Test
    void allocatesFromNearestDcFirst() {
        DistributionCenter near = dc(1L);
        DistributionCenter far = dc(2L);
        List<NearbyDc> nearby = List.of(new NearbyDc(near, 1, 2), new NearbyDc(far, 8, 16));
        List<InventorySnapshot> stock = List.of(
                snap(10L, 100L, 1L, 2),
                snap(11L, 100L, 2L, 5)
        );
        var plan = StockAllocator.allocate(
                nearby,
                List.of(new PlaceOrderRequest.OrderLineRequest(100L, 3)),
                stock);
        assertThat(plan).hasSize(2);
        assertThat(plan.get(0).inventoryId()).isEqualTo(10L);
        assertThat(plan.get(0).quantity()).isEqualTo(2);
        assertThat(plan.get(1).inventoryId()).isEqualTo(11L);
        assertThat(plan.get(1).quantity()).isEqualTo(1);
    }

    @Test
    void failsEntireOrderWhenShort() {
        DistributionCenter near = dc(1L);
        assertThatThrownBy(() -> StockAllocator.allocate(
                List.of(new NearbyDc(near, 1, 2)),
                List.of(new PlaceOrderRequest.OrderLineRequest(100L, 5)),
                List.of(snap(10L, 100L, 1L, 2))
        )).isInstanceOf(InsufficientInventoryException.class);
    }

    private static DistributionCenter dc(Long id) {
        DistributionCenter dc = new DistributionCenter();
        dc.setId(id);
        dc.setName("DC-" + id);
        return dc;
    }

    private static InventorySnapshot snap(Long invId, Long itemId, Long dcId, int qty) {
        return new InventorySnapshot(invId, itemId, "SKU", "Name", "d", dcId, "DC", qty);
    }
}
