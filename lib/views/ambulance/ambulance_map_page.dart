import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Import added
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin(); // Local instance

  bool _isEmergencyActive = false;
  bool _isFetchingRoute = false;
  LatLng _currentLocation = const LatLng(0, 0);
  LatLng? _destinationLocation;
  String? _encodedPolyline;
  List<Map<String, dynamic>> _routeSteps = [];

  bool _isSpeaking = false;
  bool _isQuotaExceeded = false;
  final Set<String> _announcedJunctions = {};
  StreamSubscription? _emergencySubscription;
  DateTime? _lastSpeechTime;

  final String _googleApiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: "");

  @override
  void initState() {
    super.initState();
    if (widget.initialDestination != null) _destinationLocation = widget.initialDestination;
    _initLocation();
    _startEmergencyListener();
    _resumeActiveEmergency();
  }

  @override
  void dispose() {
    _emergencySubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- NEW: SYSTEM NOTIFICATION FOR AMBULANCE DRIVER ---
  Future<void> _showSystemNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'Real-time alert for traffic clearance',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'clearance',
      color: Colors.green,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
    );
  }

  Future<void> _resumeActiveEmergency() async {
    final uid = _locationService.userId;
    if (uid == null) return;
    try {
      final doc = await _db.collection('ambulanceLocations').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] == 'emergency') {
          if (mounted) {
            setState(() {
              _isEmergencyActive = true;
              _encodedPolyline = data['encodedPolyline'];
              if (data['destLat'] != null && data['destLng'] != null) {
                _destinationLocation = LatLng(data['destLat'], data['destLng']);
              }
            });
            if (_destinationLocation != null) await _fetchRoute();
          }
        }
      }
    } catch (e) { debugPrint("Error resuming: $e"); }
  }

  void _initLocation() async {
    bool hasPermission = await _locationService.handleLocationPermission();
    if (hasPermission) {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));

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
          if (minDist < 500) { nearestJunction = _routeSteps[currentIdx]['name']; isNear = true; }
          int acc = 0;
          for (int i = currentIdx; i < _routeSteps.length; i++) {
            acc += (_routeSteps[i]['duration'] as int);
            junctionEtas[_routeSteps[i]['name']] = "${(acc / 60).ceil()} mins";
          }
        }

        if (mounted) setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
        _locationService.updateLiveLocation(position, "Ambulance Driver", isEmergency: _isEmergencyActive, destLat: _destinationLocation?.latitude, destLng: _destinationLocation?.longitude, encodedPolyline: _encodedPolyline, pathJunctions: _routeSteps.map((e) => e['name'] as String).toList(), nearestJunction: nearestJunction, isNearJunction: isNear, junctionEtas: junctionEtas);
      });
    }
  }

  void _startEmergencyListener() {
    final uid = _locationService.userId;
    if (uid == null) return;
    _emergencySubscription = _db.collection('ambulanceLocations').doc(uid).snapshots().listen((snapshot) {
      if (!snapshot.exists || !_isEmergencyActive) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final clearedJunctions = data['clearedJunctions'] as Map<String, dynamic>?;
      if (clearedJunctions != null) {
        clearedJunctions.forEach((key, junctionData) {
          final junctionName = junctionData['name'] ?? "Incoming Junction";
          if (!_announcedJunctions.contains(key)) {
            _announcedJunctions.add(key);

            // 1. Establish the "Talk Back" Establishing Logic
            _speakGemini("Alert. The junction $junctionName has been cleared by the police. You can proceed with safety.");

            // 2. Establish the System Tray Notification Logic
            _showSystemNotification("🚨 TRAFFIC CLEARED", "The junction $junctionName is now clear. Proceed safely.");
          }
        });
      }
    });
  }

  // --- FIRESTORE-BASED NOTIFICATION TRIGGER (FOR POLICE) ---
  Future<void> _triggerFirestoreNotification() async {
    final uid = _locationService.userId;
    if (uid == null) return;

    try {
      debugPrint("SYSTEM: Signaling Firestore Alert Collection...");
      await _db.collection('emergency_alerts').add({
        'ambulanceUid': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'Ambulance is starting an emergency broadcast.',
        'lat': _currentLocation.latitude,
        'lng': _currentLocation.longitude,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("🚨 Police Alert Signal Broadcasted"), backgroundColor: Colors.blueAccent, behavior: SnackBarBehavior.floating)
        );
      }
    } catch (e) {
      debugPrint("Trigger Error: $e");
    }
  }

  Uint8List _createWavHeader(Uint8List pcmData, int sampleRate) {
    final int fileSize = pcmData.length + 44;
    final ByteData header = ByteData(44);
    header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46);
    header.setUint32(4, fileSize - 8, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45);
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64); header.setUint8(37, 0x61); header.setUint8(38, 0x74); header.setUint8(39, 0x61);
    header.setUint32(40, pcmData.length, Endian.little);
    final Uint8List wavData = Uint8List(fileSize);
    wavData.setRange(0, 44, header.buffer.asUint8List());
    wavData.setRange(44, fileSize, pcmData);
    return wavData;
  }

  Future<void> _speakGemini(String message) async {
    if (_isSpeaking || !mounted) return;
    final now = DateTime.now();
    if (_lastSpeechTime != null && now.difference(_lastSpeechTime!).inSeconds < 10) return;
    setState(() => _isSpeaking = true);
    final String apiKey = dotenv.get('GEMINI_API_KEY', fallback: dotenv.get('GOOGLE_MAPS_API_KEY', fallback: ""));
    final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$apiKey");
    final payload = {"contents": [{"parts": [{"text": message}]}], "generationConfig": {"responseModalities": ["AUDIO"], "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Aoede"}}}}};
    try {
      final response = await http.post(url, body: jsonEncode(payload), headers: {"Content-Type": "application/json"});
      if (response.statusCode == 200) {
        if (mounted) setState(() => _isQuotaExceeded = false);
        final result = jsonDecode(response.body);
        final audioPart = result['candidates']?[0]?['content']?['parts']?[0]?['inlineData'];
        if (audioPart != null) {
          _lastSpeechTime = DateTime.now();
          final String base64Data = audioPart['data'];
          final wavBytes = _createWavHeader(base64Decode(base64Data), 24000);
          await _audioPlayer.play(BytesSource(wavBytes));
        }
      } else if (response.statusCode == 429) { if (mounted) setState(() => _isQuotaExceeded = true); }
    } catch (e) { debugPrint("Voice Error: $e"); } finally { await Future.delayed(const Duration(seconds: 2)); if (mounted) setState(() => _isSpeaking = false); }
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
          final polyline = data['routes'][0]['overview_polyline']['points'];
          final stepsList = data['routes'][0]['legs'][0]['steps'] as List;
          setState(() {
            _encodedPolyline = polyline;
            _routeSteps = stepsList.map((s) => {'lat': s['end_location']['lat'], 'lng': s['end_location']['lng'], 'name': (s['html_instructions'] as String).replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '').trim(), 'duration': s['duration']['value'] as int}).toList();
          });
        }
      }
    } catch (e) { debugPrint("Route failed: $e"); } finally { if (mounted) setState(() => _isFetchingRoute = false); }
  }

  void _toggleEmergency() async {
    if (_destinationLocation == null && !_isEmergencyActive) return;
    if (!_isEmergencyActive) {
      setState(() { _isEmergencyActive = true; _announcedJunctions.clear(); _isQuotaExceeded = false; });
      await _fetchRoute();
      Position pos = await Geolocator.getCurrentPosition();
      await _locationService.updateLiveLocation(pos, "Ambulance Driver", isEmergency: true, encodedPolyline: _encodedPolyline);
      _triggerFirestoreNotification();
    } else {
      setState(() { _isEmergencyActive = false; _encodedPolyline = null; _routeSteps = []; _announcedJunctions.clear(); _isQuotaExceeded = false; });
      Position pos = await Geolocator.getCurrentPosition();
      await _locationService.updateLiveLocation(pos, "Ambulance Driver", isEmergency: false);
      await _db.collection('ambulanceLocations').doc(_locationService.userId).update({'clearedJunctions': FieldValue.delete(), 'encodedPolyline': FieldValue.delete()});
    }
  }

  Set<Polyline> _calculatePolylines(Map<String, dynamic>? clearedJunctions) {
    if (_encodedPolyline == null) return {};
    final List<LatLng> fullPoints = _decodePolyline(_encodedPolyline!);
    LatLng? furthestClearedCoord; double maxD = -1;
    if (clearedJunctions != null) {
      clearedJunctions.forEach((key, data) {
        if (data['lat'] != null && data['lng'] != null) {
          double d = Geolocator.distanceBetween(fullPoints.first.latitude, fullPoints.first.longitude, data['lat'], data['lng']);
          if (d > maxD) { maxD = d; furthestClearedCoord = LatLng(data['lat'], data['lng']); }
        }
      });
    }
    if (furthestClearedCoord == null) return { Polyline(polylineId: const PolylineId("p"), points: fullPoints, color: Colors.purpleAccent, width: 7) };
    int splitIdx = 0; double minD = 1000000;
    for (int i = 0; i < fullPoints.length; i++) {
      double d = Geolocator.distanceBetween(fullPoints[i].latitude, fullPoints[i].longitude, furthestClearedCoord!.latitude, furthestClearedCoord!.longitude);
      if (d < minD) { minD = d; splitIdx = i; }
    }
    return {
      Polyline(polylineId: const PolylineId("g"), points: fullPoints.sublist(0, splitIdx + 1), color: const Color(0xFF22C55E), width: 8),
      Polyline(polylineId: const PolylineId("pr"), points: fullPoints.sublist(splitIdx), color: Colors.purpleAccent, width: 7)
    };
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
        if (_isQuotaExceeded) Positioned(top: 0, left: 0, right: 0, child: Container(color: Colors.black.withOpacity(0.8), padding: const EdgeInsets.symmetric(vertical: 6), child: const Center(child: Text("VOICE QUOTA REACHED - System Throttled", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))))),
        Positioned(top: 16, right: 16, child: Column(children: [FloatingActionButton.small(heroTag: "z_in", backgroundColor: Colors.black.withOpacity(0.7), onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomIn()), child: const Icon(Icons.add, color: Colors.white)), const SizedBox(height: 8), FloatingActionButton.small(heroTag: "z_out", backgroundColor: Colors.black.withOpacity(0.7), onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomOut()), child: const Icon(Icons.remove, color: Colors.white))])),
        if (_isFetchingRoute) const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)),
        DraggableScrollableSheet(initialChildSize: 0.25, minChildSize: 0.1, builder: (ctx, sc) => Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(children: [SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _isFetchingRoute ? null : _toggleEmergency, style: ElevatedButton.styleFrom(backgroundColor: _isEmergencyActive ? Colors.redAccent : Colors.purpleAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(_isEmergencyActive ? "STOP BROADCAST" : "START EMERGENCY BROADCAST", style: const TextStyle(fontWeight: FontWeight.bold))))])))
      ]),
    );
  }
}