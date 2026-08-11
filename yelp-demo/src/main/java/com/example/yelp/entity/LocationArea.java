package com.example.yelp.entity;

import jakarta.persistence.*;
import lombok.*;

/**
 * Maps a location name (e.g. "San Francisco", "Mission District") to a
 * polygon stored as GeoJSON text. This lets us translate "Pizza in NYC"
 * into a geographic filter.
 *
 * In production this would be sourced from datasets like Geoapify or OSM.
 */
@Entity
@Table(name = "locations")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class LocationArea {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String name;          // e.g. "san_francisco"

    @Column(nullable = false)
    private String displayName;   // e.g. "San Francisco"

    @Column(nullable = false)
    private String type;          // "city", "neighborhood", "region"

    /** Bounding box for quick pre-filter: minLat, minLon, maxLat, maxLon */
    private Double minLat;
    private Double minLon;
    private Double maxLat;
    private Double maxLon;
}