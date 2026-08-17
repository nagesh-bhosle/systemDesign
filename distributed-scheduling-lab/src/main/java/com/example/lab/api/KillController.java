package com.example.lab.api;

import com.example.lab.events.EventBus;
import com.example.lab.events.ProcessingEvent;
import com.example.lab.scheduling.SchedulerInstance;
import com.example.lab.scheduling.SchedulerRegistry;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * POST /api/kill/{name}   -> simulate a crash / scale-down (abandons in-flight work)
 * POST /api/revive/{name} -> simulate a scale-up
 * Unknown names return 404.
 */
@RestController
@RequestMapping("/api")
public class KillController {

    private final SchedulerRegistry schedulers;
    private final EventBus events;

    public KillController(SchedulerRegistry schedulers, EventBus events) {
        this.schedulers = schedulers;
        this.events = events;
    }

    @PostMapping("/kill/{name}")
    public ResponseEntity<Map<String, Object>> kill(@PathVariable String name) {
        SchedulerInstance instance = schedulers.find(name).orElse(null);
        if (instance == null) {
            return ResponseEntity.notFound().build();
        }
        instance.kill();
        events.publish(ProcessingEvent.instanceKilled(name));
        return ResponseEntity.ok(Map.of("killed", name));
    }

    @PostMapping("/revive/{name}")
    public ResponseEntity<Map<String, Object>> revive(@PathVariable String name) {
        SchedulerInstance instance = schedulers.find(name).orElse(null);
        if (instance == null) {
            return ResponseEntity.notFound().build();
        }
        instance.revive();
        events.publish(ProcessingEvent.instanceRevived(name));
        return ResponseEntity.ok(Map.of("revived", name));
    }
}
