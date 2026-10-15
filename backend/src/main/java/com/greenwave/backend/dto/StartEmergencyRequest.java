package com.greenwave.backend.dto;

import jakarta.validation.constraints.*;

public record StartEmergencyRequest(
        @NotNull @Min(1) @Max(5) Integer criticality,
        @NotNull @DecimalMin("-90.0") @DecimalMax("90.0") Double destinationLat,
        @NotNull @DecimalMin("-180.0") @DecimalMax("180.0") Double destinationLng,
        String encodedPolyline
) {}