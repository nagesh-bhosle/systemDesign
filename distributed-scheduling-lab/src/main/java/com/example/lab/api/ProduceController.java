package com.example.lab.api;

import com.example.lab.domain.MessageType;
import com.example.lab.mq.MessageProducer;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * POST /api/produce?type=INTRADAY&count=50 -> publishes count messages to the
 * queue for that type, returns {"published": n}.
 */
@RestController
@RequestMapping("/api")
public class ProduceController {

    private final MessageProducer producer;

    public ProduceController(MessageProducer producer) {
        this.producer = producer;
    }

    @PostMapping("/produce")
    public ResponseEntity<Map<String, Object>> produce(
            @RequestParam(defaultValue = "INTRADAY") String type,
            @RequestParam(defaultValue = "1") int count) {
        MessageType messageType;
        try {
            messageType = MessageType.valueOf(type.toUpperCase());
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "unknown type '" + type + "' (use INTRADAY or EOD)"));
        }
        if (count < 1 || count > 10_000) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "count must be between 1 and 10000"));
        }
        int published = producer.produce(messageType, count);
        return ResponseEntity.ok(Map.of("published", published));
    }
}
