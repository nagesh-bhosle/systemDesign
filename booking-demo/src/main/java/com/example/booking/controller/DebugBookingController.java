package com.example.booking.controller;

import com.example.booking.config.BookingProperties;
import com.example.booking.dto.BookOutcome;
import com.example.booking.service.DemoClock;
import com.example.booking.service.DistributedLockBookingService;
import com.example.booking.service.HoldAndConfirmService;
import com.example.booking.service.InventoryService;
import com.example.booking.service.OptimisticBookingService;
import com.example.booking.service.PessimisticBookingService;
import com.example.booking.service.UniqueConstraintBookingService;
import com.example.booking.service.UnsafeBookingService;
import com.example.booking.service.CounterService;
import com.example.booking.service.DemoResetService;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/debug")
public class DebugBookingController {

    private final UnsafeBookingService unsafeBooking;
    private final PessimisticBookingService pessimisticBooking;
    private final OptimisticBookingService optimisticBooking;
    private final InventoryService inventoryService;
    private final CounterService counterService;
    private final HoldAndConfirmService holdAndConfirm;
    private final UniqueConstraintBookingService uniqueBooking;
    private final ObjectProvider<DistributedLockBookingService> distributedLock;
    private final BookingProperties properties;

    public DebugBookingController(
            UnsafeBookingService unsafeBooking,
            PessimisticBookingService pessimisticBooking,
            OptimisticBookingService optimisticBooking,
            InventoryService inventoryService,
            CounterService counterService,
            HoldAndConfirmService holdAndConfirm,
            UniqueConstraintBookingService uniqueBooking,
            ObjectProvider<DistributedLockBookingService> distributedLock,
            BookingProperties properties) {
        this.unsafeBooking = unsafeBooking;
        this.pessimisticBooking = pessimisticBooking;
        this.optimisticBooking = optimisticBooking;
        this.inventoryService = inventoryService;
        this.counterService = counterService;
        this.holdAndConfirm = holdAndConfirm;
        this.uniqueBooking = uniqueBooking;
        this.distributedLock = distributedLock;
        this.properties = properties;
    }

    @PostMapping("/unsafe/{seatId}")
    public Map<String, Object> unsafe(
            @PathVariable Long seatId,
            @RequestParam long userId,
            @RequestParam(required = false) Integer delayMs) {
        return run(userId, clock -> unsafeBooking.book(seatId, userId, delay(delayMs), clock));
    }

    @PostMapping("/pessimistic/{seatId}")
    public Map<String, Object> pessimistic(
            @PathVariable Long seatId,
            @RequestParam long userId,
            @RequestParam(required = false) Integer delayMs) {
        return run(userId, clock -> pessimisticBooking.book(seatId, userId, delay(delayMs), clock));
    }

    @PostMapping("/optimistic/{seatId}")
    public Map<String, Object> optimistic(
            @PathVariable Long seatId,
            @RequestParam long userId,
            @RequestParam(required = false) Integer delayMs) {
        return run(userId, clock -> optimisticBooking.book(seatId, userId, delay(delayMs), clock));
    }

    @PostMapping("/inventory/unsafe/{itemId}")
    public Map<String, Object> inventoryUnsafe(
            @PathVariable Long itemId,
            @RequestParam long userId,
            @RequestParam(defaultValue = "1") int quantity,
            @RequestParam(required = false) Integer delayMs) {
        return run(userId, clock -> inventoryService.bookUnsafe(itemId, quantity, userId, delay(delayMs), clock));
    }

    @PostMapping("/inventory/atomic/{itemId}")
    public Map<String, Object> inventoryAtomic(
            @PathVariable Long itemId,
            @RequestParam long userId,
            @RequestParam(defaultValue = "1") int quantity) {
        return run(userId, clock -> inventoryService.bookAtomic(itemId, quantity, userId, clock));
    }

    @PostMapping("/inventory/lock/{itemId}")
    public Map<String, Object> inventoryLock(
            @PathVariable Long itemId,
            @RequestParam long userId,
            @RequestParam(defaultValue = "1") int quantity,
            @RequestParam(required = false) Integer delayMs) {
        return run(userId, clock -> inventoryService.bookWithPessimisticLock(itemId, quantity, userId, delay(delayMs), clock));
    }

    @PostMapping("/counter/unsafe/{id}")
    public Map<String, Object> counterUnsafe(
            @PathVariable Long id,
            @RequestParam long userId,
            @RequestParam(required = false) Integer delayMs) {
        return run(userId, clock -> counterService.incrementUnsafe(id, userId, delay(delayMs), clock));
    }

    @PostMapping("/counter/atomic/{id}")
    public Map<String, Object> counterAtomic(@PathVariable Long id, @RequestParam long userId) {
        return run(userId, clock -> counterService.incrementAtomic(id, userId, clock));
    }

    @PostMapping("/distributed/{seatId}")
    public Map<String, Object> distributed(
            @PathVariable Long seatId,
            @RequestParam long userId,
            @RequestParam(required = false) Integer delayMs) {
        DistributedLockBookingService locker = distributedLock.getIfAvailable();
        if (locker == null) {
            return Map.of("success", false, "message", "Redis is not enabled");
        }
        return run(userId, clock -> locker.bookWithLock(seatId, userId, delay(delayMs), properties.getRedisLockTtlMs(), clock));
    }

    @PostMapping("/hold/{seatId}")
    public Map<String, Object> hold(
            @PathVariable Long seatId,
            @RequestParam long userId,
            @RequestParam(required = false) Integer delayMs,
            @RequestParam(required = false) Integer holdSeconds) {
        int hold = holdSeconds != null ? holdSeconds : properties.getHoldSeconds();
        return run(userId, clock -> holdAndConfirm.hold(seatId, userId, hold, delay(delayMs), clock));
    }

    @PostMapping("/hold/{seatId}/confirm")
    public Map<String, Object> confirmHold(@PathVariable Long seatId, @RequestParam long userId) {
        return run(userId, clock -> holdAndConfirm.confirm(seatId, userId, clock));
    }

    @PostMapping("/unique")
    public Map<String, Object> unique(
            @RequestParam long userId,
            @RequestParam(required = false) Integer delayMs) {
        return run(userId, clock -> uniqueBooking.book(DemoResetService.EVENT_ID, DemoResetService.SEAT, userId, delay(delayMs), clock));
    }

    private int delay(Integer delayMs) {
        return delayMs != null ? delayMs : properties.getDefaultDelayMs();
    }

    private Map<String, Object> run(long userId, java.util.function.Function<DemoClock, BookOutcome> action) {
        DemoClock clock = new DemoClock();
        BookOutcome outcome = action.apply(clock);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("success", outcome.isSuccess());
        body.put("message", outcome.getMessage());
        body.put("userId", userId);
        body.put("timeline", clock.snapshot());
        return body;
    }
}
