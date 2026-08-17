package com.example.lab.api;

import com.example.lab.coordination.CoordinatorRouter;
import com.example.lab.domain.MessageStatus;
import com.example.lab.domain.MessageType;
import com.example.lab.events.EventBus;
import com.example.lab.repo.MessageRepository;
import com.example.lab.scheduling.SchedulerInstance;
import com.example.lab.scheduling.SchedulerRegistry;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Dashboard endpoints:
 *   GET  /api/stream -> text/event-stream of ProcessingEvent JSON
 *   GET  /api/stats  -> nested per-state/per-type counts + duplicates + instances
 *   POST /api/reset  -> truncate the messages table and return fresh state
 */
@RestController
@RequestMapping("/api")
public class DashboardController {

    private final EventBus eventBus;
    private final MessageRepository repo;
    private final SchedulerRegistry schedulers;
    private final CoordinatorRouter router;

    public DashboardController(EventBus eventBus, MessageRepository repo,
                               SchedulerRegistry schedulers, CoordinatorRouter router) {
        this.eventBus = eventBus;
        this.repo = repo;
        this.schedulers = schedulers;
        this.router = router;
    }

    @GetMapping(path = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter stream() {
        SseEmitter emitter = eventBus.register();
        try {
            // initial comment frame so proxies/browsers see the stream is live
            emitter.send(SseEmitter.event().comment("stream open"));
        } catch (Exception ignored) {
            // client vanished immediately; EventBus will clean up
        }
        return emitter;
    }

    @GetMapping("/stats")
    public Map<String, Object> stats() {
        Map<String, Object> result = new LinkedHashMap<>();
        for (MessageStatus status : MessageStatus.values()) {
            Map<String, Object> perType = new LinkedHashMap<>();
            for (MessageType type : MessageType.values()) {
                perType.put(type.name(), repo.countByStatusAndType(status, type));
            }
            result.put(status.name(), perType);
        }
        // duplicates = rows completed more than once (processed_count > 1).
        // Must stay 0 in coordinated mode; grows in naive mode.
        result.put("duplicates", repo.countByProcessedCountGreaterThan(1));

        List<Map<String, Object>> instances = new ArrayList<>();
        for (SchedulerInstance instance : schedulers.all()) {
            Map<String, Object> card = new LinkedHashMap<>();
            card.put("name", instance.getName());
            card.put("alive", instance.isAlive());
            card.put("currentWork", instance.getCurrentWork());
            instances.add(card);
        }
        result.put("instances", instances);
        result.put("mode", router.mode());   // informational: naive | coordinated
        return result;
    }

    @PostMapping("/reset")
    public Map<String, Object> reset() {
        repo.truncateMessages();
        // fresh state right after truncation — everything zeroed
        return Map.of(
                "NEW", Map.of("INTRADAY", 0, "EOD", 0),
                "PROCESSING", Map.of("INTRADAY", 0, "EOD", 0),
                "DONE", Map.of("INTRADAY", 0, "EOD", 0),
                "duplicates", 0);
    }
}
