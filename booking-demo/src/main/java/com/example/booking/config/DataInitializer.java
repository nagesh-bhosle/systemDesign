package com.example.booking.config;

import com.example.booking.service.DemoResetService;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class DataInitializer {

    @Bean
    ApplicationRunner seedBookingDemo(DemoResetService reset) {
        return args -> reset.seedIfEmpty();
    }
}
