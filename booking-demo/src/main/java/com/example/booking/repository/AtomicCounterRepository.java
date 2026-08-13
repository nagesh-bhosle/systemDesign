package com.example.booking.repository;

import com.example.booking.entity.AtomicCounter;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface AtomicCounterRepository extends JpaRepository<AtomicCounter, Long> {

    Optional<AtomicCounter> findByName(String name);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("UPDATE AtomicCounter c SET c.value = c.value + :delta WHERE c.id = :id")
    int increment(@Param("id") Long id, @Param("delta") int delta);
}
