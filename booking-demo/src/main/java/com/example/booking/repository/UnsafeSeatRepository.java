package com.example.booking.repository;

import com.example.booking.entity.UnsafeSeat;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface UnsafeSeatRepository extends JpaRepository<UnsafeSeat, Long> {
    Optional<UnsafeSeat> findBySeatNumber(String seatNumber);
}
