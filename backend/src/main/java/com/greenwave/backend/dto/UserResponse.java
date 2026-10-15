
package com.greenwave.backend.dto;

import com.greenwave.backend.entity.Role;
import com.greenwave.backend.entity.User;

import java.util.UUID;

public record UserResponse(
        UUID id,
        String email,
        String fullName,
        Role role,
        boolean isVerified,
        String mobile,
        String hospital
) {
    // One place that converts a User entity into a response.
    public static UserResponse from(User user) {
        return new UserResponse(
                user.getId(),
                user.getEmail(),
                user.getFullName(),
                user.getRole(),
                user.isVerified(),
                user.getMobile(),
                user.getHospital()
        );
    }
}
