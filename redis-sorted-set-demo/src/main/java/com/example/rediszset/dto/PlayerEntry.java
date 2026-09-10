package com.example.rediszset.dto;

/** One row of the leaderboard: member, score, and 0-based ZREVRANK (UI renders 1-based). */
public record PlayerEntry(String member, double score, Long rank) {
}
