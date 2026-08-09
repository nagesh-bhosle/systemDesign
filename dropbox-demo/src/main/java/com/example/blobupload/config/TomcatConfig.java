package com.example.blobupload.config;

import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.servlet.server.ConfigurableServletWebServerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Tomcat tuning for large file uploads.
 * Ensures the server doesn't reject or truncate multi-GB requests.
 */
@Configuration
public class TomcatConfig {

    @Bean
    public ConfigurableServletWebServerFactory webServerFactory() {
        TomcatServletWebServerFactory factory = new TomcatServletWebServerFactory();
        // No limit on post body size — needed for GB-scale uploads
        factory.addConnectorCustomizers(connector -> {
            connector.setProperty("maxPostSize", "-1");
            connector.setProperty("maxSavePostSize", "-1");
            connector.setProperty("maxHttpFormPostSize", "-1");
            // Increase connection timeout for slow uploads (10 minutes)
            connector.setProperty("connectionTimeout", "600000");
            // Keep-alive timeout
            connector.setProperty("keepAliveTimeout", "600000");
        });
        return factory;
    }
}