package com.example.lab.config;

import org.springframework.context.annotation.Configuration;

/**
 * Redis configuration.
 *
 * Spring Boot auto-configuration already provides the StringRedisTemplate
 * used by RedisLockCoordinator (host/port come from spring.data.redis.* in
 * application.yml). This class exists to make the Redis presence explicit in
 * the project structure; no custom beans are required.
 */
@Configuration
public class RedisConfig {
}
