package com.greenwave.backend.websocket;

import com.greenwave.backend.dto.LocationUpdateMessage;
import com.greenwave.backend.entity.User;
import com.greenwave.backend.service.LocationService;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.stereotype.Controller;

@Controller
public class LocationController {

    private final LocationService locationService;

    public LocationController(LocationService locationService) {
        this.locationService = locationService;
    }

    @MessageMapping("/location.update")
    public void updateLocation(
            @Payload LocationUpdateMessage message,
            SimpMessageHeaderAccessor headerAccessor) {

        User user = (User) headerAccessor
                .getSessionAttributes()
                .get("user");

        locationService.recordAndBroadcast(user, message);
    }
}