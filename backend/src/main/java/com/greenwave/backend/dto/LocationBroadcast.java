package com.greenwave.backend.dto;

import com.greenwave.backend.entity.Role;

import java.time.Instant;
import java.util.UUID;

public record LocationBroadcast(
        UUID userId,
        String fullName,
        Role role,
        double latitude,
        double longitude,
        Double heading,
        Instant updatedAt
) {}