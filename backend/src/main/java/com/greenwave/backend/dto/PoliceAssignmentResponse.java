package com.greenwave.backend.dto;

import java.util.UUID;

public record PoliceAssignmentResponse(
        UUID userId,
        String officerName,
        UUID junctionId,
        String junctionName,
        double latitude,
        double longitude
) {}