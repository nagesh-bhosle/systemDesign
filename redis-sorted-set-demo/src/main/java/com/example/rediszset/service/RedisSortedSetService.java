package com.example.rediszset.service;

import com.example.rediszset.dto.OpResult;
import com.example.rediszset.dto.PlayerEntry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ZSetOperations;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.function.Supplier;

/**
 * Real Redis ZSET implementation. Fails soft: if Redis is unreachable the op
 * returns ok=false with the error text so the UI keeps working (and the user
 * can flip to the in-memory backend to compare).
 */
@Service("redis")
public class RedisSortedSetService implements SortedSetService {

    private static final String[] SEED_PLAYERS = {
            "Nova:850", "Kira:920", "Jinx:640", "Pixel:730", "Miko:660",
            "Zara:590", "Orbi:410", "Rex:380", "Bolt:220", "Ash:150"
    };

    private final StringRedisTemplate redis;
    private final String key;

    public RedisSortedSetService(StringRedisTemplate redis,
                                 @Value("${sortedset.key}") String key) {
        this.redis = redis;
        this.key = key;
    }

    @Override
    public String backend() {
        return "redis";
    }

    @Override
    public OpResult zadd(String member, double score) {
        String cmd = "ZADD %s %.1f \"%s\"".formatted(key, score, member);
        return run(cmd, () -> redis.opsForZSet().add(key, member, score) ? 1L : 0L);
    }

    @Override
    public OpResult zincrby(String member, double delta) {
        String cmd = "ZINCRBY %s %.1f \"%s\"".formatted(key, delta, member);
        return run(cmd, () -> redis.opsForZSet().incrementScore(key, member, delta));
    }

    @Override
    public OpResult zrem(String member) {
        String cmd = "ZREM %s \"%s\"".formatted(key, member);
        return run(cmd, () -> redis.opsForZSet().remove(key, member));
    }

    @Override
    public OpResult zscore(String member) {
        String cmd = "ZSCORE %s \"%s\"".formatted(key, member);
        return run(cmd, () -> redis.opsForZSet().score(key, member));
    }

    @Override
    public OpResult zrevrank(String member) {
        String cmd = "ZREVRANK %s \"%s\"".formatted(key, member);
        return run(cmd, () -> redis.opsForZSet().reverseRank(key, member));
    }

    @Override
    public OpResult zrevrange(int top) {
        String cmd = "ZREVRANGE %s 0 %d WITHSCORES".formatted(key, top - 1);
        return run(cmd, () -> rows(redis.opsForZSet().reverseRangeWithScores(key, 0, top - 1)));
    }

    @Override
    public OpResult zrangebyscore(double min, double max) {
        String cmd = "ZRANGEBYSCORE %s %.1f %.1f WITHSCORES".formatted(key, min, max);
        return run(cmd, () -> rows(redis.opsForZSet().rangeByScoreWithScores(key, min, max)));
    }

    @Override
    public OpResult zcount(double min, double max) {
        String cmd = "ZCOUNT %s %.1f %.1f".formatted(key, min, max);
        return run(cmd, () -> redis.opsForZSet().count(key, min, max));
    }

    @Override
    public OpResult zcard() {
        String cmd = "ZCARD " + key;
        return run(cmd, () -> redis.opsForZSet().zCard(key));
    }

    @Override
    public OpResult seed() {
        StringBuilder cmd = new StringBuilder("ZADD " + key);
        for (String p : SEED_PLAYERS) {
            int i = p.indexOf(':');
            cmd.append(" %s \"%s\"".formatted(p.substring(i + 1), p.substring(0, i)));
        }
        return run(cmd.toString(), () -> {
            redis.opsForZSet().remove(key, members());
            java.util.Set<ZSetOperations.TypedTuple<String>> tuples = new java.util.HashSet<>();
            for (String p : SEED_PLAYERS) {
                int i = p.indexOf(':');
                tuples.add(ZSetOperations.TypedTuple.of(p.substring(0, i), Double.parseDouble(p.substring(i + 1))));
            }
            redis.opsForZSet().add(key, tuples);
            return (long) SEED_PLAYERS.length;
        });
    }

    @Override
    public OpResult reset() {
        String cmd = "DEL " + key;
        return run(cmd, () -> redis.delete(key) ? 1L : 0L);
    }

    @Override
    public List<PlayerEntry> leaderboard(int top) {
        Set<ZSetOperations.TypedTuple<String>> tuples =
                redis.opsForZSet().reverseRangeWithScores(key, 0, top - 1);
        List<PlayerEntry> rows = new ArrayList<>();
        if (tuples == null) {
            return rows;
        }
        long rank = 0;
        for (ZSetOperations.TypedTuple<String> t : tuples) {
            Double score = t.getScore();
            rows.add(new PlayerEntry(t.getValue(), score == null ? 0 : score, rank++));
        }
        return rows;
    }

    private Object rows(Set<ZSetOperations.TypedTuple<String>> tuples) {
        List<PlayerEntry> rows = new ArrayList<>();
        if (tuples != null) {
            for (ZSetOperations.TypedTuple<String> t : tuples) {
                Double score = t.getScore();
                rows.add(new PlayerEntry(t.getValue(), score == null ? 0 : score, null));
            }
        }
        return rows;
    }

    private String[] members() {
        String[] m = new String[SEED_PLAYERS.length];
        for (int i = 0; i < SEED_PLAYERS.length; i++) {
            m[i] = SEED_PLAYERS[i].substring(0, SEED_PLAYERS[i].indexOf(':'));
        }
        return m;
    }

    private OpResult run(String command, Supplier<Object> action) {
        long start = System.nanoTime();
        try {
            Object reply = action.get();
            return new OpResult(command, reply, elapsedMs(start), backend(), keySize(), true, null);
        } catch (Exception e) {
            return new OpResult(command, null, elapsedMs(start), backend(), null, false, rootMessage(e));
        }
    }

    private Long keySize() {
        try {
            Long size = redis.opsForZSet().zCard(key);
            return size == null ? 0L : size;
        } catch (Exception e) {
            return null;
        }
    }

    public static double elapsedMs(long startNanos) {
        return Math.round((System.nanoTime() - startNanos) / 1e4) / 100.0;
    }

    public static String rootMessage(Throwable e) {
        Throwable t = e;
        while (t.getCause() != null && t.getCause() != t) {
            t = t.getCause();
        }
        String msg = t.getMessage();
        return msg == null || msg.isBlank() ? t.getClass().getSimpleName() : msg.split("\n")[0];
    }
}
