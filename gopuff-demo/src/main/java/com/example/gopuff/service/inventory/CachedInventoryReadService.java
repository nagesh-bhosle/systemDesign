package com.example.gopuff.service.inventory;

import com.example.gopuff.config.GopuffProperties;
import com.example.gopuff.repository.InventoryRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

@Service
@ConditionalOnProperty(name = "gopuff.inventory.read-path", havingValue = "cache", matchIfMissing = true)
public class CachedInventoryReadService implements InventoryReadService {

    private static final TypeReference<List<InventorySnapshot>> LIST = new TypeReference<>() {
    };

    private final InventoryRepository inventoryRepository;
    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final Duration ttl;

    public CachedInventoryReadService(InventoryRepository inventoryRepository,
                                      StringRedisTemplate redis,
                                      ObjectMapper objectMapper,
                                      GopuffProperties properties) {
        this.inventoryRepository = inventoryRepository;
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.ttl = Duration.ofSeconds(properties.getCache().getTtlSeconds());
    }

    @Override
    public List<InventorySnapshot> loadForDcs(Collection<Long> dcIds) {
        List<InventorySnapshot> all = new ArrayList<>();
        for (Long dcId : dcIds) {
            all.addAll(loadDc(dcId));
        }
        return all;
    }

    private List<InventorySnapshot> loadDc(Long dcId) {
        String key = key(dcId);
        try {
            String cached = redis.opsForValue().get(key);
            if (cached != null) {
                return objectMapper.readValue(cached, LIST);
            }
        } catch (Exception ignored) {
            // fall through to DB
        }
        List<InventorySnapshot> fresh = inventoryRepository.findByDcIds(List.of(dcId)).stream()
                .map(PostgresInventoryReadService::toSnapshot)
                .toList();
        try {
            redis.opsForValue().set(key, objectMapper.writeValueAsString(fresh), ttl);
        } catch (Exception ignored) {
            // still return DB data
        }
        return fresh;
    }

    @Override
    public void invalidateDcs(Collection<Long> dcIds) {
        for (Long dcId : dcIds) {
            redis.delete(key(dcId));
        }
    }

    static String key(Long dcId) {
        return "inv:dc:" + dcId;
    }
}
