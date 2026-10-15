package com.greenwave.backend.controller;

import com.greenwave.backend.dto.LocationBroadcast;
import com.greenwave.backend.entity.Role;
import com.greenwave.backend.service.LocationService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;

import java.util.List;

@RestController
@SecurityRequirement(name = "bearerAuth")
@RequestMapping("/api/locations")
public class LocationRestController {

    private final LocationService locationService;

    public LocationRestController(LocationService locationService) {
        this.locationService = locationService;
    }

    @GetMapping("/ambulances")
    public List<LocationBroadcast> ambulances() {
        return locationService.getLocationsByRole(Role.AMBULANCE_DRIVER);
    }

    @GetMapping("/police")
    public List<LocationBroadcast> police() {
        return locationService.getLocationsByRole(Role.POLICE);
    }
}