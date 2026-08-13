package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.entity.UniqueBooking;
import com.example.booking.enums.BookingStatus;
import com.example.booking.repository.UniqueBookingRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UniqueConstraintBookingService {

    private final UniqueBookingRepository bookings;

    public UniqueConstraintBookingService(UniqueBookingRepository bookings) {
        this.bookings = bookings;
    }

    @Transactional
    public BookOutcome book(Long eventId, String seatNumber, Long userId, int delayMs, DemoClock clock) {
        clock.event(userId, "App check exists(event, seat) — racy, not sufficient alone");
        boolean exists = bookings.existsByEventIdAndSeatNumber(eventId, seatNumber);
        clock.event(userId, "exists=" + exists);
        DemoClock.sleep(delayMs);
        if (exists) {
            clock.event(userId, "App rejected duplicate");
            return BookOutcome.fail("App check: already booked");
        }
        try {
            bookings.saveAndFlush(new UniqueBooking(eventId, seatNumber, userId, BookingStatus.CONFIRMED));
            clock.event(userId, "INSERT succeeded");
            return BookOutcome.ok("Booking inserted for user " + userId);
        } catch (RuntimeException e) {
            if (isUniqueViolation(e)) {
                clock.event(userId, "UNIQUE constraint uk_event_seat rejected the INSERT (last safety net)");
                return BookOutcome.fail("DB unique constraint: event+seat already booked");
            }
            throw e;
        }
    }

    private static boolean isUniqueViolation(Throwable e) {
        while (e != null) {
            if (e instanceof DataIntegrityViolationException) {
                return true;
            }
            String name = e.getClass().getSimpleName();
            String msg = e.getMessage() == null ? "" : e.getMessage();
            if (name.contains("Constraint") || msg.toLowerCase().contains("uk_event_seat")
                    || msg.toLowerCase().contains("unique")) {
                return true;
            }
            e = e.getCause();
        }
        return false;
    }
}
