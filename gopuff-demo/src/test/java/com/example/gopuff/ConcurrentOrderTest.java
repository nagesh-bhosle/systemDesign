package com.example.gopuff;

import com.example.gopuff.entity.Inventory;
import com.example.gopuff.entity.Item;
import com.example.gopuff.repository.DistributionCenterRepository;
import com.example.gopuff.repository.InventoryRepository;
import com.example.gopuff.repository.ItemRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class ConcurrentOrderTest {

    @Autowired
    TestRestTemplate rest;

    @Autowired
    ItemRepository itemRepository;

    @Autowired
    InventoryRepository inventoryRepository;

    @Autowired
    DistributionCenterRepository dcRepository;

    @Test
    void twoBuyersCannotPurchaseTheSameLastUnit() throws Exception {
        Item lastUnit = itemRepository.findBySku("LAST-UNIT").orElseThrow();
        List<Long> dcIds = dcRepository.findAll().stream().map(dc -> dc.getId()).toList();
        Inventory stock = inventoryRepository.findByDcIds(dcIds).stream()
                .filter(row -> row.getItem().getId().equals(lastUnit.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(stock.getQuantity()).isEqualTo(1);

        Map<String, Object> line = Map.of("itemId", lastUnit.getId(), "quantity", 1);
        Map<String, Object> bodyA = Map.of("userId", "alice", "lat", 39.9526, "lon", -75.1652, "lines", List.of(line));
        Map<String, Object> bodyB = Map.of("userId", "bob", "lat", 39.9526, "lon", -75.1652, "lines", List.of(line));

        CountDownLatch start = new CountDownLatch(1);
        AtomicInteger created = new AtomicInteger();
        AtomicInteger conflict = new AtomicInteger();

        Thread t1 = new Thread(() -> postOrder(start, bodyA, created, conflict));
        Thread t2 = new Thread(() -> postOrder(start, bodyB, created, conflict));
        t1.start();
        t2.start();
        start.countDown();
        t1.join();
        t2.join();

        assertThat(created.get()).isEqualTo(1);
        assertThat(conflict.get()).isEqualTo(1);
        assertThat(inventoryRepository.findById(stock.getId()).orElseThrow().getQuantity()).isZero();
    }

    private void postOrder(CountDownLatch start, Map<String, Object> body, AtomicInteger created, AtomicInteger conflict) {
        try {
            start.await();
            ResponseEntity<String> response = rest.postForEntity("/api/orders", body, String.class);
            if (response.getStatusCode() == HttpStatus.CREATED) {
                created.incrementAndGet();
            } else if (response.getStatusCode() == HttpStatus.CONFLICT) {
                conflict.incrementAndGet();
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
