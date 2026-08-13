package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.entity.HoldableSeat;
import com.example.booking.enums.SeatStatus;
import com.example.booking.repository.HoldableSeatRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class HoldAndConfirmService {

    private final HoldableSeatRepository seats;

    public HoldAndConfirmService(HoldableSeatRepository seats) {
        this.seats = seats;
    }

    @Transactional
    public BookOutcome hold(Long seatId, Long userId, int holdSeconds, int delayMs, DemoClock clock) {
        clock.event(userId, "HOLD — SELECT FOR UPDATE");
        HoldableSeat seat = seats.findByIdWithPessimisticLock(seatId).orElseThrow();
        clock.event(userId, "status=" + seat.getStatus() + " heldBy=" + seat.getHeldBy());
        DemoClock.sleep(delayMs);

        Instant now = Instant.now();
        boolean expiredHold = seat.getStatus() == SeatStatus.HELD
                && seat.getHeldUntil() != null
                && seat.getHeldUntil().isBefore(now);

        if (seat.getStatus() == SeatStatus.AVAILABLE || expiredHold) {
            seat.setStatus(SeatStatus.HELD);
            seat.setHeldBy(userId);
            seat.setHeldUntil(now.plusSeconds(holdSeconds));
            seats.save(seat);
            String note = expiredHold ? " (previous hold expired)" : "";
            clock.event(userId, "HELD for " + holdSeconds + "s" + note);
            return BookOutcome.ok("Seat held for " + holdSeconds + " seconds. Complete payment." + note);
        }

        if (seat.getStatus() == SeatStatus.HELD && userId.equals(seat.getHeldBy())) {
            return BookOutcome.ok("You already hold this seat until " + seat.getHeldUntil());
        }

        clock.event(userId, "UNAVAILABLE status=" + seat.getStatus());
        return BookOutcome.fail("Seat unavailable. status=" + seat.getStatus() + " heldBy=" + seat.getHeldBy());
    }

    @Transactional
    public BookOutcome confirm(Long seatId, Long userId, DemoClock clock) {
        clock.event(userId, "CONFIRM after payment");
        HoldableSeat seat = seats.findByIdWithPessimisticLock(seatId).orElseThrow();
        if (seat.getStatus() != SeatStatus.HELD || !userId.equals(seat.getHeldBy())) {
            clock.event(userId, "No valid hold");
            return BookOutcome.fail("No valid hold found for this seat.");
        }
        if (seat.getHeldUntil().isBefore(Instant.now())) {
            seat.setStatus(SeatStatus.AVAILABLE);
            seat.setHeldBy(null);
            seat.setHeldUntil(null);
            seats.save(seat);
            clock.event(userId, "Hold expired — released");
            return BookOutcome.fail("Hold expired! Seat released.");
        }
        seat.setStatus(SeatStatus.BOOKED);
        seat.setBookedBy(userId);
        seat.setHeldBy(null);
        seat.setHeldUntil(null);
        seats.save(seat);
        clock.event(userId, "BOOKED");
        return BookOutcome.ok("Booking confirmed!");
    }
}
