package com.greenwave.backend.dto;

import com.greenwave.backend.entity.EmergencyStatus;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record EmergencyResponse(
        UUID id,
        UUID ambulanceUserId,
        String ambulanceName,
        int criticality,
        EmergencyStatus status,
        double destinationLat,
        double destinationLng,
        String encodedPolyline,
        Instant startedAt,
        Instant endedAt,
        List<ClearedJunction> clearedJunctions
) {

    public record ClearedJunction(
            UUID junctionId,
            String junctionName,
            double latitude,
            double longitude,
            UUID clearedByUserId,
            Instant clearedAt
    ) {}
}