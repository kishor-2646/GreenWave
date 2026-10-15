package com.greenwave.backend.controller;

import com.greenwave.backend.dto.JunctionResponse;
import com.greenwave.backend.service.JunctionService;
import org.springframework.web.bind.annotation.*;
import com.greenwave.backend.dto.CreateJunctionRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;

import java.util.List;

@RestController
@RequestMapping("/api/junctions")
public class JunctionController {

    private final JunctionService junctionService;

    public JunctionController(JunctionService junctionService) {
        this.junctionService = junctionService;
    }

    @GetMapping("/nearest")
    public JunctionResponse nearest(
            @RequestParam double lat,
            @RequestParam double lng) {

        return junctionService.findNearest(lat, lng);
    }

    @GetMapping("/nearby")
    public List<JunctionResponse> nearby(
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "1000") double radiusMeters) {

        return junctionService.findWithinRadius(
                lat,
                lng,
                radiusMeters
        );
    }

    @PreAuthorize("hasRole('ADMIN')")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping
    public ResponseEntity<JunctionResponse> create(
            @Valid @RequestBody CreateJunctionRequest request) {

        JunctionResponse response = junctionService.createJunction(request);

        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(response);
    }


    @GetMapping
    public List<JunctionResponse> all() {
        return junctionService.findAll();
    }

}