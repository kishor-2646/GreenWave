package com.greenwave.backend.repository;

import com.greenwave.backend.entity.JunctionClearance;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface JunctionClearanceRepository extends JpaRepository<JunctionClearance, UUID> {

    List<JunctionClearance> findByEmergencySessionIdIn(Collection<UUID> sessionIds);

    Optional<JunctionClearance> findByEmergencySessionIdAndJunctionId(
            UUID sessionId,
            UUID junctionId
    );
}