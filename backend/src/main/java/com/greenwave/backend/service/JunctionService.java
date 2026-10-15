package com.greenwave.backend.service;

import com.greenwave.backend.dto.JunctionResponse;
import com.greenwave.backend.entity.Junction;
import com.greenwave.backend.repository.JunctionRepository;
import org.locationtech.jts.geom.Point;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import com.greenwave.backend.dto.CreateJunctionRequest;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.PrecisionModel;

import java.util.List;

@Service
public class JunctionService {

    private static final GeometryFactory GEOMETRY_FACTORY =
            new GeometryFactory(new PrecisionModel(), 4326);

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

    public JunctionResponse createJunction(CreateJunctionRequest request) {

        Point location = GEOMETRY_FACTORY.createPoint(
                new Coordinate(request.longitude(), request.latitude())
        );

        Junction junction = Junction.builder()
                .name(request.name())
                .location(location)
                .build();

        Junction saved = junctionRepository.save(junction);
        return toResponse(saved);
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


    public List<JunctionResponse> findAll() {
        return junctionRepository.findAll()
                .stream()
                .map(this::toResponse)
                .toList();
    }
}