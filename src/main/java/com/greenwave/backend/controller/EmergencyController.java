package com.greenwave.backend.controller;

import com.greenwave.backend.dto.EmergencyResponse;
import com.greenwave.backend.dto.StartEmergencyRequest;
import com.greenwave.backend.entity.User;
import com.greenwave.backend.service.EmergencyService;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/emergencies")
@SecurityRequirement(name = "bearerAuth")
public class EmergencyController {

    private final EmergencyService emergencyService;

    public EmergencyController(EmergencyService emergencyService) {
        this.emergencyService = emergencyService;
    }

    @PreAuthorize("hasRole('AMBULANCE_DRIVER')")
    @PostMapping
    public ResponseEntity<EmergencyResponse> start(
            @AuthenticationPrincipal User user,
            @Valid @RequestBody StartEmergencyRequest request
    ) {
        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(emergencyService.start(user, request));
    }

    @PreAuthorize("hasRole('AMBULANCE_DRIVER')")
    @PostMapping("/{id}/end")
    public EmergencyResponse end(
            @AuthenticationPrincipal User user,
            @PathVariable UUID id
    ) {
        return emergencyService.end(user, id);
    }

    @GetMapping("/active")
    public List<EmergencyResponse> active() {
        return emergencyService.getActive();
    }

    @PreAuthorize("hasRole('AMBULANCE_DRIVER')")
    @GetMapping("/active/mine")
    public ResponseEntity<EmergencyResponse> activeMine(
            @AuthenticationPrincipal User user
    ) {
        return emergencyService.getActiveFor(user)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping
    public List<EmergencyResponse> history() {
        return emergencyService.getHistory();
    }

    @PreAuthorize("hasRole('POLICE')")
    @PutMapping("/{id}/clearances/{junctionId}")
    public EmergencyResponse clear(
            @AuthenticationPrincipal User user,
            @PathVariable UUID id,
            @PathVariable UUID junctionId
    ) {
        return emergencyService.markCleared(user, id, junctionId);
    }

    @PreAuthorize("hasRole('POLICE')")
    @DeleteMapping("/{id}/clearances/{junctionId}")
    public EmergencyResponse revert(
            @AuthenticationPrincipal User user,
            @PathVariable UUID id,
            @PathVariable UUID junctionId
    ) {
        return emergencyService.revertClearance(user, id, junctionId);
    }
}