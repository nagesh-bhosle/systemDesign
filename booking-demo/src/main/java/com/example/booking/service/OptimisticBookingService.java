package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.entity.OptimisticSeat;
import com.example.booking.repository.OptimisticSeatRepository;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OptimisticBookingService {

    private final OptimisticSeatRepository seats;

    public OptimisticBookingService(OptimisticSeatRepository seats) {
        this.seats = seats;
    }

    @Transactional
    public BookOutcome book(Long seatId, Long userId, int delayMs, DemoClock clock) {
        try {
            clock.event(userId, "BEGIN tx — no row lock; @Version will be checked on UPDATE");
            OptimisticSeat seat = seats.findById(seatId).orElseThrow();
            clock.event(userId, "READ booked=" + seat.isBooked() + " version=" + seat.getVersion());
            DemoClock.sleep(delayMs);
            if (seat.isBooked()) {
                clock.event(userId, "REJECT already booked");
                return BookOutcome.fail("Seat already booked by user " + seat.getBookedBy());
            }
            seat.setBooked(true);
            seat.setBookedBy(userId);
            seats.saveAndFlush(seat);
            clock.event(userId, "UPDATE ... WHERE version=" + (seat.getVersion() - 1) + " succeeded; new version=" + seat.getVersion());
            return BookOutcome.ok("Booking confirmed for user " + userId);
        } catch (OptimisticLockingFailureException e) {
            clock.event(userId, "OptimisticLockingFailureException — 0 rows updated, version already changed");
            return BookOutcome.fail("Conflict: someone else booked this seat (version mismatch). Try again.");
        }
    }
}
