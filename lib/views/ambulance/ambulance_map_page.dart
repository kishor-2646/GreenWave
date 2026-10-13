import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/services/location_service.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import 'package:dio/dio.dart';

import '../../core/models/emergency.dart';
import '../../core/network/api_error.dart';
import '../../core/network/realtime_service.dart';
import '../../core/repositories/emergency_repository.dart';
import '../../core/repositories/police_repository.dart';

class AmbulanceMapPage extends StatefulWidget {
  final LatLng? initialDestination;
  final int criticality;

  const AmbulanceMapPage({super.key, this.initialDestination, required this.criticality});

  @override
  State<AmbulanceMapPage> createState() => _AmbulanceMapPageState();
}

class _AmbulanceMapPageState extends State<AmbulanceMapPage> {
  GoogleMapController? _mapController;
  late final RealtimeService _realtime;
  late final LocationService _locationService;
  final EmergencyRepository _emergencyRepo = EmergencyRepository();
  final PoliceRepository _policeRepo = PoliceRepository();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // The server's emergency is the single source of truth.
  Emergency? _activeEmergency;
  bool get _isEmergencyActive => _activeEmergency != null;

  bool _isFetchingRoute = false;
  bool _isToggling = false;
  LatLng _currentLocation = const LatLng(0, 0);
  LatLng? _destinationLocation;
  String? _encodedPolyline;

  bool _isSpeaking = false;
  final Set<String> _announcedJunctions = {};

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _emergencySubscription;
  StreamSubscription? _radarSubscription;
  StreamSubscription? _reconnectSubscription;

  Map<String, LatLng> _policeOnRoute = {};
  BitmapDescriptor? _policeCircleIcon;

  final String _googleApiKey =
  dotenv.get('GOOGLE_MAPS_API_KEY', fallback: "");

  @override
  void initState() {
    super.initState();

    _realtime = context.read<RealtimeService>();
    _locationService = LocationService(_realtime);

    if (widget.initialDestination != null) {
      _destinationLocation = widget.initialDestination;
    }

    _initLocation();
    _startRealtime();
    _refreshFromServer();
    _createPoliceCircleIcon();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _emergencySubscription?.cancel();
    _radarSubscription?.cancel();
    _reconnectSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
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


  // ---------- location ----------

  Future<void> _initLocation() async {
    final hasPermission = await _locationService.handleLocationPermission();
    if (!hasPermission) return;

    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
    _locationService.sendPosition(pos);

    _positionSubscription = _locationService.getPositionStream().listen((position) {
      if (!mounted) return;
      setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
      _locationService.sendPosition(position);
    });
  }

  // ---------- realtime ----------

  void _startRealtime() {
    _emergencySubscription =
        _realtime.topic('/topic/emergencies').listen(_onEmergencyEvent);
    _radarSubscription =
        _realtime.topic('/topic/police-assignments').listen((_) => _refreshRadar());
    _reconnectSubscription =
        _realtime.onConnected.listen((_) => _refreshFromServer());
  }

  Future<void> _refreshFromServer() async {
    await _syncActiveEmergency();
    await _refreshRadar();
  }

  Future<void> _refreshRadar() async {
    try {
      final assignments = await _policeRepo.getAssignments();
      if (!mounted) return;
      setState(() {
        _policeOnRoute = {
          for (final a in assignments)
            a.junctionId: LatLng(a.latitude, a.longitude),
        };
      });
    } catch (e) {
      debugPrint('Radar refresh failed: ${apiErrorMessage(e)}');
    }
  }

  Future<void> _syncActiveEmergency() async {
    try {
      final mine = await _emergencyRepo.getMine();
      if (!mounted) return;
      _applyEmergency(mine);
    } catch (e) {
      debugPrint('Emergency sync failed: ${apiErrorMessage(e)}');
    }
  }

  void _onEmergencyEvent(Map<String, dynamic> json) {
    if (!mounted) return;
    try {
      final event = EmergencyEvent.fromJson(json);
      final myId = context.read<AuthService>().currentUser?.id;
      if (event.emergency.ambulanceUserId != myId) return;
      _applyEmergency(event.emergency);
    } catch (e) {
      debugPrint('Bad emergency event: $e');
    }
  }

  void _applyEmergency(Emergency? emergency) {
    final active =
    (emergency != null && emergency.isActive) ? emergency : null;

    if (active != null) {
      for (final cleared in active.clearedJunctions) {
        if (_announcedJunctions.add(cleared.junctionId)) {
          _speakGemini(
            'Update. ${cleared.junctionName} has been cleared.',
          );
        }
      }
    }

    setState(() {
      _activeEmergency = active;
      if (active != null) {
        _destinationLocation =
            LatLng(active.destinationLat, active.destinationLng);
        _encodedPolyline = active.encodedPolyline;
      } else {
        _encodedPolyline = null;
        _announcedJunctions.clear();
      }
    });
  }

  // ---------- start / stop ----------

  Future<void> _toggleEmergency() async {
    if (_isToggling) return;
    if (!_isEmergencyActive && _destinationLocation == null) return;

    setState(() => _isToggling = true);
    try {
      if (!_isEmergencyActive) {
        await _fetchRoute();
        if (_encodedPolyline == null || _destinationLocation == null) return;

        final emergency = await _emergencyRepo.start(
          criticality: widget.criticality,
          destinationLat: _destinationLocation!.latitude,
          destinationLng: _destinationLocation!.longitude,
          encodedPolyline: _encodedPolyline,
        );
        if (mounted) _applyEmergency(emergency);
      } else {
        final id = _activeEmergency!.id;
        final emergency = await _emergencyRepo.end(id);
        if (mounted) _applyEmergency(emergency);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
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