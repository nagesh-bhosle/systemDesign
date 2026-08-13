package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.UUID;

@Service
@ConditionalOnBean(StringRedisTemplate.class)
public class DistributedLockBookingService {

    private final StringRedisTemplate redis;
    private final UnsafeBookingService unsafeBookingService;

    public DistributedLockBookingService(StringRedisTemplate redis, UnsafeBookingService unsafeBookingService) {
        this.redis = redis;
        this.unsafeBookingService = unsafeBookingService;
    }

    public BookOutcome bookWithLock(Long seatId, Long userId, int delayMs, int ttlMs, DemoClock clock) {
        String key = "booking-lock:seat:" + seatId;
        String token = userId + ":" + UUID.randomUUID();
        clock.event(userId, "Redis SET " + key + " NX PX " + ttlMs);
        Boolean acquired = redis.opsForValue().setIfAbsent(key, token, Duration.ofMillis(ttlMs));
        if (!Boolean.TRUE.equals(acquired)) {
            clock.event(userId, "Lock NOT acquired — another instance holds it");
            return BookOutcome.fail("System busy, please try again! (distributed lock)");
        }
        try {
            clock.event(userId, "Lock acquired — only one process in the cluster can book this seat now");
            return unsafeBookingService.book(seatId, userId, delayMs, clock);
        } finally {
            String current = redis.opsForValue().get(key);
            if (token.equals(current)) {
                redis.delete(key);
                clock.event(userId, "Redis UNLOCK");
            }
        }
    }
}
