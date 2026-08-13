package com.example.booking.repository;

import com.example.booking.entity.UniqueBooking;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface UniqueBookingRepository extends JpaRepository<UniqueBooking, Long> {

    boolean existsByEventIdAndSeatNumber(Long eventId, String seatNumber);

    List<UniqueBooking> findByEventIdAndSeatNumber(Long eventId, String seatNumber);
}
