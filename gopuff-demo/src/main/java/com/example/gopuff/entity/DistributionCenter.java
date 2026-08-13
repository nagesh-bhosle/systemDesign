package com.example.gopuff.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "distribution_centers")
@Getter
@Setter
@NoArgsConstructor
public class DistributionCenter {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String name;

    @Column(nullable = false)
    private double latitude;

    @Column(nullable = false)
    private double longitude;

    @Column(nullable = false)
    private String zipCode;

    /** First three digits of zip — partition / replica routing key. */
    @Column(nullable = false)
    private String regionId;

    /** Multiplier on mock drive time (e.g. river / border). */
    @Column(nullable = false)
    private double trafficFactor = 1.0;
}
