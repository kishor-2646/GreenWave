package com.greenwave.backend.dto;

public record LocationUpdateMessage(
        Double latitude,
        Double longitude,
        Double heading
) {}