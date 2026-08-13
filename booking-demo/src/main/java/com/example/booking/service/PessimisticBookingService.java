package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.entity.PessimisticSeat;
import com.example.booking.repository.PessimisticSeatRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PessimisticBookingService {

    private final PessimisticSeatRepository seats;

    public PessimisticBookingService(PessimisticSeatRepository seats) {
        this.seats = seats;
    }

    @Transactional
    public BookOutcome book(Long seatId, Long userId, int delayMs, DemoClock clock) {
        clock.event(userId, "BEGIN tx — SELECT ... FOR UPDATE (will BLOCK if another tx holds the row)");
        PessimisticSeat seat = seats.findByIdWithPessimisticLock(seatId).orElseThrow();
        clock.event(userId, "LOCK acquired. READ booked=" + seat.isBooked() + " bookedBy=" + seat.getBookedBy());
        DemoClock.sleep(delayMs);
        clock.event(userId, "Still holding row lock after " + delayMs + "ms");
        if (seat.isBooked()) {
            clock.event(userId, "REJECT already booked — will COMMIT and RELEASE lock");
            return BookOutcome.fail("Seat already booked by user " + seat.getBookedBy());
        }
        seat.setBooked(true);
        seat.setBookedBy(userId);
        seats.save(seat);
        clock.event(userId, "WRITE booked=true bookedBy=" + userId + " COMMIT — lock released");
        return BookOutcome.ok("Booking confirmed for user " + userId);
    }
}
