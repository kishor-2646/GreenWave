import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/services/location_service.dart';

class AmbulanceMapPage extends StatefulWidget {
  final LatLng? initialDestination;
  final int criticality;

  const AmbulanceMapPage({super.key, this.initialDestination, required this.criticality});

  @override
  State<AmbulanceMapPage> createState() => _AmbulanceMapPageState();
}

class _AmbulanceMapPageState extends State<AmbulanceMapPage> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isEmergencyActive = false;
  bool _isFetchingRoute = false;
  LatLng _currentLocation = const LatLng(0, 0);
  LatLng? _destinationLocation;
  String? _encodedPolyline;

  bool _isSpeaking = false;
  final Set<String> _announcedJunctions = {};
  StreamSubscription? _emergencySubscription;

  Map<String, LatLng> _policeOnRoute = {};
  BitmapDescriptor? _policeCircleIcon;

  final String _googleApiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: "");
  final String _fcmServerKey = dotenv.get('FCM_SERVER_KEY', fallback: "");

  @override
  void initState() {
    super.initState();
    if (widget.initialDestination != null) _destinationLocation = widget.initialDestination;
    _initLocation();
    _startEmergencyListener();
    _resumeActiveEmergency();
    _startPoliceRadarListener();
    _createPoliceCircleIcon();
  }

  @override
  void dispose() { _emergencySubscription?.cancel(); _audioPlayer.dispose(); super.dispose(); }

  Future<void> _createPoliceCircleIcon() async {
    const int size = 80;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    final Paint paint = Paint()..color = Colors.blueAccent;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.5, paint);
    final ui.Image image = await pictureRecorder.endRecording().toImage(size, size);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) setState(() { _policeCircleIcon = BitmapDescriptor.fromBytes(byteData.buffer.asUint8List()); });
  }

  void _startPoliceRadarListener() {
    _db.collection('policeLocations').snapshots().listen((snapshot) {
      if (!mounted) return;
      final Map<String, LatLng> updatedPolice = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['junctionLat'] != null) updatedPolice[data['assignedJunction'] ?? "Officer"] = LatLng(data['junctionLat'], data['junctionLng']);
      }
      setState(() => _policeOnRoute = updatedPolice);
    });
  }

  Future<void> _triggerFirestoreNotification() async {
    final uid = _locationService.userId;
    if (uid == null) return;
    await _db.collection('emergency_alerts').add({
      'ambulanceUid': uid,
      'timestamp': FieldValue.serverTimestamp(),
      'message': 'Ambulance Emergency: Priority Level ${widget.criticality}',
      'criticality': widget.criticality,
      'lat': _currentLocation.latitude,
      'lng': _currentLocation.longitude,
    });
  }

  Future<void> _sendEmergencyBroadcastNotification() async {
    if (_fcmServerKey.isEmpty) return;
    try {
      await http.post(Uri.parse('https://fcm.googleapis.com/fcm/send'), headers: {'Content-Type': 'application/json', 'Authorization': 'key=$_fcmServerKey'}, body: jsonEncode({'to': '/topics/police_alerts', 'notification': {'title': '🚨 EMERGENCY ALERT', 'body': 'Clear the path! Ambulance broadcast started.'}, 'priority': 'high'}));
    } catch (e) { debugPrint("FCM Error: $e"); }
  }

  void _initLocation() async {
    bool hasPermission = await _locationService.handleLocationPermission();
    if (hasPermission) {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
      _locationService.getPositionStream().listen((Position position) {
        if (!mounted) return;
        setState(() => _currentLocation = LatLng(position.latitude, position.longitude));

        // CRITICAL FIX: Ensure _encodedPolyline is only pushed when emergency is active
        // This prevents overwriting the valid route with null during location pings
        _locationService.updateLiveLocation(
            position,
            "Ambulance Driver",
            isEmergency: _isEmergencyActive,
            encodedPolyline: _isEmergencyActive ? _encodedPolyline : null,
            destLat: _isEmergencyActive ? _destinationLocation?.latitude : null,
            destLng: _isEmergencyActive ? _destinationLocation?.longitude : null
        );
      });
    }
  }

  void _startEmergencyListener() {
    final uid = _locationService.userId;
    if (uid == null) return;
    _emergencySubscription = _db.collection('ambulanceLocations').doc(uid).snapshots().listen((snapshot) {
      if (!snapshot.exists || !_isEmergencyActive) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final cleared = data['clearedJunctions'] as Map<String, dynamic>?;
      if (cleared != null) {
        cleared.forEach((key, val) {
          if (!_announcedJunctions.contains(key)) {
            _announcedJunctions.add(key);
            _speakGemini("Update. ${val['name'] ?? "Junction"} has been cleared.");
          }
        });
      }
    });
  }

  Future<void> _speakGemini(String message) async {
    if (_isSpeaking || !mounted) return;
    setState(() => _isSpeaking = true);
    final String apiKey = dotenv.get('GEMINI_API_KEY', fallback: "");
    final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$apiKey");
    final payload = {"contents": [{"parts": [{"text": message}]}], "generationConfig": {"responseModalities": ["AUDIO"], "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Aoede"}}}}};
    try {
      final response = await http.post(url, body: jsonEncode(payload), headers: {"Content-Type": "application/json"});
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final audioPart = result['candidates']?[0]?['content']?['parts']?[0]?['inlineData'];
        if (audioPart != null) await _audioPlayer.play(BytesSource(_createWavHeader(base64Decode(audioPart['data']), 24000)));
      }
    } catch (e) { debugPrint("Voice Error: $e"); } finally { await Future.delayed(const Duration(seconds: 2)); if (mounted) setState(() => _isSpeaking = false); }
  }

  Uint8List _createWavHeader(Uint8List pcmData, int sampleRate) {
    final header = ByteData(44);
    header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46);
    header.setUint32(4, pcmData.length + 36, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45);
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little); header.setUint16(20, 1, Endian.little); header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little); header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little); header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64); header.setUint8(37, 0x61); header.setUint8(38, 0x74); header.setUint8(39, 0x61);
    header.setUint32(40, pcmData.length, Endian.little);
    final res = Uint8List(pcmData.length + 44);
    res.setRange(0, 44, header.buffer.asUint8List()); res.setRange(44, res.length, pcmData);
    return res;
  }

  Future<void> _fetchRoute() async {
    if (_destinationLocation == null) return;
    setState(() => _isFetchingRoute = true);
    final url = "https://maps.googleapis.com/maps/api/directions/json?origin=${_currentLocation.latitude},${_currentLocation.longitude}&destination=${_destinationLocation!.latitude},${_destinationLocation!.longitude}&mode=driving&key=$_googleApiKey";
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final String poly = data['routes'][0]['overview_polyline']['points'];
          debugPrint("SYNC_DEBUG: String length received: ${poly.length}");
          setState(() { _encodedPolyline = poly; });
        }
      }
    } catch (e) { debugPrint("Route failed: $e"); } finally { if (mounted) setState(() => _isFetchingRoute = false); }
  }

  void _toggleEmergency() async {
    if (_destinationLocation == null && !_isEmergencyActive) return;
    if (!_isEmergencyActive) {
      setState(() { _isEmergencyActive = true; _announcedJunctions.clear(); });
      await _fetchRoute();
      Position pos = await Geolocator.getCurrentPosition();
      await _locationService.updateLiveLocation(pos, "Ambulance Driver", isEmergency: true, encodedPolyline: _encodedPolyline, destLat: _destinationLocation?.latitude, destLng: _destinationLocation?.longitude);
      _sendEmergencyBroadcastNotification();
      _triggerFirestoreNotification();
    } else {
      setState(() { _isEmergencyActive = false; _encodedPolyline = null; });
      Position pos = await Geolocator.getCurrentPosition();
      await _locationService.updateLiveLocation(pos, "Ambulance Driver", isEmergency: false);
      await _db.collection('ambulanceLocations').doc(_locationService.userId).update({'clearedJunctions': FieldValue.delete(), 'encodedPolyline': FieldValue.delete(), 'destLat': FieldValue.delete(), 'destLng': FieldValue.delete()});
    }
  }

  Future<void> _resumeActiveEmergency() async {
    final uid = _locationService.userId;
    if (uid == null) return;
    final doc = await _db.collection('ambulanceLocations').doc(uid).get();
    if (doc.exists && doc.data()?['status'] == 'emergency') {
      setState(() {
        _isEmergencyActive = true;
        _encodedPolyline = doc.data()?['encodedPolyline'];
        if (doc.data()?['destLat'] != null) _destinationLocation = LatLng(doc.data()!['destLat'], doc.data()!['destLng']);
      });
      if (_destinationLocation != null) await _fetchRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Emergency Route"), backgroundColor: Colors.black),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _currentLocation, zoom: 15),
          onMapCreated: (c) => _mapController = c,
          myLocationEnabled: true,
          markers: {
            Marker(markerId: const MarkerId("amb"), position: _currentLocation, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
            if (_destinationLocation != null) Marker(markerId: const MarkerId("dest"), position: _destinationLocation!, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
            ..._policeOnRoute.entries.map((e) => Marker(markerId: MarkerId(e.key), position: e.value, icon: _policeCircleIcon ?? BitmapDescriptor.defaultMarker, anchor: const Offset(0.5, 0.5)))
          },
          circles: _policeOnRoute.entries.map((e) => Circle(circleId: CircleId("radar_${e.key}"), center: e.value, radius: 1000, fillColor: Colors.blue.withOpacity(0.15), strokeColor: Colors.blueAccent.withOpacity(0.4), strokeWidth: 2)).toSet(),
          polylines: _encodedPolyline == null ? {} : {Polyline(polylineId: const PolylineId("p"), points: _decodePolyline(_encodedPolyline!), color: Colors.purpleAccent, width: 7, jointType: JointType.round)},
          onLongPress: (p) { if (!_isEmergencyActive) setState(() { _destinationLocation = p; }); },
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{ Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()) },
        ),
        DraggableScrollableSheet(initialChildSize: 0.2, minChildSize: 0.1, builder: (ctx, sc) => Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(children: [SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _isFetchingRoute ? null : _toggleEmergency, style: ElevatedButton.styleFrom(backgroundColor: _isEmergencyActive ? Colors.redAccent : Colors.purpleAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(_isEmergencyActive ? "STOP BROADCAST" : "START EMERGENCY BROADCAST", style: const TextStyle(fontWeight: FontWeight.bold))))])))
      ]),
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = []; int index = 0, len = encoded.length; int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        if (index >= len) return points;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0; result = 0;
      do {
        if (index >= len) return points;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}