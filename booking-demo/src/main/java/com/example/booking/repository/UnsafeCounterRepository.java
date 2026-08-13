package com.example.booking.repository;

import com.example.booking.entity.UnsafeCounter;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface UnsafeCounterRepository extends JpaRepository<UnsafeCounter, Long> {
    Optional<UnsafeCounter> findByName(String name);
}
