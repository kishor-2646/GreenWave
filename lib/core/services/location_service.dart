import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Start tracking and pushing to Firestore
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters to save battery/data
      ),
    );
  }

  // Update Firestore with current location
  Future<void> updateLiveLocation(Position position, String role) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Directing data to the correct collection based on user role
    final collection = role == "Ambulance Driver"
        ? 'ambulanceLocations'
        : 'policeLocations';

    await _db.collection('artifacts').doc('greenwave').collection('public').doc('data').collection(collection).doc(user.uid).set({
      'uid': user.uid,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'heading': position.heading,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'active',
    }, SetOptions(merge: true));
  }

  // Check and Request GPS Permissions
  Future<bool> handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }
}