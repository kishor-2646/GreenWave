import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../core/services/location_service.dart';

class AmbulanceMapPage extends StatefulWidget {
  final LatLng? initialDestination;
  const AmbulanceMapPage({super.key, this.initialDestination});

  @override
  State<AmbulanceMapPage> createState() => _AmbulanceMapPageState();
}

class _AmbulanceMapPageState extends State<AmbulanceMapPage> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isEmergencyActive = false;
  bool _isFetchingRoute = false;
  LatLng _currentLocation = const LatLng(0, 0);
  LatLng? _destinationLocation;
  String? _encodedPolyline;
  List<Map<String, dynamic>> _routeSteps = [];

  final String _googleApiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: "");

  @override
  void initState() {
    super.initState();
    if (widget.initialDestination != null) _destinationLocation = widget.initialDestination;
    _initLocation();
  }

  void _initLocation() async {
    bool hasPermission = await _locationService.handleLocationPermission();
    if (hasPermission) {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));

      if (widget.initialDestination != null) _toggleEmergency();

      _locationService.getPositionStream().listen((Position position) {
        if (!mounted) return;

        Map<String, String> junctionEtas = {};
        String? nearestJunction;
        bool isNear = false;

        if (_isEmergencyActive && _routeSteps.isNotEmpty) {
          int currentIdx = 0; double minDist = double.infinity;
          for (int i = 0; i < _routeSteps.length; i++) {
            double d = Geolocator.distanceBetween(position.latitude, position.longitude, _routeSteps[i]['lat'], _routeSteps[i]['lng']);
            if (d < minDist) { minDist = d; currentIdx = i; }
          }
          if (minDist < 500) {
            nearestJunction = _routeSteps[currentIdx]['name'];
            isNear = true;
          }
          int acc = 0;
          for (int i = currentIdx; i < _routeSteps.length; i++) {
            acc += (_routeSteps[i]['duration'] as int);
            junctionEtas[_routeSteps[i]['name']] = "${(acc / 60).ceil()} mins";
          }
        }

        if (mounted) setState(() => _currentLocation = LatLng(position.latitude, position.longitude));

        _locationService.updateLiveLocation(
          position, "Ambulance Driver",
          isEmergency: _isEmergencyActive,
          destLat: _destinationLocation?.latitude,
          destLng: _destinationLocation?.longitude,
          encodedPolyline: _encodedPolyline,
          pathJunctions: _routeSteps.map((e) => e['name'] as String).toList(),
          nearestJunction: nearestJunction,
          isNearJunction: isNear,
          junctionEtas: junctionEtas,
        );
      });
    }
  }

  Future<void> _fetchRoute() async {
    if (_destinationLocation == null) return;
    setState(() => _isFetchingRoute = true);
    final String url = "https://maps.googleapis.com/maps/api/directions/json?origin=${_currentLocation.latitude},${_currentLocation.longitude}&destination=${_destinationLocation!.latitude},${_destinationLocation!.longitude}&mode=driving&key=$_googleApiKey";

    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          _encodedPolyline = data['routes'][0]['overview_polyline']['points'];
          final steps = data['routes'][0]['legs'][0]['steps'] as List;
          _routeSteps = steps.map((s) => {
            'lat': s['end_location']['lat'], 'lng': s['end_location']['lng'],
            'name': (s['html_instructions'] as String).replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '').trim(),
            'duration': s['duration']['value'] as int,
          }).toList();
        }
      }
    } catch (e) { debugPrint("Route fetch failed: $e"); }
    finally { if (mounted) setState(() => _isFetchingRoute = false); }
  }

  void _toggleEmergency() async {
    if (_destinationLocation == null && !_isEmergencyActive) return;

    if (!_isEmergencyActive) {
      setState(() => _isEmergencyActive = true);
      await _fetchRoute();
      Position pos = await Geolocator.getCurrentPosition();
      _locationService.updateLiveLocation(pos, "Ambulance Driver", isEmergency: true, encodedPolyline: _encodedPolyline);
    } else {
      setState(() {
        _isEmergencyActive = false;
        _encodedPolyline = null;
        _routeSteps = [];
      });
      Position pos = await Geolocator.getCurrentPosition();
      _locationService.updateLiveLocation(pos, "Ambulance Driver", isEmergency: false);
    }
  }

  // UPDATED LOGIC: Default is Purple, Cleared is Green
  Set<Polyline> _calculatePolylines(Map<String, dynamic>? clearedJunctions) {
    if (_encodedPolyline == null) return {};
    final List<LatLng> fullPoints = _decodePolyline(_encodedPolyline!);

    LatLng? furthestClearedCoord;
    double maxDistanceFromStart = -1;

    if (clearedJunctions != null) {
      clearedJunctions.forEach((key, data) {
        if (data['lat'] != null && data['lng'] != null) {
          double d = Geolocator.distanceBetween(fullPoints.first.latitude, fullPoints.first.longitude, data['lat'], data['lng']);
          if (d > maxDistanceFromStart) {
            maxDistanceFromStart = d;
            furthestClearedCoord = LatLng(data['lat'], data['lng']);
          }
        }
      });
    }

    // Default Purple Color for regular path
    const Color defaultPathColor = Colors.purpleAccent;
    // Green color for cleared segments
    const Color clearedPathColor = Color(0xFF22C55E);

    if (furthestClearedCoord == null) {
      // Entire path is Regular (Purple)
      return { Polyline(polylineId: const PolylineId("p_full"), points: fullPoints, color: defaultPathColor, width: 7) };
    } else {
      int splitIdx = 0; double minD = 1000000;
      for (int i = 0; i < fullPoints.length; i++) {
        double d = Geolocator.distanceBetween(fullPoints[i].latitude, fullPoints[i].longitude, furthestClearedCoord!.latitude, furthestClearedCoord!.longitude);
        if (d < minD) { minD = d; splitIdx = i; }
      }
      return {
        // Cleared part: Green
        Polyline(polylineId: const PolylineId("g_cleared"), points: fullPoints.sublist(0, splitIdx + 1), color: clearedPathColor, width: 8),
        // Remaining part: Purple
        Polyline(polylineId: const PolylineId("p_remaining"), points: fullPoints.sublist(splitIdx), color: defaultPathColor, width: 7)
      };
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = []; int index = 0, len = encoded.length; int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = _locationService.userId;
    if (uid == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Emergency Route"), backgroundColor: Colors.black),
      body: Stack(children: [
        StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('ambulanceLocations').doc(uid).snapshots(),
            builder: (context, snapshot) {
              Map<String, dynamic>? clearedJunctions;
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                clearedJunctions = data['clearedJunctions'];
              }

              return GoogleMap(
                initialCameraPosition: CameraPosition(target: _currentLocation, zoom: 15),
                onMapCreated: (c) => _mapController = c,
                myLocationEnabled: true,
                markers: {
                  Marker(markerId: const MarkerId("amb"), position: _currentLocation, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
                  if (_destinationLocation != null) Marker(markerId: const MarkerId("dest"), position: _destinationLocation!, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
                },
                polylines: _calculatePolylines(clearedJunctions),
                zoomControlsEnabled: false,
                onLongPress: (p) { if (!_isEmergencyActive) setState(() { _destinationLocation = p; }); },
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{ Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()) },
              );
            }
        ),

        Positioned(
            top: 16, right: 16,
            child: Column(children: [
              FloatingActionButton.small(heroTag: "z_in", backgroundColor: Colors.black.withOpacity(0.7), onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomIn()), child: const Icon(Icons.add, color: Colors.white)),
              const SizedBox(height: 8),
              FloatingActionButton.small(heroTag: "z_out", backgroundColor: Colors.black.withOpacity(0.7), onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomOut()), child: const Icon(Icons.remove, color: Colors.white)),
            ])
        ),

        if (_isFetchingRoute) const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)),

        DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.1,
            builder: (ctx, sc) => Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
                child: Column(children: [
                  SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _isFetchingRoute ? null : _toggleEmergency, style: ElevatedButton.styleFrom(backgroundColor: _isEmergencyActive ? Colors.redAccent : Colors.purpleAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(_isEmergencyActive ? "STOP BROADCAST" : "START EMERGENCY BROADCAST", style: const TextStyle(fontWeight: FontWeight.bold)))),
                ])
            )
        )
      ]),
    );
  }
}