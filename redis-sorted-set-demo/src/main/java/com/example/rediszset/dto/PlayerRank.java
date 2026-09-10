package com.example.rediszset.dto;

/** Reply for GET /api/players/{name}/rank — combines ZREVRANK + ZSCORE. */
public record PlayerRank(String member, Long rank, Double score) {
}
