package com.example.booking.entity;

import com.example.booking.enums.BookingStatus;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(name = "inventory_booking")
@Getter
@Setter
@NoArgsConstructor
public class InventoryBooking {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long itemId;
    private Long userId;
    private int quantity;

    @Enumerated(EnumType.STRING)
    private BookingStatus status;

    private Instant createdAt;

    public InventoryBooking(Long itemId, Long userId, int quantity, BookingStatus status) {
        this.itemId = itemId;
        this.userId = userId;
        this.quantity = quantity;
        this.status = status;
        this.createdAt = Instant.now();
    }
}
