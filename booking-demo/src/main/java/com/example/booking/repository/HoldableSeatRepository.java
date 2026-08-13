package com.example.booking.repository;

import com.example.booking.entity.HoldableSeat;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Optional;

public interface HoldableSeatRepository extends JpaRepository<HoldableSeat, Long> {

    Optional<HoldableSeat> findBySeatNumber(String seatNumber);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM HoldableSeat s WHERE s.id = :id")
    Optional<HoldableSeat> findByIdWithPessimisticLock(@Param("id") Long id);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("UPDATE HoldableSeat s SET s.status = com.example.booking.enums.SeatStatus.AVAILABLE, "
            + "s.heldBy = null, s.heldUntil = null "
            + "WHERE s.status = com.example.booking.enums.SeatStatus.HELD AND s.heldUntil < :now")
    int releaseExpiredHolds(@Param("now") Instant now);
}
