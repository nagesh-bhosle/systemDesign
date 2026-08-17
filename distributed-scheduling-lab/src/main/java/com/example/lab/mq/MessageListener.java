package com.example.lab.mq;

import com.example.lab.domain.Message;
import com.example.lab.domain.MessageType;
import com.example.lab.events.EventBus;
import com.example.lab.events.ProcessingEvent;
import com.example.lab.repo.MessageRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Consumes from both queues and persists each message as a status=NEW row.
 *
 * Key invariant (spec §16 #5): the broker feeds the DB; the DB is the work
 * queue. The queue guarantees durability of ingestion; the row guarantees
 * visibility to the schedulers.
 */
@Component
public class MessageListener {

    private static final Logger log = LoggerFactory.getLogger(MessageListener.class);

    private final MessageRepository repo;
    private final EventBus events;
    private final ObjectMapper mapper = new ObjectMapper();

    public MessageListener(MessageRepository repo, EventBus events) {
        this.repo = repo;
        this.events = events;
    }

    @RabbitListener(queues = "q.intraday")
    public void onIntraday(String json) {
        persist(json, MessageType.INTRADAY);
    }

    @RabbitListener(queues = "q.eod")
    public void onEod(String json) {
        persist(json, MessageType.EOD);
    }

    private void persist(String json, MessageType type) {
        String payload = extractPayload(json, type);
        Message saved = repo.save(new Message(type, payload));
        log.debug("persisted message id={} type={} as NEW", saved.getId(), type);
        events.publish(ProcessingEvent.received(saved));
    }

    private String extractPayload(String json, MessageType fallbackType) {
        try {
            JsonNode node = mapper.readTree(json);
            JsonNode payload = node.get("payload");
            return payload != null ? payload.asText() : json;
        } catch (IOException ex) {
            log.warn("could not parse payload JSON, storing raw message: {}", json, ex);
            return json;
        }
    }
}
