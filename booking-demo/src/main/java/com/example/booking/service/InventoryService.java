package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.entity.InventoryBooking;
import com.example.booking.entity.InventoryItem;
import com.example.booking.enums.BookingStatus;
import com.example.booking.repository.InventoryBookingRepository;
import com.example.booking.repository.InventoryItemRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InventoryService {

    private final InventoryItemRepository items;
    private final InventoryBookingRepository bookings;

    public InventoryService(InventoryItemRepository items, InventoryBookingRepository bookings) {
        this.items = items;
        this.bookings = bookings;
    }

    @Transactional
    public BookOutcome bookUnsafe(Long itemId, int qty, Long userId, int delayMs, DemoClock clock) {
        clock.event(userId, "UNSAFE read-then-write inventory");
        InventoryItem item = items.findById(itemId).orElseThrow();
        clock.event(userId, "READ available=" + item.getAvailableQuantity() + " booked=" + item.getBookedQuantity());
        DemoClock.sleep(delayMs);
        if (item.getAvailableQuantity() < qty) {
            clock.event(userId, "REJECT not enough stock");
            return BookOutcome.fail("Not enough stock. Available=" + item.getAvailableQuantity());
        }
        item.setBookedQuantity(item.getBookedQuantity() + qty);
        items.save(item);
        bookings.save(new InventoryBooking(itemId, userId, qty, BookingStatus.CONFIRMED));
        clock.event(userId, "WRITE bookedQuantity=" + item.getBookedQuantity() + " (can oversell)");
        return BookOutcome.ok("Booked " + qty + " (unsafe path)");
    }

    @Transactional
    public BookOutcome bookAtomic(Long itemId, int qty, Long userId, DemoClock clock) {
        clock.event(userId, "ATOMIC UPDATE ... SET booked = booked + " + qty + " WHERE remaining >= " + qty);
        int rows = items.decreaseStockAtomically(itemId, qty);
        if (rows == 0) {
            clock.event(userId, "0 rows updated — guard rejected this booking");
            return BookOutcome.fail("Not enough stock available!");
        }
        bookings.save(new InventoryBooking(itemId, userId, qty, BookingStatus.CONFIRMED));
        InventoryItem item = items.findById(itemId).orElseThrow();
        clock.event(userId, "1 row updated. remaining=" + item.getAvailableQuantity());
        return BookOutcome.ok("Booked " + qty + " items. Remaining=" + item.getAvailableQuantity());
    }

    @Transactional
    public BookOutcome bookWithPessimisticLock(Long itemId, int qty, Long userId, int delayMs, DemoClock clock) {
        clock.event(userId, "PESSIMISTIC lock inventory row, then Java business rules");
        InventoryItem item = items.findByIdWithPessimisticLock(itemId).orElseThrow();
        clock.event(userId, "LOCK acquired. available=" + item.getAvailableQuantity());
        DemoClock.sleep(delayMs);
        if (item.getAvailableQuantity() < qty) {
            clock.event(userId, "REJECT after lock — only " + item.getAvailableQuantity() + " left");
            return BookOutcome.fail("Only " + item.getAvailableQuantity() + " items left!");
        }
        item.setBookedQuantity(item.getBookedQuantity() + qty);
        items.save(item);
        bookings.save(new InventoryBooking(itemId, userId, qty, BookingStatus.CONFIRMED));
        clock.event(userId, "Confirmed. remaining=" + item.getAvailableQuantity());
        return BookOutcome.ok("Confirmed. " + item.getAvailableQuantity() + " remaining.");
    }
}
