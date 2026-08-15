package com.example.booking.repository;

import com.example.booking.entity.OptimisticSeat;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface OptimisticSeatRepository extends JpaRepository<OptimisticSeat, Long> {
    Optional<OptimisticSeat> findBySeatNumber(String seatNumber);
}
