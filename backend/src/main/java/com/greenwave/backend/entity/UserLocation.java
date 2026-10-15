package com.greenwave.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import org.locationtech.jts.geom.Point;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "user_locations")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserLocation {

    @Id
    private UUID userId;

    @Column(columnDefinition = "geography(Point,4326)", nullable = false)
    private Point location;

    private Double heading;

    @Column(nullable = false)
    private Instant updatedAt;
}