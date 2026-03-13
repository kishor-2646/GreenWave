import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }

  Future<void> updateLiveLocation(
      Position position,
      String role,
      {
        bool isEmergency = false,
        double? destLat,
        double? destLng,
        String? encodedPolyline,
        List<String>? pathJunctions,
        String? nearestJunction,
        bool? isNearJunction,
      }
      ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final collectionName = role == "Ambulance Driver" ? 'ambulanceLocations' : 'policeLocations';

    final Map<String, dynamic> data = {
      'uid': user.uid,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'heading': position.heading,
      'timestamp': FieldValue.serverTimestamp(),
      'status': isEmergency ? 'emergency' : 'active',
    };

    if (isEmergency) {
      if (destLat != null) data['destLat'] = destLat;
      if (destLng != null) data['destLng'] = destLng;
      if (encodedPolyline != null) data['encodedPolyline'] = encodedPolyline;
      if (pathJunctions != null) data['pathJunctions'] = pathJunctions;
      if (nearestJunction != null) data['nearestJunction'] = nearestJunction;
      if (isNearJunction != null) data['isNearJunction'] = isNearJunction;
    }

    await _db.collection(collectionName).doc(user.uid).set(data, SetOptions(merge: true));
  }

  Future<bool> handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    return permission != LocationPermission.deniedForever;
  }
}