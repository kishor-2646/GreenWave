package com.greenwave.backend.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.*;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "police_assignments")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PoliceAssignment {

    @Id
    private UUID userId;

    @Column(nullable = false)



    private UUID junctionId;

    @Column(nullable = false)
    private Instant updatedAt;
}