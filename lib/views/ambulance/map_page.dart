import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

class _AmbulanceMapPageState extends State<AmbulanceMapPage> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  late AnimationController _blinkController;

  bool _isEmergencyActive = false;
  bool _isFetchingRoute = false;
  LatLng _currentLocation = const LatLng(0, 0);
  LatLng? _destinationLocation;
  String? _currentEncodedPolyline;
  List<Map<String, dynamic>> _routeSteps = [];

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  final String _googleApiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: "");

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    if (widget.initialDestination != null) _destinationLocation = widget.initialDestination;
    _initLocation();
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _initLocation() async {
    bool hasPermission = await _locationService.handleLocationPermission();
    if (hasPermission) {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _updateMarkers();
        });
        if (widget.initialDestination != null) _toggleEmergency();
      }

      _locationService.getPositionStream().listen((Position position) {
        if (!mounted) return;

        String? nearestJunction;
        bool isNear = false;

        if (_isEmergencyActive && _routeSteps.isNotEmpty) {
          for (var step in _routeSteps) {
            double distance = Geolocator.distanceBetween(position.latitude, position.longitude, step['lat'], step['lng']);
            if (distance < 500) {
              nearestJunction = step['name'];
              isNear = true;
              break;
            }
          }
        }

        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _updateMarkers();
        });

        _locationService.updateLiveLocation(
          position,
          "Ambulance Driver",
          isEmergency: _isEmergencyActive,
          destLat: _destinationLocation?.latitude,
          destLng: _destinationLocation?.longitude,
          encodedPolyline: _isEmergencyActive ? _currentEncodedPolyline : null,
          pathJunctions: _routeSteps.map((e) => e['name'] as String).toList(),
          nearestJunction: nearestJunction,
          isNearJunction: isNear,
        );
      });
    }
  }

  String _cleanJunctionName(String html) {
    // Remove HTML tags and strip common filler words like "onto", "at", "roundabout"
    String text = html.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ');
    text = text.replaceAll(RegExp(r'\b(onto|at|through|roundabout|the|and)\b', caseSensitive: false), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _fetchAndDrawRoute() async {
    if (_destinationLocation == null) return;
    setState(() => _isFetchingRoute = true);

    final String url = "https://maps.googleapis.com/maps/api/directions/json?origin=${_currentLocation.latitude},${_currentLocation.longitude}&destination=${_destinationLocation!.latitude},${_destinationLocation!.longitude}&mode=driving&key=$_googleApiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          _currentEncodedPolyline = data['routes'][0]['overview_polyline']['points'];
          final steps = data['routes'][0]['legs'][0]['steps'] as List;
          _routeSteps = steps.map((s) => {
            'lat': s['end_location']['lat'],
            'lng': s['end_location']['lng'],
            'name': _cleanJunctionName(s['html_instructions'] as String),
          }).toList();

          setState(() {
            _polylines.add(Polyline(polylineId: const PolylineId("route"), points: _decodePolyline(_currentEncodedPolyline!), color: const Color(0xFF22C55E), width: 6));
          });
        }
      }
    } catch (e) {
      debugPrint("Route error: $e");
    } finally {
      if (mounted) setState(() => _isFetchingRoute = false);
    }
  }

  void _toggleEmergency() async {
    if (_destinationLocation == null && !_isEmergencyActive) return;
    bool newStatus = !_isEmergencyActive;
    if (newStatus) {
      await _fetchAndDrawRoute();
      if (_polylines.isEmpty) return;
    }
    setState(() {
      _isEmergencyActive = newStatus;
      if (!newStatus) { _polylines.clear(); _currentEncodedPolyline = null; _routeSteps = []; }
    });
    try {
      Position currentPos = await Geolocator.getCurrentPosition();
      await _locationService.updateLiveLocation(
        currentPos, "Ambulance Driver", isEmergency: newStatus,
        destLat: _destinationLocation?.latitude, destLng: _destinationLocation?.longitude,
        encodedPolyline: newStatus ? _currentEncodedPolyline : null,
        pathJunctions: _routeSteps.map((e) => e['name'] as String).toList(),
      );
    } catch (e) { debugPrint("Sync failed: $e"); }
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

  void _updateMarkers() {
    _markers.removeWhere((m) => m.markerId.value == "ambulance" || m.markerId.value == "destination");
    _markers.add(Marker(markerId: const MarkerId("ambulance"), position: _currentLocation, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)));
    if (_destinationLocation != null) _markers.add(Marker(markerId: const MarkerId("destination"), position: _destinationLocation!, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)));
  }

  void _recenterToMyLocation() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: _currentLocation, zoom: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color brandGreen = Color(0xFF22C55E);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Emergency Route"), backgroundColor: Colors.black),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _currentLocation, zoom: 15),
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // Using custom recenter button
            markers: _markers,
            polylines: _polylines,
            zoomControlsEnabled: false,
            onLongPress: (pos) { if (!_isEmergencyActive) setState(() { _destinationLocation = pos; _updateMarkers(); _polylines.clear(); }); },
          ),

          // Floating Action Buttons (Recenter & Show Post)
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: "recenter",
                  backgroundColor: Colors.black.withOpacity(0.7),
                  onPressed: _recenterToMyLocation,
                  child: const Icon(Icons.my_location, color: brandGreen),
                ),
                if (_destinationLocation != null) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: "showPost",
                    backgroundColor: Colors.black.withOpacity(0.7),
                    onPressed: () => _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(_destinationLocation!, 16)
                    ),
                    child: const Icon(Icons.flag, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),

          if (_isFetchingRoute) const Center(child: CircularProgressIndicator(color: brandGreen)),

          DraggableScrollableSheet(
            initialChildSize: 0.3,
            builder: (context, scrollController) => Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      onPressed: _isFetchingRoute ? null : _toggleEmergency,
                      style: ElevatedButton.styleFrom(backgroundColor: _isEmergencyActive ? Colors.redAccent : brandGreen),
                      child: Text(_isEmergencyActive ? "STOP BROADCAST" : "START BROADCAST"),
                    ),
                  ),
                  if (_isEmergencyActive) Padding(padding: const EdgeInsets.only(top: 10), child: const Text("📡 BROADCASTING TO ALL JUNCTION POLICE", style: TextStyle(color: brandGreen, fontWeight: FontWeight.bold, fontSize: 12))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}