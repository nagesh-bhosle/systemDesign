package com.example.booking.controller;

import com.example.booking.config.BookingProperties;
import com.example.booking.dto.ConceptResult;
import com.example.booking.service.ConceptDemoService;
import com.example.booking.service.DemoResetService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/concepts")
public class ConceptController {

    private final ConceptDemoService demos;
    private final DemoResetService reset;
    private final BookingProperties properties;

    public ConceptController(ConceptDemoService demos, DemoResetService reset, BookingProperties properties) {
        this.demos = demos;
        this.reset = reset;
        this.properties = properties;
    }

    @GetMapping
    public Map<String, Object> catalog() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("howToUse", "POST each path. The server starts two (or more) users at the same instant and returns a timeline.");
        body.put("debugUi", "http://localhost:8083");
        body.put("defaultDelayMs", properties.getDefaultDelayMs());
        body.put("concepts", List.of(
                Map.of("method", "POST", "path", "/api/concepts/race-condition",
                        "shows", "Two users both succeed — double booking"),
                Map.of("method", "POST", "path", "/api/concepts/pessimistic-lock",
                        "shows", "FOR UPDATE: one waits, then sees booked=true"),
                Map.of("method", "POST", "path", "/api/concepts/optimistic-lock",
                        "shows", "@Version: loser gets OptimisticLockingFailureException"),
                Map.of("method", "POST", "path", "/api/concepts/unsafe-inventory",
                        "shows", "Last ticket oversold with Java increment"),
                Map.of("method", "POST", "path", "/api/concepts/atomic-update",
                        "shows", "Guarded UPDATE prevents oversell"),
                Map.of("method", "POST", "path", "/api/concepts/pessimistic-inventory",
                        "shows", "Lock then Java rules on a count of 5"),
                Map.of("method", "POST", "path", "/api/concepts/unsafe-counter",
                        "shows", "Lost updates on read-modify-write"),
                Map.of("method", "POST", "path", "/api/concepts/atomic-counter",
                        "shows", "UPDATE value = value + 1 keeps the total"),
                Map.of("method", "POST", "path", "/api/concepts/distributed-lock",
                        "shows", "Redis SET NX around the unsafe book"),
                Map.of("method", "POST", "path", "/api/concepts/hold-and-confirm",
                        "shows", "Two users race to HOLD; then confirm"),
                Map.of("method", "POST", "path", "/api/concepts/unique-constraint",
                        "shows", "UNIQUE(event, seat) catches racy inserts")
        ));
        body.put("state", demos.snapshot());
        return body;
    }

    @GetMapping("/state")
    public Map<String, Object> state() {
        return demos.snapshot();
    }

    @PostMapping("/reset")
    public Map<String, Object> resetAll() {
        reset.resetAll();
        return demos.snapshot();
    }

    @PostMapping("/race-condition")
    public ConceptResult race(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(required = false) Integer delayMs) {
        return demos.raceCondition(users, delay(delayMs));
    }

    @PostMapping("/pessimistic-lock")
    public ConceptResult pessimistic(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(required = false) Integer delayMs) {
        return demos.pessimisticLock(users, delay(delayMs));
    }

    @PostMapping("/optimistic-lock")
    public ConceptResult optimistic(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(required = false) Integer delayMs) {
        return demos.optimisticLock(users, delay(delayMs));
    }

    @PostMapping("/unsafe-inventory")
    public ConceptResult unsafeInventory(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(defaultValue = "1") int quantity,
            @RequestParam(required = false) Integer delayMs) {
        return demos.unsafeInventory(users, quantity, delay(delayMs));
    }

    @PostMapping("/atomic-update")
    public ConceptResult atomicUpdate(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(defaultValue = "1") int quantity) {
        return demos.atomicUpdate(users, quantity);
    }

    @PostMapping("/pessimistic-inventory")
    public ConceptResult pessimisticInventory(
            @RequestParam(defaultValue = "3") int users,
            @RequestParam(defaultValue = "2") int quantity,
            @RequestParam(required = false) Integer delayMs) {
        return demos.pessimisticInventory(users, quantity, delay(delayMs));
    }

    @PostMapping("/unsafe-counter")
    public ConceptResult unsafeCounter(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(defaultValue = "20") int incrementsEach,
            @RequestParam(defaultValue = "5") int delayMs) {
        return demos.unsafeCounter(users, incrementsEach, delayMs);
    }

    @PostMapping("/atomic-counter")
    public ConceptResult atomicCounter(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(defaultValue = "20") int incrementsEach) {
        return demos.atomicCounter(users, incrementsEach);
    }

    @PostMapping("/distributed-lock")
    public ConceptResult distributed(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(required = false) Integer delayMs) {
        return demos.distributedLock(users, delay(delayMs));
    }

    @PostMapping("/hold-and-confirm")
    public ConceptResult hold(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(required = false) Integer delayMs,
            @RequestParam(required = false) Integer holdSeconds) {
        int hold = holdSeconds != null ? holdSeconds : properties.getHoldSeconds();
        return demos.holdAndConfirm(users, delay(delayMs), hold);
    }

    @PostMapping("/hold-and-confirm/confirm")
    public ConceptResult confirm(@RequestParam long userId) {
        return demos.confirmHold(userId);
    }

    @PostMapping("/unique-constraint")
    public ConceptResult unique(
            @RequestParam(defaultValue = "2") int users,
            @RequestParam(required = false) Integer delayMs) {
        return demos.uniqueConstraint(users, delay(delayMs));
    }

    private int delay(Integer delayMs) {
        return delayMs != null ? delayMs : properties.getDefaultDelayMs();
    }
}
