package com.example.booking.service;

import com.example.booking.config.BookingProperties;
import com.example.booking.dto.ConceptResult;
import com.example.booking.dto.ConceptResult.UserAttempt;
import com.example.booking.entity.AtomicCounter;
import com.example.booking.entity.HoldableSeat;
import com.example.booking.entity.InventoryItem;
import com.example.booking.entity.OptimisticSeat;
import com.example.booking.entity.PessimisticSeat;
import com.example.booking.entity.UnsafeCounter;
import com.example.booking.entity.UnsafeSeat;
import com.example.booking.repository.AtomicCounterRepository;
import com.example.booking.repository.HoldableSeatRepository;
import com.example.booking.repository.InventoryItemRepository;
import com.example.booking.repository.OptimisticSeatRepository;
import com.example.booking.repository.PessimisticSeatRepository;
import com.example.booking.repository.UniqueBookingRepository;
import com.example.booking.repository.UnsafeCounterRepository;
import com.example.booking.repository.UnsafeSeatRepository;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class ConceptDemoService {

    private final BookingProperties properties;
    private final DemoResetService reset;
    private final UnsafeBookingService unsafeBooking;
    private final PessimisticBookingService pessimisticBooking;
    private final OptimisticBookingService optimisticBooking;
    private final InventoryService inventoryService;
    private final CounterService counterService;
    private final HoldAndConfirmService holdAndConfirm;
    private final UniqueConstraintBookingService uniqueBooking;
    private final ObjectProvider<DistributedLockBookingService> distributedLock;
    private final UnsafeSeatRepository unsafeSeats;
    private final PessimisticSeatRepository pessimisticSeats;
    private final OptimisticSeatRepository optimisticSeats;
    private final InventoryItemRepository inventory;
    private final UnsafeCounterRepository unsafeCounters;
    private final AtomicCounterRepository atomicCounters;
    private final HoldableSeatRepository holdableSeats;
    private final UniqueBookingRepository uniqueBookings;

    public ConceptDemoService(
            BookingProperties properties,
            DemoResetService reset,
            UnsafeBookingService unsafeBooking,
            PessimisticBookingService pessimisticBooking,
            OptimisticBookingService optimisticBooking,
            InventoryService inventoryService,
            CounterService counterService,
            HoldAndConfirmService holdAndConfirm,
            UniqueConstraintBookingService uniqueBooking,
            ObjectProvider<DistributedLockBookingService> distributedLock,
            UnsafeSeatRepository unsafeSeats,
            PessimisticSeatRepository pessimisticSeats,
            OptimisticSeatRepository optimisticSeats,
            InventoryItemRepository inventory,
            UnsafeCounterRepository unsafeCounters,
            AtomicCounterRepository atomicCounters,
            HoldableSeatRepository holdableSeats,
            UniqueBookingRepository uniqueBookings) {
        this.properties = properties;
        this.reset = reset;
        this.unsafeBooking = unsafeBooking;
        this.pessimisticBooking = pessimisticBooking;
        this.optimisticBooking = optimisticBooking;
        this.inventoryService = inventoryService;
        this.counterService = counterService;
        this.holdAndConfirm = holdAndConfirm;
        this.uniqueBooking = uniqueBooking;
        this.distributedLock = distributedLock;
        this.unsafeSeats = unsafeSeats;
        this.pessimisticSeats = pessimisticSeats;
        this.optimisticSeats = optimisticSeats;
        this.inventory = inventory;
        this.unsafeCounters = unsafeCounters;
        this.atomicCounters = atomicCounters;
        this.holdableSeats = holdableSeats;
        this.uniqueBookings = uniqueBookings;
    }

    public ConceptResult raceCondition(int users, int delayMs) {
        UnsafeSeat seat = reset.resetUnsafeSeat();
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> unsafeBooking.book(seat.getId(), userId, delayMs, clock));
        UnsafeSeat after = unsafeSeats.findById(seat.getId()).orElseThrow();

        ConceptResult result = ConcurrentUsers.base("RACE_CONDITION", "Two users, no lock — double booking");
        result.setProblem("Both threads read booked=false, both write booked=true. Last write wins in the row, but both think they succeeded.");
        result.setHowThisEndpointWorks("Resets seat A1, then starts " + users
                + " threads that read, sleep " + delayMs + "ms, then write — no SELECT FOR UPDATE and no @Version.");
        result.setExpectedInvariant("Exactly one confirmed booking");
        long wins = ConcurrentUsers.successCount(attempts);
        result.setInvariantHeld(wins == 1);
        result.setActualOutcome(wins > 1
                ? "DOUBLE BOOKING: " + wins + " users got a confirmation"
                : (wins == 1 ? "Only one succeeded this run (increase delayMs if the race did not appear)" : "Nobody booked"));
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of(
                "seatNumber", after.getSeatNumber(),
                "booked", after.isBooked(),
                "bookedBy", after.getBookedBy() == null ? "none" : after.getBookedBy(),
                "successCount", wins));
        result.setWatchInDebugger("UnsafeBookingService.book — breakpoint after findById and after the sleep");
        result.setRelatedManualApis("POST /api/debug/unsafe/{seatId}?userId=1&delayMs=2000  (hit twice from two terminals)");
        return result;
    }

    public ConceptResult pessimisticLock(int users, int delayMs) {
        PessimisticSeat seat = reset.resetPessimisticSeat();
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> pessimisticBooking.book(seat.getId(), userId, delayMs, clock));
        PessimisticSeat after = pessimisticSeats.findById(seat.getId()).orElseThrow();
        long wins = ConcurrentUsers.successCount(attempts);

        ConceptResult result = ConcurrentUsers.base("PESSIMISTIC_LOCK", "SELECT ... FOR UPDATE serializes the two users");
        result.setProblem("Same race as /race-condition, but the second transaction BLOCKS until the first commits.");
        result.setHowThisEndpointWorks("JPA @Lock(PESSIMISTIC_WRITE) issues FOR UPDATE. User 2 waits, then reads booked=true and rejects.");
        result.setExpectedInvariant("Exactly one confirmed booking");
        result.setInvariantHeld(wins == 1);
        result.setActualOutcome(wins == 1
                ? "Fixed: one confirmed, others rejected after waiting for the row lock"
                : "Unexpected successCount=" + wins);
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of(
                "seatNumber", after.getSeatNumber(),
                "booked", after.isBooked(),
                "bookedBy", after.getBookedBy() == null ? "none" : after.getBookedBy(),
                "successCount", wins,
                "note", "Look at elapsedMs: the loser usually waited ~delayMs while blocked"));
        result.setWatchInDebugger("PessimisticSeatRepository.findByIdWithPessimisticLock — second thread sits here until lock is free");
        result.setRelatedManualApis("POST /api/debug/pessimistic/{seatId}?userId=1&delayMs=3000");
        return result;
    }

    public ConceptResult optimisticLock(int users, int delayMs) {
        OptimisticSeat seat = reset.resetOptimisticSeat();
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> optimisticBooking.book(seat.getId(), userId, delayMs, clock));
        OptimisticSeat after = optimisticSeats.findById(seat.getId()).orElseThrow();
        long wins = ConcurrentUsers.successCount(attempts);

        ConceptResult result = ConcurrentUsers.base("OPTIMISTIC_LOCK", "@Version — no blocking, loser gets OptimisticLockingFailureException");
        result.setProblem("Both users read version=N. First UPDATE bumps version. Second UPDATE WHERE version=N updates 0 rows.");
        result.setHowThisEndpointWorks("Hibernate adds WHERE version=? on flush. Spring throws OptimisticLockingFailureException.");
        result.setExpectedInvariant("Exactly one confirmed booking");
        result.setInvariantHeld(wins == 1);
        result.setActualOutcome(wins == 1
                ? "Fixed: one commit, others failed on version mismatch (no thread blocking)"
                : "Unexpected successCount=" + wins);
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of(
                "seatNumber", after.getSeatNumber(),
                "booked", after.isBooked(),
                "bookedBy", after.getBookedBy() == null ? "none" : after.getBookedBy(),
                "version", after.getVersion(),
                "successCount", wins));
        result.setWatchInDebugger("OptimisticBookingService.book — catch OptimisticLockingFailureException after saveAndFlush");
        result.setRelatedManualApis("POST /api/debug/optimistic/{seatId}?userId=1&delayMs=3000");
        return result;
    }

    public ConceptResult unsafeInventory(int users, int qtyEach, int delayMs) {
        InventoryItem item = reset.resetInventory(DemoResetService.LAST_TICKET, 1);
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> inventoryService.bookUnsafe(item.getId(), qtyEach, userId, delayMs, clock));
        InventoryItem after = inventory.findById(item.getId()).orElseThrow();
        long wins = ConcurrentUsers.successCount(attempts);
        boolean oversold = wins > 1 || after.getBookedQuantity() > after.getTotalQuantity();

        ConceptResult result = ConcurrentUsers.base("UNSAFE_INVENTORY", "Count in Java — oversell when stock is 1");
        result.setProblem("Two users each see available=1 and both confirm. bookedQuantity may stay 1 (lost update) while two booking rows exist.");
        result.setHowThisEndpointWorks("LAST-TICKET has total=1. Each user books " + qtyEach + " after a delay, using entity fields (not a guarded UPDATE).");
        result.setExpectedInvariant("Exactly one confirmation and bookedQuantity <= totalQuantity");
        result.setInvariantHeld(!oversold);
        result.setActualOutcome(oversold
                ? "BROKEN: confirmations=" + wins + " bookedQuantity=" + after.getBookedQuantity() + " total=" + after.getTotalQuantity()
                : "Did not race this run — increase delayMs");
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(inventoryState(after));
        result.setWatchInDebugger("InventoryService.bookUnsafe — after getAvailableQuantity() and after setBookedQuantity");
        result.setRelatedManualApis("POST /api/debug/inventory/unsafe/{itemId}?userId=1&quantity=1&delayMs=2000");
        return result;
    }

    public ConceptResult atomicUpdate(int users, int qtyEach) {
        InventoryItem item = reset.resetInventory(DemoResetService.LAST_TICKET, 1);
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> inventoryService.bookAtomic(item.getId(), qtyEach, userId, clock));
        InventoryItem after = inventory.findById(item.getId()).orElseThrow();
        long wins = ConcurrentUsers.successCount(attempts);
        boolean ok = after.getBookedQuantity() <= after.getTotalQuantity() && wins == 1;

        ConceptResult result = ConcurrentUsers.base("ATOMIC_UPDATE", "Single UPDATE with WHERE remaining >= qty");
        result.setProblem("Same last-ticket race, solved inside the database engine (row write is serialized + guard).");
        result.setHowThisEndpointWorks("UPDATE bookedQuantity = bookedQuantity + qty WHERE (total - booked) >= qty. rowsUpdated==0 means reject.");
        result.setExpectedInvariant("Exactly one booking and bookedQuantity == 1");
        result.setInvariantHeld(ok);
        result.setActualOutcome(ok
                ? "Fixed: one user got the ticket, others saw 0 rows updated"
                : "Unexpected booked=" + after.getBookedQuantity() + " wins=" + wins);
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(inventoryState(after));
        result.setWatchInDebugger("InventoryItemRepository.decreaseStockAtomically — inspect the UPDATE SQL in the console");
        result.setRelatedManualApis("POST /api/debug/inventory/atomic/{itemId}?userId=1&quantity=1");
        return result;
    }

    public ConceptResult pessimisticInventory(int users, int qtyEach, int delayMs) {
        InventoryItem item = reset.resetInventory(DemoResetService.WIDGET, 5);
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> inventoryService.bookWithPessimisticLock(item.getId(), qtyEach, userId, delayMs, clock));
        InventoryItem after = inventory.findById(item.getId()).orElseThrow();
        boolean ok = after.getBookedQuantity() <= after.getTotalQuantity();

        ConceptResult result = ConcurrentUsers.base("PESSIMISTIC_INVENTORY", "Lock row, then apply Java rules, then decrement");
        result.setProblem("Use this when you need more than a single SQL guard (max per user, loyalty, etc.).");
        result.setHowThisEndpointWorks("WIDGET has 5 in stock. " + users + " users each take " + qtyEach
                + " under FOR UPDATE so the remaining count is always consistent.");
        result.setExpectedInvariant("bookedQuantity <= totalQuantity");
        result.setInvariantHeld(ok);
        result.setActualOutcome("booked=" + after.getBookedQuantity() + " remaining=" + after.getAvailableQuantity());
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(inventoryState(after));
        result.setWatchInDebugger("InventoryService.bookWithPessimisticLock");
        result.setRelatedManualApis("POST /api/debug/inventory/lock/{itemId}?userId=1&quantity=2&delayMs=2000");
        return result;
    }

    public ConceptResult unsafeCounter(int users, int incrementsEach, int delayMs) {
        reset.resetCounters();
        UnsafeCounter counter = unsafeCounters.findByName(DemoResetService.COUNTER).orElseThrow();
        DemoClock clock = new DemoClock();
        int expected = users * incrementsEach;
        List<UserAttempt> attempts = ConcurrentUsers.run(users, userId -> {
            for (int i = 0; i < incrementsEach; i++) {
                counterService.incrementUnsafe(counter.getId(), userId, delayMs, clock);
            }
            return com.example.booking.dto.BookOutcome.ok("Finished " + incrementsEach + " increments");
        });
        UnsafeCounter after = unsafeCounters.findById(counter.getId()).orElseThrow();
        boolean lost = after.getValue() < expected;

        ConceptResult result = ConcurrentUsers.base("UNSAFE_COUNTER", "Lost updates on a counter");
        result.setProblem("Read value, add 1 in Java, write back. Concurrent writes discard each other.");
        result.setHowThisEndpointWorks(users + " users each increment " + incrementsEach + " times. Expected final value=" + expected + ".");
        result.setExpectedInvariant("value == " + expected);
        result.setInvariantHeld(!lost);
        result.setActualOutcome(lost
                ? "LOST UPDATES: value=" + after.getValue() + " expected=" + expected
                : "No loss this run — increase delayMs or incrementsEach");
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of("name", after.getName(), "value", after.getValue(), "expected", expected));
        result.setWatchInDebugger("CounterService.incrementUnsafe");
        result.setRelatedManualApis("POST /api/debug/counter/unsafe/{id}?userId=1&delayMs=50");
        return result;
    }

    public ConceptResult atomicCounter(int users, int incrementsEach) {
        reset.resetCounters();
        AtomicCounter counter = atomicCounters.findByName(DemoResetService.COUNTER).orElseThrow();
        DemoClock clock = new DemoClock();
        int expected = users * incrementsEach;
        List<UserAttempt> attempts = ConcurrentUsers.run(users, userId -> {
            for (int i = 0; i < incrementsEach; i++) {
                counterService.incrementAtomic(counter.getId(), userId, clock);
            }
            return com.example.booking.dto.BookOutcome.ok("Finished " + incrementsEach + " atomic increments");
        });
        AtomicCounter after = atomicCounters.findById(counter.getId()).orElseThrow();
        boolean ok = after.getValue() == expected;

        ConceptResult result = ConcurrentUsers.base("ATOMIC_COUNTER", "UPDATE value = value + 1 (DB atomic increment)");
        result.setProblem("Same lost-update problem, solved with one SQL increment so the engine serializes the row.");
        result.setHowThisEndpointWorks(users + " users each increment " + incrementsEach + " times. Expected=" + expected + ".");
        result.setExpectedInvariant("value == " + expected);
        result.setInvariantHeld(ok);
        result.setActualOutcome(ok
                ? "Fixed: value=" + after.getValue()
                : "Unexpected value=" + after.getValue() + " expected=" + expected);
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of("name", after.getName(), "value", after.getValue(), "expected", expected));
        result.setWatchInDebugger("AtomicCounterRepository.increment");
        result.setRelatedManualApis("POST /api/debug/counter/atomic/{id}?userId=1");
        return result;
    }

    public ConceptResult distributedLock(int users, int delayMs) {
        DistributedLockBookingService locker = distributedLock.getIfAvailable();
        if (locker == null) {
            ConceptResult missing = ConcurrentUsers.base("DISTRIBUTED_LOCK", "Redis lock not available");
            missing.setProblem("StringRedisTemplate is not on the classpath/context (test profile excludes Redis).");
            missing.setHowThisEndpointWorks("Start with Docker Redis (./start.sh) so this endpoint can run.");
            missing.setExpectedInvariant("Exactly one booking");
            missing.setInvariantHeld(false);
            missing.setActualOutcome("Skipped — Redis bean missing");
            return missing;
        }
        UnsafeSeat seat = reset.resetUnsafeSeat();
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> locker.bookWithLock(seat.getId(), userId, delayMs, properties.getRedisLockTtlMs(), clock));
        UnsafeSeat after = unsafeSeats.findById(seat.getId()).orElseThrow();
        long wins = ConcurrentUsers.successCount(attempts);

        ConceptResult result = ConcurrentUsers.base("DISTRIBUTED_LOCK", "Redis SET NX — mutex across app instances");
        result.setProblem("FOR UPDATE only works inside one database. Multiple pods need a lock both can see (Redis).");
        result.setHowThisEndpointWorks("SET booking-lock:seat:{id} NX PX ttl, then the same unsafe book method. Only the lock holder enters.");
        result.setExpectedInvariant("Exactly one confirmed booking");
        result.setInvariantHeld(wins == 1);
        result.setActualOutcome(wins == 1
                ? "Fixed at cluster level: one lock holder booked, others got 'system busy' or already-booked"
                : "Unexpected successCount=" + wins);
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of(
                "seatNumber", after.getSeatNumber(),
                "booked", after.isBooked(),
                "bookedBy", after.getBookedBy() == null ? "none" : after.getBookedBy(),
                "successCount", wins));
        result.setWatchInDebugger("DistributedLockBookingService.bookWithLock — setIfAbsent then unsafe book");
        result.setRelatedManualApis("POST /api/debug/distributed/{seatId}?userId=1&delayMs=2000");
        return result;
    }

    public ConceptResult holdAndConfirm(int users, int delayMs, int holdSeconds) {
        HoldableSeat seat = reset.resetHoldable();
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> holdAndConfirm.hold(seat.getId(), userId, holdSeconds, delayMs, clock));
        HoldableSeat after = holdableSeats.findById(seat.getId()).orElseThrow();
        long wins = ConcurrentUsers.successCount(attempts);

        ConceptResult result = ConcurrentUsers.base("HOLD_AND_CONFIRM", "Temporary HOLD then CONFIRM (Ticketmaster-style)");
        result.setProblem("Do not mark BOOKED before payment. Hold the seat, expire it, confirm after pay.");
        result.setHowThisEndpointWorks(users + " users race to HOLD seat A1 for " + holdSeconds
                + "s. Only one gets HELD. Confirm with POST /api/concepts/hold-and-confirm/confirm?userId={winner}.");
        result.setExpectedInvariant("At most one holder");
        result.setInvariantHeld(wins == 1 && after.getHeldBy() != null);
        result.setActualOutcome("status=" + after.getStatus() + " heldBy=" + after.getHeldBy()
                + " until=" + after.getHeldUntil()
                + ". Confirm or wait for HoldCleanupJob (every 5s).");
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("status", after.getStatus().name());
        state.put("heldBy", after.getHeldBy());
        state.put("heldUntil", after.getHeldUntil() == null ? null : after.getHeldUntil().toString());
        state.put("bookedBy", after.getBookedBy());
        state.put("seatId", after.getId());
        result.setFinalState(state);
        result.setWatchInDebugger("HoldAndConfirmService.hold / confirm; HoldCleanupJob.releaseExpiredHolds");
        result.setRelatedManualApis("POST /api/concepts/hold-and-confirm/confirm?userId=1  and  POST /api/debug/hold/{seatId}?userId=1");
        return result;
    }

    public ConceptResult confirmHold(long userId) {
        HoldableSeat seat = holdableSeats.findBySeatNumber(DemoResetService.SEAT).orElseThrow();
        DemoClock clock = new DemoClock();
        var outcome = holdAndConfirm.confirm(seat.getId(), userId, clock);
        HoldableSeat after = holdableSeats.findById(seat.getId()).orElseThrow();
        ConceptResult result = ConcurrentUsers.base("HOLD_CONFIRM", "Payment succeeded — convert HOLD to BOOKED");
        result.setProblem("Only the user who holds the seat may confirm, and only before heldUntil.");
        result.setHowThisEndpointWorks("Pessimistic lock, check heldBy + expiry, set BOOKED.");
        result.setExpectedInvariant("BOOKED by the holder");
        result.setInvariantHeld(outcome.isSuccess());
        result.setActualOutcome(outcome.getMessage());
        result.setUsers(List.of(new UserAttempt(userId, outcome.isSuccess(), outcome.getMessage(), 0)));
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of(
                "status", after.getStatus().name(),
                "bookedBy", after.getBookedBy() == null ? "none" : after.getBookedBy()));
        return result;
    }

    public ConceptResult uniqueConstraint(int users, int delayMs) {
        uniqueBookings.deleteAll();
        DemoClock clock = new DemoClock();
        List<UserAttempt> attempts = ConcurrentUsers.run(users,
                userId -> uniqueBooking.book(DemoResetService.EVENT_ID, DemoResetService.SEAT, userId, delayMs, clock));
        var rows = uniqueBookings.findByEventIdAndSeatNumber(DemoResetService.EVENT_ID, DemoResetService.SEAT);
        long wins = ConcurrentUsers.successCount(attempts);

        ConceptResult result = ConcurrentUsers.base("UNIQUE_CONSTRAINT", "Last safety net: UNIQUE(event_id, seat_number)");
        result.setProblem("App-level exists() check is racy. The unique index still rejects the second INSERT.");
        result.setHowThisEndpointWorks("Both users see exists=false, both INSERT. One gets DataIntegrityViolationException.");
        result.setExpectedInvariant("Exactly one row for event 100 / seat A1");
        result.setInvariantHeld(rows.size() == 1 && wins == 1);
        result.setActualOutcome("DB rows=" + rows.size() + " app successes=" + wins);
        result.setUsers(attempts);
        result.setTimeline(clock.snapshot());
        result.setFinalState(Map.of(
                "eventId", DemoResetService.EVENT_ID,
                "seatNumber", DemoResetService.SEAT,
                "rowCount", rows.size(),
                "winnerUserId", rows.isEmpty() ? "none" : rows.getFirst().getUserId()));
        result.setWatchInDebugger("UniqueConstraintBookingService.book — catch DataIntegrityViolationException");
        result.setRelatedManualApis("POST /api/debug/unique?userId=1&delayMs=2000");
        return result;
    }

    public Map<String, Object> snapshot() {
        Map<String, Object> out = new LinkedHashMap<>();
        unsafeSeats.findBySeatNumber(DemoResetService.SEAT).ifPresent(s ->
                out.put("unsafeSeat", Map.of("id", s.getId(), "booked", s.isBooked(), "bookedBy", String.valueOf(s.getBookedBy()))));
        pessimisticSeats.findBySeatNumber(DemoResetService.SEAT).ifPresent(s ->
                out.put("pessimisticSeat", Map.of("id", s.getId(), "booked", s.isBooked(), "bookedBy", String.valueOf(s.getBookedBy()))));
        optimisticSeats.findBySeatNumber(DemoResetService.SEAT).ifPresent(s ->
                out.put("optimisticSeat", Map.of("id", s.getId(), "booked", s.isBooked(), "bookedBy", String.valueOf(s.getBookedBy()), "version", s.getVersion())));
        inventory.findByItemName(DemoResetService.LAST_TICKET).ifPresent(i -> out.put("lastTicket", inventoryState(i)));
        inventory.findByItemName(DemoResetService.WIDGET).ifPresent(i -> out.put("widget", inventoryState(i)));
        unsafeCounters.findByName(DemoResetService.COUNTER).ifPresent(c ->
                out.put("unsafeCounter", Map.of("id", c.getId(), "value", c.getValue())));
        atomicCounters.findByName(DemoResetService.COUNTER).ifPresent(c ->
                out.put("atomicCounter", Map.of("id", c.getId(), "value", c.getValue())));
        holdableSeats.findBySeatNumber(DemoResetService.SEAT).ifPresent(s ->
                out.put("holdableSeat", Map.of(
                        "id", s.getId(),
                        "status", s.getStatus().name(),
                        "heldBy", String.valueOf(s.getHeldBy()),
                        "heldUntil", String.valueOf(s.getHeldUntil()),
                        "bookedBy", String.valueOf(s.getBookedBy()))));
        out.put("uniqueBookings", uniqueBookings.count());
        return out;
    }

    private static Map<String, Object> inventoryState(InventoryItem item) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("id", item.getId());
        map.put("itemName", item.getItemName());
        map.put("totalQuantity", item.getTotalQuantity());
        map.put("bookedQuantity", item.getBookedQuantity());
        map.put("available", item.getAvailableQuantity());
        return map;
    }
}
