package com.greenwave.backend.service;

import com.greenwave.backend.dto.EmergencyEvent;
import com.greenwave.backend.dto.EmergencyEventType;
import com.greenwave.backend.dto.EmergencyResponse;
import com.greenwave.backend.dto.StartEmergencyRequest;
import com.greenwave.backend.entity.EmergencySession;
import com.greenwave.backend.entity.EmergencyStatus;
import com.greenwave.backend.entity.Junction;
import com.greenwave.backend.entity.JunctionClearance;
import com.greenwave.backend.entity.PoliceAssignment;
import com.greenwave.backend.entity.User;
import com.greenwave.backend.repository.EmergencySessionRepository;
import com.greenwave.backend.repository.JunctionClearanceRepository;
import com.greenwave.backend.repository.JunctionRepository;
import com.greenwave.backend.repository.PoliceAssignmentRepository;
import com.greenwave.backend.repository.UserRepository;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.Point;
import org.locationtech.jts.geom.PrecisionModel;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;


import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class EmergencyService {

    private static final GeometryFactory GEOMETRY_FACTORY =
            new GeometryFactory(new PrecisionModel(), 4326);

    private final EmergencySessionRepository sessionRepository;
    private final JunctionClearanceRepository clearanceRepository;
    private final PoliceAssignmentRepository assignmentRepository;
    private final JunctionRepository junctionRepository;
    private final UserRepository userRepository;
    private final ApplicationEventPublisher eventPublisher;

    public EmergencyService(
            EmergencySessionRepository sessionRepository,
            JunctionClearanceRepository clearanceRepository,
            PoliceAssignmentRepository assignmentRepository,
            JunctionRepository junctionRepository,
            UserRepository userRepository,
            ApplicationEventPublisher eventPublisher
    ) {
        this.sessionRepository = sessionRepository;
        this.clearanceRepository = clearanceRepository;
        this.assignmentRepository = assignmentRepository;
        this.junctionRepository = junctionRepository;
        this.userRepository = userRepository;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public EmergencyResponse start(
            User ambulance,
            StartEmergencyRequest request
    ) {
        sessionRepository
                .findByAmbulanceUserIdAndStatus(
                        ambulance.getId(),
                        EmergencyStatus.ACTIVE
                )
                .ifPresent(s -> {
                    throw new ResponseStatusException(
                            HttpStatus.CONFLICT,
                            "An emergency is already active"
                    );
                });

        Point destination = GEOMETRY_FACTORY.createPoint(
                new Coordinate(
                        request.destinationLng(),
                        request.destinationLat()
                )
        );

        EmergencySession session =
                sessionRepository.save(
                        EmergencySession.builder()
                                .ambulanceUserId(ambulance.getId())
                                .criticality(request.criticality())
                                .status(EmergencyStatus.ACTIVE)
                                .destination(destination)
                                .encodedPolyline(request.encodedPolyline())
                                .startedAt(Instant.now())
                                .build()
                );

        EmergencyResponse response = toResponse(session);

        eventPublisher.publishEvent(
                new EmergencyEvent(
                        EmergencyEventType.STARTED,
                        response
                )
        );

        return response;
    }

    @Transactional
    public EmergencyResponse end(
            User ambulance,
            UUID emergencyId
    ) {
        EmergencySession session = find(emergencyId);

        if (!session.getAmbulanceUserId().equals(ambulance.getId())) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN,
                    "Not your emergency"
            );
        }

        if (session.getStatus() == EmergencyStatus.ENDED) {
            return toResponse(session);
        }

        session.setStatus(EmergencyStatus.ENDED);
        session.setEndedAt(Instant.now());

        sessionRepository.save(session);

        EmergencyResponse response = toResponse(session);

        eventPublisher.publishEvent(
                new EmergencyEvent(
                        EmergencyEventType.ENDED,
                        response
                )
        );

        return response;
    }

    @Transactional
    public EmergencyResponse markCleared(
            User police,
            UUID emergencyId,
            UUID junctionId
    ) {
        EmergencySession session = findActive(emergencyId);

        requireAssignedTo(police, junctionId);

        if (clearanceRepository
                .findByEmergencySessionIdAndJunctionId(
                        emergencyId,
                        junctionId
                )
                .isPresent()) {

            return toResponse(session);
        }

        clearanceRepository.save(
                JunctionClearance.builder()
                        .emergencySessionId(emergencyId)
                        .junctionId(junctionId)
                        .clearedByUserId(police.getId())
                        .clearedAt(Instant.now())
                        .build()
        );

        EmergencyResponse response = toResponse(session);

        eventPublisher.publishEvent(
                new EmergencyEvent(
                        EmergencyEventType.JUNCTION_CLEARED,
                        response
                )
        );

        return response;
    }

    @Transactional
    public EmergencyResponse revertClearance(
            User police,
            UUID emergencyId,
            UUID junctionId
    ) {
        EmergencySession session = findActive(emergencyId);

        requireAssignedTo(police, junctionId);

        Optional<JunctionClearance> existing =
                clearanceRepository.findByEmergencySessionIdAndJunctionId(
                        emergencyId,
                        junctionId
                );

        if (existing.isEmpty()) {
            return toResponse(session);
        }

        clearanceRepository.delete(existing.get());

        EmergencyResponse response = toResponse(session);

        eventPublisher.publishEvent(
                new EmergencyEvent(
                        EmergencyEventType.CLEARANCE_REVERTED,
                        response
                )
        );

        return response;
    }

    @Transactional(readOnly = true)
    public List<EmergencyResponse> getActive() {
        return toResponses(
                sessionRepository.findByStatus(
                        EmergencyStatus.ACTIVE
                )
        );
    }

    @Transactional(readOnly = true)
    public Optional<EmergencyResponse> getActiveFor(
            User ambulance
    ) {
        return sessionRepository
                .findByAmbulanceUserIdAndStatus(
                        ambulance.getId(),
                        EmergencyStatus.ACTIVE
                )
                .map(this::toResponse);
    }

    @Transactional(readOnly = true)
    public List<EmergencyResponse> getHistory() {
        return toResponses(
                sessionRepository.findTop100ByOrderByStartedAtDesc()
        );
    }

    // ---------- helpers ----------

    private EmergencySession find(UUID id) {
        return sessionRepository
                .findById(id)
                .orElseThrow(() ->
                        new ResponseStatusException(
                                HttpStatus.NOT_FOUND,
                                "Emergency not found"
                        )
                );
    }

    private EmergencySession findActive(UUID id) {
        EmergencySession session = find(id);

        if (session.getStatus() != EmergencyStatus.ACTIVE) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "Emergency already ended"
            );
        }

        return session;
    }

    private void requireAssignedTo(
            User police,
            UUID junctionId
    ) {
        PoliceAssignment assignment =
                assignmentRepository
                        .findById(police.getId())
                        .orElseThrow(() ->
                                new ResponseStatusException(
                                        HttpStatus.FORBIDDEN,
                                        "You have no assigned junction"
                                )
                        );

        if (!assignment.getJunctionId().equals(junctionId)) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN,
                    "You can only clear your assigned junction"
            );
        }
    }

    private EmergencyResponse toResponse(
            EmergencySession session
    ) {
        return toResponses(List.of(session)).get(0);
    }

    private List<EmergencyResponse> toResponses(
            List<EmergencySession> sessions
    ) {
        if (sessions.isEmpty()) {
            return List.of();
        }

        List<UUID> sessionIds =
                sessions.stream()
                        .map(EmergencySession::getId)
                        .toList();

        List<JunctionClearance> clearances =
                clearanceRepository
                        .findByEmergencySessionIdIn(sessionIds);

        Map<UUID, User> users =
                userRepository
                        .findAllById(
                                sessions.stream()
                                        .map(EmergencySession::getAmbulanceUserId)
                                        .distinct()
                                        .toList()
                        )
                        .stream()
                        .collect(
                                Collectors.toMap(
                                        User::getId,
                                        u -> u
                                )
                        );

        Map<UUID, Junction> junctions =
                junctionRepository
                        .findAllById(
                                clearances.stream()
                                        .map(JunctionClearance::getJunctionId)
                                        .distinct()
                                        .toList()
                        )
                        .stream()
                        .collect(
                                Collectors.toMap(
                                        Junction::getId,
                                        j -> j
                                )
                        );

        Map<UUID, List<JunctionClearance>> clearancesBySession =
                clearances.stream()
                        .collect(
                                Collectors.groupingBy(
                                        JunctionClearance::getEmergencySessionId
                                )
                        );

        return sessions.stream()
                .map(s -> {

                    List<EmergencyResponse.ClearedJunction> cleared =
                            clearancesBySession
                                    .getOrDefault(
                                            s.getId(),
                                            List.of()
                                    )
                                    .stream()
                                    .map(c -> {
                                        Junction j =
                                                junctions.get(
                                                        c.getJunctionId()
                                                );

                                        return new EmergencyResponse.ClearedJunction(
                                                j.getId(),
                                                j.getName(),
                                                j.getLocation().getY(),
                                                j.getLocation().getX(),
                                                c.getClearedByUserId(),
                                                c.getClearedAt()
                                        );
                                    })
                                    .toList();

                    User ambulance =
                            users.get(s.getAmbulanceUserId());

                    return new EmergencyResponse(
                            s.getId(),
                            s.getAmbulanceUserId(),
                            ambulance != null
                                    ? ambulance.getFullName()
                                    : "Unknown",
                            s.getCriticality(),
                            s.getStatus(),
                            s.getDestination().getY(),
                            s.getDestination().getX(),
                            s.getEncodedPolyline(),
                            s.getStartedAt(),
                            s.getEndedAt(),
                            cleared
                    );
                })
                .toList();
    }
}