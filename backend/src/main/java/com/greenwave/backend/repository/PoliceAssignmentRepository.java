package com.greenwave.backend.repository;

import com.greenwave.backend.entity.PoliceAssignment;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface PoliceAssignmentRepository
        extends JpaRepository<PoliceAssignment, UUID> {
}

