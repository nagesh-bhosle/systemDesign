package com.example.rediszset.dto;

/**
 * Everything a demo click needs to teach one Redis command:
 * the exact command text, the raw reply, timing, and which backend ran it.
 */
public record OpResult(
        String command,
        Object reply,
        double latencyMs,
        String backend,
        Long keySize,
        boolean ok,
        String error
) {
}
