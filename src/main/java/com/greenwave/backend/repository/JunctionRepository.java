package com.greenwave.backend.repository;

import com.greenwave.backend.entity.Junction;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface JunctionRepository extends JpaRepository<Junction, UUID> {

    @Query(value = """
            SELECT * FROM junctions
            ORDER BY location <-> ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)::geography
            LIMIT 1
            """, nativeQuery = true)
    Optional<Junction> findNearestJunction(
            @Param("longitude") double longitude,
            @Param("latitude") double latitude
    );

    @Query(value = """
            SELECT * FROM junctions
            WHERE ST_DWithin(
                location,
                ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)::geography,
                :radiusMeters
            )
            """, nativeQuery = true)
    List<Junction> findJunctionsWithinRadius(
            @Param("longitude") double longitude,
            @Param("latitude") double latitude,
            @Param("radiusMeters") double radiusMeters
    );
}