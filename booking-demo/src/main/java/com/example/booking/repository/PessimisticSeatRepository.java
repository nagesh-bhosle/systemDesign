package com.example.booking.repository;

import com.example.booking.entity.PessimisticSeat;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface PessimisticSeatRepository extends JpaRepository<PessimisticSeat, Long> {

    Optional<PessimisticSeat> findBySeatNumber(String seatNumber);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM PessimisticSeat s WHERE s.id = :id")
    Optional<PessimisticSeat> findByIdWithPessimisticLock(@Param("id") Long id);
}
