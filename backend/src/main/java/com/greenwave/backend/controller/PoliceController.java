package com.greenwave.backend.controller;

import com.greenwave.backend.dto.AssignJunctionRequest;
import com.greenwave.backend.dto.PoliceAssignmentResponse;
import com.greenwave.backend.entity.User;
import com.greenwave.backend.service.PoliceAssignmentService;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/police")
@SecurityRequirement(name = "bearerAuth")
public class PoliceController {

    private final PoliceAssignmentService assignmentService;

    public PoliceController(PoliceAssignmentService assignmentService) {
        this.assignmentService = assignmentService;
    }

    @PreAuthorize("hasRole('POLICE')")
    @PutMapping("/assignment")
    public PoliceAssignmentResponse assign(
            @AuthenticationPrincipal User user,
            @Valid @RequestBody AssignJunctionRequest request
    ) {
        return assignmentService.assign(
                user,
                request.junctionId()
        );
    }

    @GetMapping("/assignments")
    public List<PoliceAssignmentResponse> list() {
        return assignmentService.listAll();
    }
}