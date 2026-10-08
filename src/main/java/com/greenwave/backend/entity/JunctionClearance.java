package com.greenwave.backend.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(
        name = "junction_clearances",
        uniqueConstraints = @UniqueConstraint(
                columnNames = {"emergency_session_id", "junction_id"}
        )
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class JunctionClearance {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "emergency_session_id", nullable = false)
    private UUID emergencySessionId;

    @Column(name = "junction_id", nullable = false)
    private UUID junctionId;

    @Column(nullable = false)
    private UUID clearedByUserId;

    @Column(nullable = false)
    private Instant clearedAt;
}