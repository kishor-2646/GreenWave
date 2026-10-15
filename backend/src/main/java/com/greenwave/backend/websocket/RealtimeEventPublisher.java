package com.greenwave.backend.websocket;

import com.greenwave.backend.dto.EmergencyEvent;
import com.greenwave.backend.dto.PoliceAssignmentResponse;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Component
public class RealtimeEventPublisher {

    private final SimpMessagingTemplate messagingTemplate;

    public RealtimeEventPublisher(
            SimpMessagingTemplate messagingTemplate
    ) {
        this.messagingTemplate = messagingTemplate;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onEmergencyEvent(EmergencyEvent event) {
        messagingTemplate.convertAndSend(
                "/topic/emergencies",
                event
        );
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onPoliceAssignment(
            PoliceAssignmentResponse assignment
    ) {
        messagingTemplate.convertAndSend(
                "/topic/police-assignments",
                assignment
        );
    }
}