package com.example.booking.entity;

import com.example.booking.enums.BookingStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(
        name = "unique_booking",
        uniqueConstraints = @UniqueConstraint(name = "uk_event_seat", columnNames = {"event_id", "seat_number"})
)
@Getter
@Setter
@NoArgsConstructor
public class UniqueBooking {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "event_id")
    private Long eventId;

    @Column(name = "seat_number")
    private String seatNumber;

    private Long userId;

    @Enumerated(EnumType.STRING)
    private BookingStatus status;

    private Instant createdAt;

    public UniqueBooking(Long eventId, String seatNumber, Long userId, BookingStatus status) {
        this.eventId = eventId;
        this.seatNumber = seatNumber;
        this.userId = userId;
        this.status = status;
        this.createdAt = Instant.now();
    }
}
