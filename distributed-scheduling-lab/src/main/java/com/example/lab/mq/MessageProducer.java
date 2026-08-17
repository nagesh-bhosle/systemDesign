package com.example.lab.mq;

import com.example.lab.config.RabbitConfig;
import com.example.lab.domain.MessageType;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Component;

import java.util.concurrent.ThreadLocalRandom;

/**
 * Publishes ingestion messages of the form {"type":"...","payload":"order-<random>"}
 * to the queue for the given type. Payloads are plain JSON strings; the listener
 * parses them back out.
 */
@Component
public class MessageProducer {

    private final RabbitTemplate rabbit;

    public MessageProducer(RabbitTemplate rabbit) {
        this.rabbit = rabbit;
    }

    public int produce(MessageType type, int count) {
        String routingKey = type == MessageType.INTRADAY
                ? RabbitConfig.INTRADAY_ROUTING_KEY
                : RabbitConfig.EOD_ROUTING_KEY;
        for (int i = 0; i < count; i++) {
            String json = "{\"type\":\"" + type.name()
                    + "\",\"payload\":\"order-" + ThreadLocalRandom.current().nextInt(100_000, 999_999) + "\"}";
            rabbit.convertAndSend(RabbitConfig.EXCHANGE, routingKey, json);
        }
        return count;
    }
}
