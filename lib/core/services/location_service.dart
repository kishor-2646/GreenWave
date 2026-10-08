import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../network/location_socket_service.dart';
import 'auth_service.dart';

class LocationService {
  final AuthService _authService;
  final LocationSocketService _socket = LocationSocketService();

  LocationService(this._authService);

  String? get userId => _authService.currentUser?.id;

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }

  // B1 sends position only. The emergency parameters are accepted so existing
  // callers compile, and B2 will start sending them. The backend takes the
  // user's role from the JWT, so `role` is unused here.
  Future<void> updateLiveLocation(
      Position position,
      String role, {
        bool isEmergency = false,
        double? destLat,
        double? destLng,
        String? encodedPolyline,
        List<String>? pathJunctions,
        String? nearestJunction,
        bool? isNearJunction,
        Map<String, String>? junctionEtas,
      }) async {
    try {
      await _socket.connect();

      _socket.sendLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
      );
    } catch (e) {
      debugPrint('Location send skipped: $e');
    }
  }

  Future<bool> handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) return false;

    LocationPermission permission =
    await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    return permission != LocationPermission.deniedForever;
  }

  void dispose() => _socket.disconnect();
}