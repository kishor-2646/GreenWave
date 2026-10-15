
package com.greenwave.backend.controller;

import com.greenwave.backend.dto.RouteResponse;
import com.greenwave.backend.service.RouteService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/routes")
public class RouteController {

    private final RouteService routeService;

    public RouteController(RouteService routeService) {
        this.routeService = routeService;
    }

    @GetMapping
    public RouteResponse getRoute(
            @RequestParam double originLat,
            @RequestParam double originLng,
            @RequestParam double destinationLat,
            @RequestParam double destinationLng) {

        String encodedPolyline = routeService.getEncodedPolyline(
                originLat,
                originLng,
                destinationLat,
                destinationLng
        );

        return new RouteResponse(encodedPolyline);
    }
}
