package com.greenwave.backend.repository;

import com.greenwave.backend.entity.EmergencySession;
import com.greenwave.backend.entity.EmergencyStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface EmergencySessionRepository extends JpaRepository<EmergencySession, UUID> {

    Optional<EmergencySession> findByAmbulanceUserIdAndStatus(
            UUID ambulanceUserId,
            EmergencyStatus status
    );

    List<EmergencySession> findByStatus(EmergencyStatus status);

    List<EmergencySession> findTop100ByOrderByStartedAtDesc();
}