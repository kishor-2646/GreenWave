package com.greenwave.backend.service;

import com.greenwave.backend.dto.LocationBroadcast;
import com.greenwave.backend.dto.LocationUpdateMessage;
import com.greenwave.backend.entity.Role;
import com.greenwave.backend.entity.User;
import com.greenwave.backend.entity.UserLocation;
import com.greenwave.backend.repository.UserLocationRepository;
import com.greenwave.backend.repository.UserRepository;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.Point;
import org.locationtech.jts.geom.PrecisionModel;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class LocationService {

    private static final GeometryFactory GEOMETRY_FACTORY =
            new GeometryFactory(new PrecisionModel(), 4326);

    private final UserLocationRepository userLocationRepository;
    private final UserRepository userRepository;
    private final SimpMessagingTemplate messagingTemplate;

    public LocationService(UserLocationRepository userLocationRepository,
                           UserRepository userRepository,
                           SimpMessagingTemplate messagingTemplate) {
        this.userLocationRepository = userLocationRepository;
        this.userRepository = userRepository;
        this.messagingTemplate = messagingTemplate;
    }

    public void recordAndBroadcast(User user, LocationUpdateMessage message) {

        if (message.latitude() == null || message.longitude() == null) {
            return;
        }

        Point point = GEOMETRY_FACTORY.createPoint(
                new Coordinate(message.longitude(), message.latitude())
        );

        UserLocation location = userLocationRepository.findById(user.getId())
                .orElseGet(() -> UserLocation.builder().userId(user.getId()).build());

        location.setLocation(point);
        location.setHeading(message.heading());
        location.setUpdatedAt(Instant.now());
        userLocationRepository.save(location);

        LocationBroadcast broadcast = new LocationBroadcast(
                user.getId(),
                user.getFullName(),
                user.getRole(),
                message.latitude(),
                message.longitude(),
                message.heading(),
                location.getUpdatedAt()
        );

        String topic = user.getRole() == Role.POLICE
                ? "/topic/police-updates"
                : "/topic/ambulance-updates";

        messagingTemplate.convertAndSend(topic, broadcast);
    }

    public List<LocationBroadcast> getLocationsByRole(Role role) {

        List<UserLocation> locations =
                userLocationRepository.findByUserRole(role.name());

        Map<java.util.UUID, User> usersById = userRepository
                .findAllById(
                        locations.stream()
                                .map(UserLocation::getUserId)
                                .toList()
                )
                .stream()
                .collect(Collectors.toMap(User::getId, u -> u));

        return locations.stream()
                .map(loc -> {
                    User u = usersById.get(loc.getUserId());

                    return new LocationBroadcast(
                            u.getId(),
                            u.getFullName(),
                            u.getRole(),
                            loc.getLocation().getY(),
                            loc.getLocation().getX(),
                            loc.getHeading(),
                            loc.getUpdatedAt()
                    );
                })
                .toList();
    }
}