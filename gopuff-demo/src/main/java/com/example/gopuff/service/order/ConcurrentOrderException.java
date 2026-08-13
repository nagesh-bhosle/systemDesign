package com.example.gopuff.service.order;

public class ConcurrentOrderException extends RuntimeException {
    public ConcurrentOrderException(String message, Throwable cause) {
        super(message, cause);
    }

    public ConcurrentOrderException(String message) {
        super(message);
    }
}
