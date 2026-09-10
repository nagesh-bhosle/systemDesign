package com.example.rediszset.service;

import com.example.rediszset.dto.OpResult;
import com.example.rediszset.dto.PlayerEntry;

import java.util.List;

/**
 * Mirrors the Redis Sorted Set (ZSET) API. Every method returns an {@link OpResult}
 * carrying the exact Redis command it models, so the UI command console always
 * shows what really ran — regardless of which backend executed it.
 */
public interface SortedSetService {

    /** Backend id: "redis" or "memory". */
    String backend();

    OpResult zadd(String member, double score);

    OpResult zincrby(String member, double delta);

    OpResult zrem(String member);

    OpResult zscore(String member);

    OpResult zrevrank(String member);

    OpResult zrevrange(int top);

    OpResult zrangebyscore(double min, double max);

    OpResult zcount(double min, double max);

    OpResult zcard();

    OpResult seed();

    OpResult reset();

    /** ZREVRANGE WITHSCORES enriched with per-member ZREVRANK — powers the ranked table. */
    List<PlayerEntry> leaderboard(int top);
}
