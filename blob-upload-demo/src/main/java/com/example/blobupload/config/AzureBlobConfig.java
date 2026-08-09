package com.example.blobupload.config;

import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AzureBlobConfig {

    private static final Logger log = LoggerFactory.getLogger(AzureBlobConfig.class);

    @Value("${azure.blob.connection-string}")
    private String connectionString;

    @Value("${azure.blob.container-name}")
    private String containerName;

    @Bean
    public BlobServiceClient blobServiceClient() {
        log.info("Creating BlobServiceClient with Azurite connection");
        log.info("Container to use: {}", containerName);

        return new BlobServiceClientBuilder()
                .connectionString(connectionString)
                .buildClient();
    }
}