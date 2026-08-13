package com.example.gopuff.web;

import com.example.gopuff.service.order.ConcurrentOrderException;
import com.example.gopuff.service.order.InsufficientInventoryException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(InsufficientInventoryException.class)
    public ResponseEntity<Map<String, String>> insufficient(InsufficientInventoryException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", ex.getMessage()));
    }

    @ExceptionHandler(ConcurrentOrderException.class)
    public ResponseEntity<Map<String, String>> concurrent(ConcurrentOrderException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", ex.getMessage()));
    }
}
