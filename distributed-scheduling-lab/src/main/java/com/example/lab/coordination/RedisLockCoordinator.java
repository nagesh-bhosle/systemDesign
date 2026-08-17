package com.example.lab.coordination;

import com.example.lab.domain.Message;
import com.example.lab.domain.MessageStatus;
import com.example.lab.domain.MessageType;
import com.example.lab.repo.MessageRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Strategy 1 — Redis distributed lock, used for INTRADAY messages.
 *
 * Semantics: one lock per message (not per batch). Key {@code lock:msg:{id}},
 * value {@code {instanceName}:{claimToken}}, TTL from {@code lab.redis-lock-ttl-ms}
 * (default 10s, deliberately short for the demo). Acquire with
 * {@code SET key value NX PX <ttl>} — atomic acquire-or-fail. Release via a Lua
 * script that compares the value before DEL, so we never delete someone else's
 * lock after our own TTL expired.
 *
 * Key invariants (spec §16):
 *  #1 at-most-once successful processing — the guarded completeIfOwned update
 *     enforces it even if two instances somehow both hold a claim;
 *  #2 never lost — if an instance dies, the Redis key expires on its own and
 *     the shared LeaseSweeper reconciles the DB row back to NEW;
 *  #3 coordination is per-strategy, recovery is shared.
 */
@Component
public class RedisLockCoordinator implements Coordinator {

    private final StringRedisTemplate redis;
    private final MessageRepository repo;
    private final Duration lockTtl;

    private static final DefaultRedisScript<Long> RELEASE_SCRIPT =
        new DefaultRedisScript<>(
            "if redis.call('get', KEYS[1]) == ARGV[1] then " +
            "return redis.call('del', KEYS[1]) else return 0 end",
            Long.class);

    public RedisLockCoordinator(StringRedisTemplate redis,
                                MessageRepository repo,
                                @Value("${lab.redis-lock-ttl-ms:10000}") long lockTtlMs) {
        this.redis = redis;
        this.repo = repo;
        this.lockTtl = Duration.ofMillis(lockTtlMs);
    }

    @Override
    public List<Message> claimBatch(String instanceName, int batchSize) {
        // 1. Read candidates - NO database lock. Redis is the arbiter.
        List<Message> candidates = repo.findTop50ByTypeAndStatusOrderByCreatedAt(
                MessageType.INTRADAY, MessageStatus.NEW);

        List<Message> won = new ArrayList<>();
        for (Message m : candidates) {
            if (won.size() >= batchSize) {
                break;
            }

            UUID token = UUID.randomUUID();
            String key   = "lock:msg:" + m.getId();
            String value = instanceName + ":" + token;

            // SET key value NX PX <ttl>  (atomic acquire-or-fail)
            Boolean acquired = redis.opsForValue().setIfAbsent(key, value, lockTtl);

            if (Boolean.TRUE.equals(acquired)) {
                // 2. Bookkeeping in DB - guarded so we only flip NEW rows
                int updated = repo.markProcessing(m.getId(), instanceName, token, Instant.now());
                if (updated == 1) {
                    m.setClaimToken(token);
                    won.add(m);
                } else {
                    // Someone else beat us in the DB - release our lock
                    redis.execute(RELEASE_SCRIPT, List.of(key), value);
                }
            }
            // acquired == false -> another instance holds the lock; skip silently
        }
        return won;
    }

    @Override
    public boolean complete(Message m, String instanceName, UUID claimToken) {
        // 1. Idempotent guarded transition (increments processed_count).
        // A return of 0 is a harmless late write — never an error.
        int updated = repo.completeIfOwned(
                m.getId(), instanceName, claimToken, Instant.now());

        // 2. Release the lock ONLY if we still own it (Lua compares value)
        String key      = "lock:msg:" + m.getId();
        String expected = instanceName + ":" + claimToken;
        redis.execute(RELEASE_SCRIPT, List.of(key), expected);

        return updated == 1;
    }

    @Override
    public MessageType handles() {
        return MessageType.INTRADAY;
    }
}
