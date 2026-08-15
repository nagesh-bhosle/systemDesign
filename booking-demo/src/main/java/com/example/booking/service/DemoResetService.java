package com.example.booking.service;

import com.example.booking.entity.AtomicCounter;
import com.example.booking.entity.HoldableSeat;
import com.example.booking.entity.InventoryItem;
import com.example.booking.entity.OptimisticSeat;
import com.example.booking.entity.PessimisticSeat;
import com.example.booking.entity.UnsafeCounter;
import com.example.booking.entity.UnsafeSeat;
import com.example.booking.enums.SeatStatus;
import com.example.booking.repository.AtomicCounterRepository;
import com.example.booking.repository.HoldableSeatRepository;
import com.example.booking.repository.InventoryBookingRepository;
import com.example.booking.repository.InventoryItemRepository;
import com.example.booking.repository.OptimisticSeatRepository;
import com.example.booking.repository.PessimisticSeatRepository;
import com.example.booking.repository.UniqueBookingRepository;
import com.example.booking.repository.UnsafeCounterRepository;
import com.example.booking.repository.UnsafeSeatRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DemoResetService {

    public static final String SEAT = "A1";
    public static final String LAST_TICKET = "LAST-TICKET";
    public static final String WIDGET = "WIDGET";
    public static final String COUNTER = "page-views";
    public static final long EVENT_ID = 100L;

    private final UnsafeSeatRepository unsafeSeats;
    private final PessimisticSeatRepository pessimisticSeats;
    private final OptimisticSeatRepository optimisticSeats;
    private final InventoryItemRepository inventory;
    private final InventoryBookingRepository inventoryBookings;
    private final UnsafeCounterRepository unsafeCounters;
    private final AtomicCounterRepository atomicCounters;
    private final HoldableSeatRepository holdableSeats;
    private final UniqueBookingRepository uniqueBookings;

    public DemoResetService(
            UnsafeSeatRepository unsafeSeats,
            PessimisticSeatRepository pessimisticSeats,
            OptimisticSeatRepository optimisticSeats,
            InventoryItemRepository inventory,
            InventoryBookingRepository inventoryBookings,
            UnsafeCounterRepository unsafeCounters,
            AtomicCounterRepository atomicCounters,
            HoldableSeatRepository holdableSeats,
            UniqueBookingRepository uniqueBookings) {
        this.unsafeSeats = unsafeSeats;
        this.pessimisticSeats = pessimisticSeats;
        this.optimisticSeats = optimisticSeats;
        this.inventory = inventory;
        this.inventoryBookings = inventoryBookings;
        this.unsafeCounters = unsafeCounters;
        this.atomicCounters = atomicCounters;
        this.holdableSeats = holdableSeats;
        this.uniqueBookings = uniqueBookings;
    }

    @Transactional
    public void seedIfEmpty() {
        if (unsafeSeats.findBySeatNumber(SEAT).isEmpty()) {
            UnsafeSeat s = new UnsafeSeat();
            s.setSeatNumber(SEAT);
            unsafeSeats.save(s);
        }
        if (pessimisticSeats.findBySeatNumber(SEAT).isEmpty()) {
            PessimisticSeat s = new PessimisticSeat();
            s.setSeatNumber(SEAT);
            pessimisticSeats.save(s);
        }
        if (optimisticSeats.findBySeatNumber(SEAT).isEmpty()) {
            OptimisticSeat s = new OptimisticSeat();
            s.setSeatNumber(SEAT);
            optimisticSeats.save(s);
        }
        if (inventory.findByItemName(LAST_TICKET).isEmpty()) {
            InventoryItem item = new InventoryItem();
            item.setItemName(LAST_TICKET);
            item.setTotalQuantity(1);
            item.setBookedQuantity(0);
            inventory.save(item);
        }
        if (inventory.findByItemName(WIDGET).isEmpty()) {
            InventoryItem item = new InventoryItem();
            item.setItemName(WIDGET);
            item.setTotalQuantity(5);
            item.setBookedQuantity(0);
            inventory.save(item);
        }
        if (unsafeCounters.findByName(COUNTER).isEmpty()) {
            UnsafeCounter c = new UnsafeCounter();
            c.setName(COUNTER);
            c.setValue(0);
            unsafeCounters.save(c);
        }
        if (atomicCounters.findByName(COUNTER).isEmpty()) {
            AtomicCounter c = new AtomicCounter();
            c.setName(COUNTER);
            c.setValue(0);
            atomicCounters.save(c);
        }
        if (holdableSeats.findBySeatNumber(SEAT).isEmpty()) {
            HoldableSeat s = new HoldableSeat();
            s.setSeatNumber(SEAT);
            s.setStatus(SeatStatus.AVAILABLE);
            holdableSeats.save(s);
        }
    }

    @Transactional
    public void resetAll() {
        seedIfEmpty();
        resetUnsafeSeat();
        resetPessimisticSeat();
        resetOptimisticSeat();
        resetInventory(LAST_TICKET, 1);
        resetInventory(WIDGET, 5);
        resetCounters();
        resetHoldable();
        uniqueBookings.deleteAll();
    }

    @Transactional
    public UnsafeSeat resetUnsafeSeat() {
        UnsafeSeat s = unsafeSeats.findBySeatNumber(SEAT).orElseThrow();
        s.setBooked(false);
        s.setBookedBy(null);
        return unsafeSeats.save(s);
    }

    @Transactional
    public PessimisticSeat resetPessimisticSeat() {
        PessimisticSeat s = pessimisticSeats.findBySeatNumber(SEAT).orElseThrow();
        s.setBooked(false);
        s.setBookedBy(null);
        return pessimisticSeats.save(s);
    }

    @Transactional
    public OptimisticSeat resetOptimisticSeat() {
        OptimisticSeat s = optimisticSeats.findBySeatNumber(SEAT).orElseThrow();
        s.setBooked(false);
        s.setBookedBy(null);
        return optimisticSeats.save(s);
    }

    @Transactional
    public InventoryItem resetInventory(String name, int total) {
        InventoryItem item = inventory.findByItemName(name).orElseThrow();
        item.setTotalQuantity(total);
        item.setBookedQuantity(0);
        inventoryBookings.deleteAll(inventoryBookings.findByItemId(item.getId()));
        return inventory.save(item);
    }

    @Transactional
    public void resetCounters() {
        UnsafeCounter u = unsafeCounters.findByName(COUNTER).orElseThrow();
        u.setValue(0);
        unsafeCounters.save(u);
        AtomicCounter a = atomicCounters.findByName(COUNTER).orElseThrow();
        a.setValue(0);
        atomicCounters.save(a);
    }

    @Transactional
    public HoldableSeat resetHoldable() {
        HoldableSeat s = holdableSeats.findBySeatNumber(SEAT).orElseThrow();
        s.setStatus(SeatStatus.AVAILABLE);
        s.setHeldBy(null);
        s.setHeldUntil(null);
        s.setBookedBy(null);
        return holdableSeats.save(s);
    }
}
