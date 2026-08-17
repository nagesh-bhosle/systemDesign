package com.example.lab.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Topology: two durable queues fed by one direct exchange.
 *
 * Key invariant (spec §16 #5): the broker feeds the DB. These queues only
 * guarantee ingestion durability — the listener immediately persists each
 * message as a NEW row and the messages table becomes the work queue.
 */
@Configuration
public class RabbitConfig {

    public static final String EXCHANGE = "lab.exchange";
    public static final String INTRADAY_QUEUE = "q.intraday";
    public static final String EOD_QUEUE = "q.eod";
    public static final String INTRADAY_ROUTING_KEY = "intraday";
    public static final String EOD_ROUTING_KEY = "eod";

    @Bean
    public Queue intradayQueue() {
        return QueueBuilder.durable(INTRADAY_QUEUE).build();
    }

    @Bean
    public Queue eodQueue() {
        return QueueBuilder.durable(EOD_QUEUE).build();
    }

    @Bean
    public DirectExchange labExchange() {
        return new DirectExchange(EXCHANGE, true, false);
    }

    @Bean
    public Binding intradayBinding(Queue intradayQueue, DirectExchange labExchange) {
        return BindingBuilder.bind(intradayQueue).to(labExchange).with(INTRADAY_ROUTING_KEY);
    }

    @Bean
    public Binding eodBinding(Queue eodQueue, DirectExchange labExchange) {
        return BindingBuilder.bind(eodQueue).to(labExchange).with(EOD_ROUTING_KEY);
    }
}
