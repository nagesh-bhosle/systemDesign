package com.example.gopuff;

import com.example.gopuff.config.GopuffProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
@EnableConfigurationProperties(GopuffProperties.class)
public class GopuffApplication {

    public static void main(String[] args) {
        SpringApplication.run(GopuffApplication.class, args);
    }
}
