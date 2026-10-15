package com.greenwave.backend.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.locationtech.jts.geom.Point;

import java.util.UUID;

@Entity
@Table(name = "junctions")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Junction {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private String name;

    @Column(columnDefinition = "geography(Point,4326)", nullable = false)
    private Point location;
}