package com.example.rediszset.controller;

import com.example.rediszset.dto.OpResult;
import com.example.rediszset.dto.PlayerEntry;
import com.example.rediszset.dto.PlayerRank;
import com.example.rediszset.service.RedisSortedSetService;
import com.example.rediszset.service.SortedSetService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api")
@CrossOrigin
public class LeaderboardController {

    private final Map<String, SortedSetService> services;
    private final String defaultBackend;
    private final String key;

    public LeaderboardController(List<SortedSetService> impls,
                                 @Value("${sortedset.backend}") String defaultBackend,
                                 @Value("${sortedset.key}") String key) {
        this.services = impls.stream()
                .collect(Collectors.toMap(SortedSetService::backend, Function.identity()));
        this.defaultBackend = defaultBackend;
        this.key = key;
    }

    public record SeedRequest(String name, double score) {
    }

    @GetMapping("/leaderboard")
    public OpResult leaderboard(@RequestParam(defaultValue = "10") int top,
                                @RequestParam(required = false) String backend) {
        SortedSetService s = svc(backend);
        int limit = Math.max(1, Math.min(top, 100));
        long start = System.nanoTime();
        try {
            List<PlayerEntry> rows = s.leaderboard(limit);
            return new OpResult("ZREVRANGE %s 0 %d WITHSCORES".formatted(key, limit - 1),
                    rows, RedisSortedSetService.elapsedMs(start), s.backend(), sizeOf(s), true, null);
        } catch (Exception e) {
            return error(s, "ZREVRANGE %s 0 %d WITHSCORES".formatted(key, limit - 1), start, e);
        }
    }

    @PostMapping("/players")
    public OpResult addPlayer(@RequestBody SeedRequest body,
                              @RequestParam(required = false) String backend) {
        return svc(backend).zadd(body.name(), body.score());
    }

    @PostMapping("/players/{name}/score")
    public OpResult incrementScore(@PathVariable String name,
                                   @RequestParam(defaultValue = "10") double delta,
                                   @RequestParam(required = false) String backend) {
        return svc(backend).zincrby(name, delta);
    }

    @DeleteMapping("/players/{name}")
    public OpResult removePlayer(@PathVariable String name,
                                 @RequestParam(required = false) String backend) {
        return svc(backend).zrem(name);
    }

    @GetMapping("/players/{name}/rank")
    public OpResult rankOf(@PathVariable String name,
                           @RequestParam(required = false) String backend) {
        SortedSetService s = svc(backend);
        long start = System.nanoTime();
        OpResult rank = s.zrevrank(name);
        OpResult score = s.zscore(name);
        PlayerRank reply = new PlayerRank(name,
                rank.reply() instanceof Long r ? r : null,
                score.reply() instanceof Double d ? d : null);
        boolean ok = rank.ok() && score.ok();
        String error = !ok ? (rank.error() != null ? rank.error() : score.error()) : null;
        return new OpResult(rank.command() + "  +  " + score.command(), reply,
                rank.latencyMs() + score.latencyMs(), s.backend(),
                ok ? sizeOf(s) : null, ok, error);
    }

    @GetMapping("/score-range")
    public OpResult scoreRange(@RequestParam(defaultValue = "100") double min,
                               @RequestParam(defaultValue = "500") double max,
                               @RequestParam(required = false) String backend) {
        return svc(backend).zrangebyscore(min, max);
    }

    @GetMapping("/count")
    public OpResult count(@RequestParam(defaultValue = "0") double min,
                          @RequestParam(defaultValue = "1000") double max,
                          @RequestParam(required = false) String backend) {
        return svc(backend).zcount(min, max);
    }

    @PostMapping("/seed")
    public OpResult seed(@RequestParam(required = false) String backend) {
        return svc(backend).seed();
    }

    @PostMapping("/reset")
    public OpResult reset(@RequestParam(required = false) String backend) {
        return svc(backend).reset();
    }

    @GetMapping("/backend")
    public Map<String, Object> backendInfo(@RequestParam(required = false) String backend) {
        SortedSetService s = svc(backend);
        Long size = null;
        try {
            size = sizeOf(s);
        } catch (Exception ignored) {
            // Redis unreachable — still report which backend is active
        }
        Map<String, Object> info = new java.util.LinkedHashMap<>();
        info.put("backend", s.backend());
        info.put("default", defaultBackend);
        info.put("keySize", size);
        return info;
    }

    private SortedSetService svc(String backend) {
        String b = backend == null || backend.isBlank() ? defaultBackend : backend;
        SortedSetService s = services.get(b);
        if (s == null) {
            throw new IllegalArgumentException("Unknown backend: " + b);
        }
        return s;
    }

    private Long sizeOf(SortedSetService s) {
        return s.zcard().keySize();
    }

    private OpResult error(SortedSetService s, String command, long startNanos, Exception e) {
        return new OpResult(command, null, RedisSortedSetService.elapsedMs(startNanos),
                s.backend(), null, false, RedisSortedSetService.rootMessage(e));
    }
}
