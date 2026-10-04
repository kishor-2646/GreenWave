package com.greenwave.backend.controller;

import com.greenwave.backend.dto.JunctionResponse;
import com.greenwave.backend.service.JunctionService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

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
}