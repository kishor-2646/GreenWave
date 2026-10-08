package com.greenwave.backend.entity;

import jakarta.persistence.*;
import lombok.*;

import org.locationtech.jts.geom.Point;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "emergency_sessions")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EmergencySession {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private UUID ambulanceUserId;

    @Column(nullable = false)
    private int criticality;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EmergencyStatus status;

    @Column(columnDefinition = "geography(Point,4326)", nullable = false)
    private Point destination;

    @Column(columnDefinition = "text")
    private String encodedPolyline;

    @Column(nullable = false)
    private Instant startedAt;

    private Instant endedAt;
}