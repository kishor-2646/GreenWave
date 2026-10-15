package com.greenwave.backend.dto;

import java.util.UUID;

public record JunctionResponse(
        UUID id,
        String name,
        double latitude,
        double longitude
) {
}