import 'package:geolocator/geolocator.dart';

import '../network/realtime_service.dart';

class LocationService {
  final RealtimeService _realtime;

  LocationService(this._realtime);

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }

  /// Sends this GPS fix over the shared socket.
  void sendPosition(Position position) {
    _realtime.sendLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      heading: position.heading,
    );
  }

  Future<bool> handleLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    return permission != LocationPermission.deniedForever;
  }

// No dispose(): RealtimeService owns the shared socket.
}