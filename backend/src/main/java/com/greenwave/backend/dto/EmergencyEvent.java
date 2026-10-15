package com.greenwave.backend.dto;

public record EmergencyEvent(
        EmergencyEventType type,
        EmergencyResponse emergency
) {}