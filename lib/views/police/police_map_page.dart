import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';

class PoliceMapPage extends StatefulWidget {
  const PoliceMapPage({super.key});

  @override
  State<PoliceMapPage> createState() => _PoliceMapPageState();
}

class _PoliceMapPageState extends State<PoliceMapPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  GoogleMapController? _mapController;
  LatLng _myLocation = const LatLng(12.9716, 77.5946);

  // Theme Colors
  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color darkCard = Color(0xFF282828);
  static const Color bgBlack = Color(0xFF121212);

  // TESTING: Static Junction Data with Coordinates
  final Map<String, LatLng> _junctionData = {
    "Koramangala 5th Block Junction": const LatLng(12.9352, 77.6245),
    "Silk Board Signal": const LatLng(12.9176, 77.6233),
    "HSR Layout 27th Main": const LatLng(12.9128, 77.6387),
    "Dairy Circle Flyover": const LatLng(12.9427, 77.5997),
    "Agara Junction": const LatLng(12.9231, 77.6515),
    "Sapthagiri Junction": const LatLng(13.0645, 77.4985),
    "Chimney Hill Junction": const LatLng(13.0598, 77.4952),
  };

  String? _myAssignedJunction;
  LatLng? _junctionLocation;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initPoliceData();
  }

  void _initPoliceData() async {
    Position pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
    }

    Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() => _myLocation = LatLng(position.latitude, position.longitude));
      }
    });
  }

  void _updateDutyJunction(String junctionName) {
    final location = _junctionData[junctionName];
    setState(() {
      _myAssignedJunction = junctionName;
      _junctionLocation = location;
    });

    final uid = Provider.of<AuthService>(context, listen: false).currentUser?.uid;
    if (uid != null) {
      _db.collection('policeLocations').doc(uid).set({
        'assignedJunction': junctionName,
        'junctionLat': location?.latitude,
        'junctionLng': location?.longitude,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (_mapController != null && location != null) {
      _fitMapToPoints([_myLocation, location]);
    }
  }

  void _fitMapToPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 80));
  }

  void _recenterToMyLocation() {
    _mapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: _myLocation, zoom: 16)));
  }

  // --- NEW COORDINATE COLLISION LOGIC ---

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0; result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  /// Checks if any part of the path (decoded polyline) passes within [radiusMeters] of the junction.
  bool _isPathCollidingWithJunction(String? encodedPolyline, LatLng? junctionLoc) {
    if (encodedPolyline == null || junctionLoc == null) return false;

    final List<LatLng> pathPoints = _decodePolyline(encodedPolyline);

    for (var point in pathPoints) {
      double distance = Geolocator.distanceBetween(
          point.latitude, point.longitude,
          junctionLoc.latitude, junctionLoc.longitude
      );
      // Collision threshold: 300 meters
      if (distance < 300) return true;
    }
    return false;
  }

  // Smarter Keyword Matching Logic (Backup)
  bool _isJunctionNameOnPath(List pathJunctions, String? myJunction) {
    if (myJunction == null) return false;
    String normalizedMine = myJunction.toLowerCase();
    final stopWords = {'signal', 'junction', 'circle', 'flyover', 'road', 'rd', 'main', 'block', 'onto', 'at'};
    List<String> myKeywords = normalizedMine.split(' ').where((w) => w.length > 2 && !stopWords.contains(w)).toList();

    return pathJunctions.any((pathPoint) {
      String point = pathPoint.toString().toLowerCase();
      if (point.contains(normalizedMine)) return true;
      if (myKeywords.isNotEmpty && myKeywords.every((k) => point.contains(k))) return true;
      return false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Police Control Portal', style: TextStyle(fontSize: 18)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_input_component, color: spotifyGreen),
            onSelected: _updateDutyJunction,
            itemBuilder: (context) => _junctionData.keys.map((j) => PopupMenuItem(value: j, child: Text(j, style: const TextStyle(fontSize: 12)))).toList(),
          )
        ],
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'ALERTS'), Tab(text: 'MAP')], indicatorColor: spotifyGreen, labelColor: spotifyGreen),
      ),
      body: Column(
        children: [
          _buildDutyHeader(),
          Expanded(child: TabBarView(controller: _tabController, children: [_buildAlertsList(), _buildMap()])),
        ],
      ),
    );
  }

  Widget _buildDutyHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: Colors.white10,
      child: Row(
        children: [
          Icon(Icons.location_on, size: 14, color: _myAssignedJunction == null ? Colors.orange : spotifyGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(_myAssignedJunction == null ? "NO JUNCTION ASSIGNED" : "DUTY AT: $_myAssignedJunction", style: TextStyle(color: _myAssignedJunction == null ? Colors.orange : Colors.green, fontSize: 12, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('ambulanceLocations').where('status', isEqualTo: 'emergency').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: spotifyGreen));

        final relevantDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // PRIMARY: Check Physical Coordinate Collision with the Path
          bool pathCollision = _isPathCollidingWithJunction(data['encodedPolyline'], _junctionLocation);

          // SECONDARY: Check Current Proximity (Safety net: 1.5km radius)
          bool currentProximity = false;
          if (_junctionLocation != null) {
            double distance = Geolocator.distanceBetween(
                data['latitude'], data['longitude'],
                _junctionLocation!.latitude, _junctionLocation!.longitude
            );
            if (distance < 1500) currentProximity = true;
          }

          // BACKUP: Text-Based Path Matching
          bool textMatch = _isJunctionNameOnPath(data['pathJunctions'] ?? [], _myAssignedJunction);

          return pathCollision || currentProximity || textMatch;
        }).toList();

        if (relevantDocs.isEmpty) {
          return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.shield_outlined, size: 60, color: Colors.white10),
              SizedBox(height: 10),
              Text("No active emergencies on your path", style: TextStyle(color: Colors.white30)),
            ],
          ));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: relevantDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;

            // Proximity alert: Ambulance is within 500m of the junction
            bool isNear = false;
            if (_junctionLocation != null) {
              double distance = Geolocator.distanceBetween(
                  data['latitude'], data['longitude'],
                  _junctionLocation!.latitude, _junctionLocation!.longitude
              );
              if (distance < 500) isNear = true;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isNear ? Colors.red.withOpacity(0.3) : darkCard,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: isNear ? Colors.red : Colors.white10, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_hospital, color: isNear ? Colors.white : Colors.red),
                      const SizedBox(width: 10),
                      const Expanded(child: Text("INCOMING AMBULANCE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      if (isNear) const Icon(Icons.warning, color: Colors.white, size: 18),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 20),
                  if (isNear)
                    const Padding(padding: EdgeInsets.only(bottom: 12), child: Text("🚨 CLEAR SIGNAL - WITHIN 500m", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        _tabController.animateTo(1);
                        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(data['latitude'], data['longitude']), 17));
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: isNear ? Colors.white : spotifyGreen, foregroundColor: Colors.black),
                      child: const Text("LOCATE ON MAP"),
                    ),
                  )
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
            stream: _db.collection('ambulanceLocations').where('status', isEqualTo: 'emergency').snapshots(),
            builder: (context, snapshot) {
              Set<Marker> markers = {
                Marker(
                    markerId: const MarkerId("police_me"),
                    position: _myLocation,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                    infoWindow: const InfoWindow(title: "Your Location")
                )
              };
              Set<Polyline> polylines = {};

              if (_junctionLocation != null) {
                markers.add(Marker(
                    markerId: const MarkerId("assigned_junction"),
                    position: _junctionLocation!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                    infoWindow: InfoWindow(title: "Duty Junction", snippet: _myAssignedJunction)
                ));
              }

              if (snapshot.hasData) {
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;

                  // Use collision logic for map markers as well
                  bool isRelevant = _isPathCollidingWithJunction(data['encodedPolyline'], _junctionLocation);
                  if (!isRelevant && _junctionLocation != null) {
                    double dist = Geolocator.distanceBetween(data['latitude'], data['longitude'], _junctionLocation!.latitude, _junctionLocation!.longitude);
                    if (dist < 1500) isRelevant = true;
                  }
                  if (!isRelevant) {
                    isRelevant = _isJunctionNameOnPath(data['pathJunctions'] ?? [], _myAssignedJunction);
                  }

                  if (isRelevant) {
                    // Ambulance Current Location Marker
                    markers.add(Marker(
                        markerId: MarkerId("${doc.id}_live"),
                        position: LatLng(data['latitude'], data['longitude']),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: const InfoWindow(title: "Ambulance (Live)")
                    ));

                    // Ambulance Destination Marker
                    if (data['destLat'] != null && data['destLng'] != null) {
                      markers.add(Marker(
                          markerId: MarkerId("${doc.id}_dest"),
                          position: LatLng(data['destLat'], data['destLng']),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
                          infoWindow: const InfoWindow(title: "Ambulance Destination")
                      ));
                    }

                    // Ambulance Path Polyline
                    if (data['encodedPolyline'] != null) {
                      polylines.add(Polyline(
                        polylineId: PolylineId("${doc.id}_polyline"),
                        points: _decodePolyline(data['encodedPolyline']),
                        color: spotifyGreen,
                        width: 5,
                        jointType: JointType.round,
                      ));
                    }
                  }
                }
              }
              return GoogleMap(
                initialCameraPosition: CameraPosition(target: _myLocation, zoom: 14),
                onMapCreated: (c) => _mapController = c,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{ Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()) },
                markers: markers,
                polylines: polylines,
              );
            }
        ),
        Positioned(top: 16, right: 16, child: Column(children: [
          FloatingActionButton.small(heroTag: "recenter", backgroundColor: Colors.black.withOpacity(0.7), onPressed: _recenterToMyLocation, child: const Icon(Icons.my_location, color: spotifyGreen)),
          if (_junctionLocation != null) ...[
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: "showPost", backgroundColor: Colors.black.withOpacity(0.7), onPressed: () => _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_junctionLocation!, 16)), child: const Icon(Icons.flag, color: Colors.green)),
          ],
        ])),
      ],
    );
  }
}