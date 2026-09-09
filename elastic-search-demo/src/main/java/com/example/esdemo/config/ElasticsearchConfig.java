package com.example.esdemo.config;

import co.elastic.clients.elasticsearch.ElasticsearchClient;
import co.elastic.clients.json.jackson.JacksonJsonpMapper;
import co.elastic.clients.transport.rest_client.RestClientTransport;
import org.apache.http.HttpHost;
import org.elasticsearch.client.RestClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ElasticsearchConfig {

    @Value("${elasticsearch.host:localhost}")
    private String host;

    @Value("${elasticsearch.port:9201}")
    private int port;

    @Value("${elasticsearch.scheme:http}")
    private String scheme;

    @Bean
    public ElasticsearchClient elasticsearchClient() {
        RestClient restClient = RestClient.builder(new HttpHost(host, port, scheme))
                .setRequestConfigCallback(builder -> builder
                        .setConnectTimeout(5000)
                        .setSocketTimeout(60000))
                .build();
        return new ElasticsearchClient(new RestClientTransport(restClient, new JacksonJsonpMapper()));
    }
}
