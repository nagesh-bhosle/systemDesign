package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.entity.UnsafeSeat;
import com.example.booking.repository.UnsafeSeatRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UnsafeBookingService {

    private final UnsafeSeatRepository seats;

    public UnsafeBookingService(UnsafeSeatRepository seats) {
        this.seats = seats;
    }

    @Transactional
    public BookOutcome book(Long seatId, Long userId, int delayMs, DemoClock clock) {
        clock.event(userId, "BEGIN tx — no lock");
        UnsafeSeat seat = seats.findById(seatId).orElseThrow();
        clock.event(userId, "READ booked=" + seat.isBooked() + " bookedBy=" + seat.getBookedBy());
        DemoClock.sleep(delayMs);
        clock.event(userId, "WOKE after " + delayMs + "ms delay (other user may have booked by now)");
        if (seat.isBooked()) {
            clock.event(userId, "REJECT already booked");
            return BookOutcome.fail("Seat already booked by user " + seat.getBookedBy());
        }
        seat.setBooked(true);
        seat.setBookedBy(userId);
        seats.save(seat);
        clock.event(userId, "WRITE booked=true bookedBy=" + userId + " COMMIT");
        return BookOutcome.ok("Booking confirmed for user " + userId);
    }
}
