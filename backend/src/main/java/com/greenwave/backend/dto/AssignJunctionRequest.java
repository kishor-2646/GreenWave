package com.greenwave.backend.dto;

import jakarta.validation.constraints.NotNull;

import java.util.UUID;

public record AssignJunctionRequest(
        @NotNull UUID junctionId
) {}