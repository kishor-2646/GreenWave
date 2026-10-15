
package com.greenwave.backend.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record UpdateProfileRequest(
        @NotBlank @Size(max = 100) String fullName,
        @Size(max = 20) String mobile,
        @Size(max = 150) String hospital
) {}
