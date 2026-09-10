package com.example.rediszset.service;

import com.example.rediszset.dto.OpResult;
import com.example.rediszset.dto.PlayerEntry;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

/**
 * Pure-Java mirror of the ZSET semantics (ConcurrentHashMap + on-demand sort).
 * Lets the UI demo the exact same commands with no Redis — handy when Docker
 * is down and for comparing O(log N) skiplist behavior with a sort-per-read map.
 */
@Service("memory")
public class InMemorySortedSetService implements SortedSetService {

    private static final String[] SEED_PLAYERS = {
            "Nova:850", "Kira:920", "Jinx:640", "Pixel:730", "Miko:660",
            "Zara:590", "Orbi:410", "Rex:380", "Bolt:220", "Ash:150"
    };

    private static final Comparator<Map.Entry<String, Double>> SCORE_DESC_THEN_MEMBER =
            Comparator.comparingDouble((Map.Entry<String, Double> e) -> -e.getValue())
                    .thenComparing(Map.Entry::getKey);

    private final Map<String, Double> scores = new ConcurrentHashMap<>();

    @Override
    public String backend() {
        return "memory";
    }

    @Override
    public OpResult zadd(String member, double score) {
        String cmd = "ZADD leaderboard:global %.1f \"%s\"".formatted(score, member);
        return run(cmd, () -> scores.put(member, score) == null ? 1L : 0L);
    }

    @Override
    public OpResult zincrby(String member, double delta) {
        String cmd = "ZINCRBY leaderboard:global %.1f \"%s\"".formatted(delta, member);
        return run(cmd, () -> scores.merge(member, delta, Double::sum));
    }

    @Override
    public OpResult zrem(String member) {
        String cmd = "ZREM leaderboard:global \"%s\"".formatted(member);
        return run(cmd, () -> scores.remove(member) == null ? 0L : 1L);
    }

    @Override
    public OpResult zscore(String member) {
        String cmd = "ZSCORE leaderboard:global \"%s\"".formatted(member);
        return run(cmd, () -> scores.get(member));
    }

    @Override
    public OpResult zrevrank(String member) {
        String cmd = "ZREVRANK leaderboard:global \"%s\"".formatted(member);
        return run(cmd, () -> rankOf(member));
    }

    @Override
    public OpResult zrevrange(int top) {
        String cmd = "ZREVRANGE leaderboard:global 0 %d WITHSCORES".formatted(top - 1);
        return run(cmd, () -> sortedDesc().stream().limit(top).map(InMemorySortedSetService::row).toList());
    }

    @Override
    public OpResult zrangebyscore(double min, double max) {
        String cmd = "ZRANGEBYSCORE leaderboard:global %.1f %.1f WITHSCORES".formatted(min, max);
        return run(cmd, () -> sortedAsc().stream()
                .filter(e -> e.getValue() >= min && e.getValue() <= max)
                .map(InMemorySortedSetService::row)
                .toList());
    }

    @Override
    public OpResult zcount(double min, double max) {
        String cmd = "ZCOUNT leaderboard:global %.1f %.1f".formatted(min, max);
        return run(cmd, () -> scores.values().stream().filter(s -> s >= min && s <= max).count());
    }

    @Override
    public OpResult zcard() {
        String cmd = "ZCARD leaderboard:global";
        return run(cmd, () -> (long) scores.size());
    }

    @Override
    public OpResult seed() {
        StringBuilder cmd = new StringBuilder("ZADD leaderboard:global");
        for (String p : SEED_PLAYERS) {
            int i = p.indexOf(':');
            cmd.append(" %s \"%s\"".formatted(p.substring(i + 1), p.substring(0, i)));
        }
        return run(cmd.toString(), () -> {
            scores.clear();
            for (String p : SEED_PLAYERS) {
                int i = p.indexOf(':');
                scores.put(p.substring(0, i), Double.parseDouble(p.substring(i + 1)));
            }
            return (long) SEED_PLAYERS.length;
        });
    }

    @Override
    public OpResult reset() {
        String cmd = "DEL leaderboard:global";
        return run(cmd, () -> {
            boolean wasEmpty = scores.isEmpty();
            scores.clear();
            return wasEmpty ? 0L : 1L;
        });
    }

    @Override
    public List<PlayerEntry> leaderboard(int top) {
        List<PlayerEntry> rows = new ArrayList<>();
        long rank = 0;
        for (Map.Entry<String, Double> e : sortedDesc()) {
            if (rank >= top) {
                break;
            }
            rows.add(new PlayerEntry(e.getKey(), e.getValue(), rank++));
        }
        return rows;
    }

    private Long rankOf(String member) {
        Double score = scores.get(member);
        if (score == null) {
            return null;
        }
        long rank = 0;
        for (Map.Entry<String, Double> e : scores.entrySet()) {
            if (e.getValue() > score || (e.getValue() == score && e.getKey().compareTo(member) < 0)) {
                rank++;
            }
        }
        return rank;
    }

    private List<Map.Entry<String, Double>> sortedDesc() {
        return scores.entrySet().stream().sorted(SCORE_DESC_THEN_MEMBER).toList();
    }

    private List<Map.Entry<String, Double>> sortedAsc() {
        return scores.entrySet().stream()
                .sorted(Comparator.<Map.Entry<String, Double>>comparingDouble(Map.Entry::getValue)
                        .thenComparing(Map.Entry::getKey))
                .toList();
    }

    private static PlayerEntry row(Map.Entry<String, Double> e) {
        return new PlayerEntry(e.getKey(), e.getValue(), null);
    }

    private OpResult run(String command, Supplier<Object> action) {
        return new OpResult(command, action.get(), RedisSortedSetService.elapsedMs(System.nanoTime()),
                backend(), (long) scores.size(), true, null);
    }
}
