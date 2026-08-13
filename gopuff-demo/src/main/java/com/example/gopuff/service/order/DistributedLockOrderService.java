package com.example.gopuff.service.order;

import com.example.gopuff.config.GopuffProperties;
import com.example.gopuff.dto.PlaceOrderRequest;
import com.example.gopuff.entity.CustomerOrder;
import com.example.gopuff.repository.InventoryRepository;
import com.example.gopuff.service.nearby.NearbyDc;
import com.example.gopuff.service.nearby.NearbyService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * "Good" interview path: Redis locks on sorted inventory keys, then DB writes.
 * Keys are sorted to avoid AB-BA deadlock. Lock TTL covers a process crash
 * while holding locks (inventory and orders still share one DB transaction).
 */
@Service
@ConditionalOnProperty(name = "gopuff.orders.consistency", havingValue = "distributed-lock")
public class DistributedLockOrderService implements OrderService {

    private final NearbyService nearbyService;
    private final InventoryRepository inventoryRepository;
    private final OrderPersistence persistence;
    private final StringRedisTemplate redis;
    private final Duration lockTtl;

    public DistributedLockOrderService(NearbyService nearbyService,
                                       InventoryRepository inventoryRepository,
                                       OrderPersistence persistence,
                                       StringRedisTemplate redis,
                                       GopuffProperties properties) {
        this.nearbyService = nearbyService;
        this.inventoryRepository = inventoryRepository;
        this.persistence = persistence;
        this.redis = redis;
        this.lockTtl = Duration.ofMillis(properties.getOrders().getLockTtlMs());
    }

    @Override
    public CustomerOrder place(PlaceOrderRequest request) {
        List<NearbyDc> nearby = nearbyService.findNearby(request.lat(), request.lon());
        if (nearby.isEmpty()) {
            throw new InsufficientInventoryException("No distribution center can deliver to this location in time");
        }
        List<Long> dcIds = nearby.stream().map(n -> n.dc().getId()).toList();
        List<Long> lockIds = request.lines().stream()
                .flatMap(line -> inventoryRepository.findByItemAndDcIds(line.itemId(), dcIds).stream())
                .map(inv -> inv.getId())
                .distinct()
                .sorted()
                .toList();

        String token = UUID.randomUUID().toString();
        List<String> held = new ArrayList<>();
        try {
            for (Long id : lockIds) {
                String key = "lock:inv:" + id;
                Boolean ok = redis.opsForValue().setIfAbsent(key, token, lockTtl);
                if (!Boolean.TRUE.equals(ok)) {
                    throw new ConcurrentOrderException("Could not acquire inventory lock for " + id);
                }
                held.add(key);
            }
            return persistence.placeReadCommitted(request);
        } finally {
            for (String key : held) {
                String current = redis.opsForValue().get(key);
                if (token.equals(current)) {
                    redis.delete(key);
                }
            }
        }
    }
}
