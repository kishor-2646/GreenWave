import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/location_service.dart';

class AmbulanceMapPage extends StatefulWidget {
  const AmbulanceMapPage({super.key});

  @override
  State<AmbulanceMapPage> createState() => _AmbulanceMapPageState();
}

class _AmbulanceMapPageState extends State<AmbulanceMapPage> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  bool _isEmergencyActive = false;
  LatLng _currentLocation = const LatLng(0, 0);

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  // Initialize GPS and start listening to the position stream
  void _initLocation() async {
    bool hasPermission = await _locationService.handleLocationPermission();
    if (hasPermission) {
      Position pos = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
      });

      _locationService.getPositionStream().listen((Position position) {
        if (mounted) {
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
          });

          // Only push to Firebase if the emergency toggle is ON
          if (_isEmergencyActive) {
            _locationService.updateLiveLocation(position, "Ambulance Driver");
          }

          // Move camera to follow the ambulance
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(_currentLocation),
          );
        }
      });
    }
  }

  void _toggleEmergency() {
    setState(() {
      _isEmergencyActive = !_isEmergencyActive;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEmergencyActive ? "Emergency Started! Tracking live..." : "Emergency Ended."),
        backgroundColor: _isEmergencyActive ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Navigator"),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _currentLocation, zoom: 15),
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,

            markers: {
              Marker(
                markerId: const MarkerId("ambulance_marker"),
                position: _currentLocation,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: const InfoWindow(title: "Ambulance Status: Active"),
              ),
            },
          ),

          // Emergency Control Panel
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: _isEmergencyActive ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isEmergencyActive ? "EMERGENCY BROADCASTING" : "SYSTEM STANDBY",
                        style: TextStyle(
                          color: _isEmergencyActive ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _toggleEmergency,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isEmergencyActive
                            ? const Color(0xFF333333)
                            : const Color(0xFF22C55E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _isEmergencyActive ? "STOP EMERGENCY" : "START EMERGENCY",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}