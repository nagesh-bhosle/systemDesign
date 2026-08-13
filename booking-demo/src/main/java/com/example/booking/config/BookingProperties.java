package com.example.booking.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

@Data
@ConfigurationProperties(prefix = "booking")
public class BookingProperties {
    private int defaultDelayMs = 200;
    private int holdSeconds = 15;
    private int redisLockWaitMs = 3000;
    private int redisLockTtlMs = 10000;
}
