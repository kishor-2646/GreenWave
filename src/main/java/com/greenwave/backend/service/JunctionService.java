package com.greenwave.backend.service;

import com.greenwave.backend.dto.JunctionResponse;
import com.greenwave.backend.entity.Junction;
import com.greenwave.backend.repository.JunctionRepository;
import org.locationtech.jts.geom.Point;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@Service
public class JunctionService {

    private final JunctionRepository junctionRepository;

    public JunctionService(JunctionRepository junctionRepository) {
        this.junctionRepository = junctionRepository;
    }

    public JunctionResponse findNearest(double latitude, double longitude) {

        Junction junction = junctionRepository
                .findNearestJunction(longitude, latitude)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "No junctions exist yet"
                ));

        return toResponse(junction);
    }

    public List<JunctionResponse> findWithinRadius(
            double latitude,
            double longitude,
            double radiusMeters) {

        return junctionRepository
                .findJunctionsWithinRadius(
                        longitude,
                        latitude,
                        radiusMeters
                )
                .stream()
                .map(this::toResponse)
                .toList();
    }

    private JunctionResponse toResponse(Junction junction) {

        Point location = junction.getLocation();

        return new JunctionResponse(
                junction.getId(),
                junction.getName(),
                location.getY(),
                location.getX()
        );
    }
}