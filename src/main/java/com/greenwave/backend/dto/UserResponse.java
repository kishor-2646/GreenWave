package com.greenwave.backend.dto;

import com.greenwave.backend.entity.Role;

import java.util.UUID;

public record UserResponse(
        UUID id,
        String email,
        String fullName,
        Role role,
        boolean isVerified
) {
}