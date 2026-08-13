package com.example.booking.repository;

import com.example.booking.entity.InventoryBooking;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface InventoryBookingRepository extends JpaRepository<InventoryBooking, Long> {

    List<InventoryBooking> findByItemId(Long itemId);
}
