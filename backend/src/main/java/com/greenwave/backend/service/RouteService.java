
package com.greenwave.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.Map;

@Service
public class RouteService {

    private final RestClient restClient;
    private final ObjectMapper objectMapper;
    private final String apiKey;

    public RouteService(
            @Value("${google.maps.routes.api-key}") String apiKey) {
        this.restClient = RestClient.create();
        this.objectMapper = new ObjectMapper();
        this.apiKey = apiKey;
    }

    public String getEncodedPolyline(
            double originLat,
            double originLng,
            double destinationLat,
            double destinationLng) {

        Map<String, Object> requestBody = Map.of(
                "origin", Map.of(
                        "location", Map.of(
                                "latLng", Map.of(
                                        "latitude", originLat,
                                        "longitude", originLng
                                )
                        )
                ),
                "destination", Map.of(
                        "location", Map.of(
                                "latLng", Map.of(
                                        "latitude", destinationLat,
                                        "longitude", destinationLng
                                )
                        )
                ),
                "travelMode", "DRIVE"
        );

        String response = restClient.post()
                .uri("https://routes.googleapis.com/directions/v2:computeRoutes")
                .header("X-Goog-Api-Key", apiKey)
                .header("X-Goog-FieldMask", "routes.polyline.encodedPolyline")
                .contentType(MediaType.APPLICATION_JSON)
                .body(requestBody)
                .retrieve()
                .body(String.class);

        try {
            JsonNode root = objectMapper.readTree(response);
            JsonNode polyline =
                    root.path("routes").path(0).path("polyline").path("encodedPolyline");

            if (polyline.isMissingNode() || polyline.asText().isBlank()) {
                throw new IllegalStateException(
                        "Google Routes API returned no encoded polyline");
            }

            return polyline.asText();
        } catch (Exception e) {
            if (e instanceof IllegalStateException illegalStateException) {
                throw illegalStateException;
            }
            throw new IllegalStateException(
                    "Failed to parse Google Routes API response", e);
        }
    }
}
