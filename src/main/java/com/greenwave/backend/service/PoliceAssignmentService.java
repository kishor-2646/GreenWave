package com.greenwave.backend.service;

import com.greenwave.backend.dto.PoliceAssignmentResponse;
import com.greenwave.backend.entity.Junction;
import com.greenwave.backend.entity.PoliceAssignment;
import com.greenwave.backend.entity.User;
import com.greenwave.backend.repository.JunctionRepository;
import com.greenwave.backend.repository.PoliceAssignmentRepository;
import com.greenwave.backend.repository.UserRepository;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class PoliceAssignmentService {

    private final PoliceAssignmentRepository assignmentRepository;
    private final JunctionRepository junctionRepository;
    private final UserRepository userRepository;
    private final ApplicationEventPublisher eventPublisher;

    public PoliceAssignmentService(
            PoliceAssignmentRepository assignmentRepository,
            JunctionRepository junctionRepository,
            UserRepository userRepository,
            ApplicationEventPublisher eventPublisher
    ) {
        this.assignmentRepository = assignmentRepository;
        this.junctionRepository = junctionRepository;
        this.userRepository = userRepository;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public PoliceAssignmentResponse assign(User police, UUID junctionId) {
        Junction junction = junctionRepository.findById(junctionId)
                .orElseThrow(() ->
                        new ResponseStatusException(
                                HttpStatus.NOT_FOUND,
                                "Junction not found"
                        )
                );

        PoliceAssignment assignment = assignmentRepository.findById(police.getId())
                .orElseGet(() ->
                        PoliceAssignment.builder()
                                .userId(police.getId())
                                .build()
                );

        assignment.setJunctionId(junctionId);
        assignment.setUpdatedAt(Instant.now());

        assignmentRepository.save(assignment);

        PoliceAssignmentResponse response = toResponse(police, junction);

        eventPublisher.publishEvent(response);

        return response;
    }

    @Transactional(readOnly = true)
    public List<PoliceAssignmentResponse> listAll() {
        List<PoliceAssignment> all = assignmentRepository.findAll();

        Map<UUID, User> users = userRepository
                .findAllById(
                        all.stream()
                                .map(PoliceAssignment::getUserId)
                                .toList()
                )
                .stream()
                .collect(
                        Collectors.toMap(
                                User::getId,
                                u -> u
                        )
                );

        Map<UUID, Junction> junctions = junctionRepository
                .findAllById(
                        all.stream()
                                .map(PoliceAssignment::getJunctionId)
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

        return all.stream()
                .map(a ->
                        toResponse(
                                users.get(a.getUserId()),
                                junctions.get(a.getJunctionId())
                        )
                )
                .toList();
    }

    private PoliceAssignmentResponse toResponse(
            User officer,
            Junction junction
    ) {
        return new PoliceAssignmentResponse(
                officer.getId(),
                officer.getFullName(),
                junction.getId(),
                junction.getName(),
                junction.getLocation().getY(),
                junction.getLocation().getX()
        );
    }
}