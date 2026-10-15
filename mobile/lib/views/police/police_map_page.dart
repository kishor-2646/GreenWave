import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../core/models/emergency.dart';
import '../../core/models/junction.dart';
import '../../core/models/live_location.dart';
import '../../core/network/api_error.dart';
import '../../core/network/realtime_service.dart';
import '../../core/repositories/emergency_repository.dart';
import '../../core/repositories/junction_repository.dart';
import '../../core/repositories/location_repository.dart';
import '../../core/repositories/police_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/location_service.dart';

class PoliceMapPage extends StatefulWidget {
  const PoliceMapPage({super.key});

  @override
  State<PoliceMapPage> createState() => _PoliceMapPageState();
}

class _PoliceMapPageState extends State<PoliceMapPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  GoogleMapController? _mapController;
  LatLng _myLocation = const LatLng(12.9716, 77.5946);
  bool _locationPermissionGranted = false;

  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color darkCard = Color(0xFF282828);
  static const Color bgBlack = Color(0xFF121212);
  static const Color emergencyPurple = Colors.purpleAccent;

  // ---- dependencies ----
  late final RealtimeService _realtime;
  late final LocationService _locationService;
  final EmergencyRepository _emergencyRepo = EmergencyRepository();
  final PoliceRepository _policeRepo = PoliceRepository();
  final JunctionRepository _junctionRepo = JunctionRepository();
  final LocationRepository _locationRepo = LocationRepository();

  // ---- state that mirrors the SERVER ----
  List<Junction> _junctions = [];
  Junction? _myJunction; // the junction this officer is posted at
  final Map<String, Emergency> _emergencies = {}; // active ones, key = emergency id
  final Map<String, LiveLocation> _ambulances = {}; // key = ambulance user id

  // ---- UI-only state ----
  bool _isClearing = false; // blocks double taps on CLEAR/UNDO
  bool _isSpeaking = false;
  bool _isQuotaExceeded = false;
  DateTime? _lastSpeechTime;

  final Map<String, List<LatLng>> _polylineCache = {}; // key = emergency id
  final Set<String> _announcedAmbulances = {}; // emergency ids we said "incoming" for
  final Set<String> _arrivedAnnounced = {}; // emergency ids we said "reached" for
  final Set<String> _notifiedEmergencyIds = {};

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _emergencySubscription;
  StreamSubscription? _ambulanceSubscription;
  StreamSubscription? _reconnectSubscription;

  @override
  void initState() {
    super.initState();
    _realtime = context.read<RealtimeService>();
    _locationService = LocationService(_realtime);
    _tabController = TabController(length: 2, vsync: this);
    _checkPermissionsAndInit();
    _startRealtime();
    _refreshFromServer();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _emergencySubscription?.cancel();
    _ambulanceSubscription?.cancel();
    _reconnectSubscription?.cancel();
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ======================= location =======================

  Future<void> _checkPermissionsAndInit() async {
    final granted = await _locationService.handleLocationPermission();
    if (!granted || !mounted) return;
    setState(() => _locationPermissionGranted = true);

    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
    _locationService.sendPosition(pos); // admins can now see this officer online

    _positionSubscription = _locationService.getPositionStream().listen((position) {
      if (!mounted) return;
      setState(() => _myLocation = LatLng(position.latitude, position.longitude));
      _locationService.sendPosition(position);
    });
  }

  // ======================= realtime + server sync =======================

  void _startRealtime() {
    _emergencySubscription = _realtime.topic('/topic/emergencies').listen(_onEmergencyEvent);
    _ambulanceSubscription = _realtime.topic('/topic/ambulance-updates').listen(_onAmbulanceLocation);
    // Any (re)connect: we may have missed events, so rebuild state from REST.
    _reconnectSubscription = _realtime.onConnected.listen((_) => _refreshFromServer());
  }

  // Runs a request; on failure logs and returns null instead of throwing,
  // so one failing endpoint doesn't stop the other three from loading.
  Future<T?> _safe<T>(Future<T> request) async {
    try {
      return await request;
    } catch (e) {
      debugPrint('Sync failed: ${apiErrorMessage(e)}');
      return null;
    }
  }

  Future<void> _refreshFromServer() async {
    final junctions = await _safe(_junctionRepo.getAll());
    final assignments = await _safe(_policeRepo.getAssignments());
    final active = await _safe(_emergencyRepo.getActive());
    final ambulances = await _safe(_locationRepo.getAmbulances());
    if (!mounted) return;

    final myId = context.read<AuthService>().currentUser?.id;

    setState(() {
      if (junctions != null) _junctions = junctions;

      if (assignments != null) {
        _myJunction = null;
        for (final a in assignments) {
          if (a.userId == myId) {
            _myJunction = Junction(
              id: a.junctionId,
              name: a.junctionName,
              latitude: a.latitude,
              longitude: a.longitude,
            );
          }
        }
      }

      if (active != null) {
        _emergencies
          ..clear()
          ..addEntries(active.map((e) => MapEntry(e.id, e)));
        _polylineCache.removeWhere((id, _) => !_emergencies.containsKey(id));
      }

      if (ambulances != null) {
        _ambulances.clear();
        for (final l in ambulances) {
          _ambulances[l.userId] = l;
        }
      }
    });
    _evaluateVoice();
  }

  void _onEmergencyEvent(Map<String, dynamic> json) {
    if (!mounted) return;
    try {
      final event = EmergencyEvent.fromJson(json);
      setState(() => _applyEmergency(event.emergency));
      if (event.type == 'STARTED') _notifyIfRelevant(event.emergency);
      _evaluateVoice();
    } catch (e) {
      debugPrint('Bad emergency event: $e');
    }
  }

  void _onAmbulanceLocation(Map<String, dynamic> json) {
    if (!mounted) return;
    try {
      final loc = LiveLocation.fromJson(json);
      setState(() => _ambulances[loc.userId] = loc);
      _evaluateVoice();
    } catch (e) {
      debugPrint('Bad location event: $e');
    }
  }

  // The one place a single emergency enters or leaves local state.
  // Call it inside setState. Idempotent.
  void _applyEmergency(Emergency e) {
    if (e.isActive) {
      _emergencies[e.id] = e;
    } else {
      _emergencies.remove(e.id);
      _polylineCache.remove(e.id);
      _announcedAmbulances.remove(e.id);
      _arrivedAnnounced.remove(e.id);
    }
  }

  // ======================= actions =======================

  Future<void> _assignJunction(Junction junction) async {
    try {
      await _policeRepo.assign(junction.id);
      if (!mounted) return;
      setState(() {
        _myJunction = junction;
        _announcedAmbulances.clear();
        _arrivedAnnounced.clear();
        _polylineCache.clear();
        _isQuotaExceeded = false;
      });
      _fitMapToPoints([_myLocation, LatLng(junction.latitude, junction.longitude)]);
      _evaluateVoice();
    } catch (e) {
      _showSnack(apiErrorMessage(e), Colors.redAccent);
    }
  }

  Future<void> _setCleared(Emergency emergency, {required bool cleared}) async {
    final junction = _myJunction;
    if (junction == null || _isClearing) return;

    setState(() => _isClearing = true);
    try {
      // The server returns the updated emergency; we apply it right away.
      // The broadcast event arrives too, and applying twice is harmless.
      final updated = cleared
          ? await _emergencyRepo.markCleared(emergency.id, junction.id)
          : await _emergencyRepo.revertClearance(emergency.id, junction.id);
      if (!mounted) return;
      setState(() => _applyEmergency(updated));
      _showSnack(
        cleared ? 'Cleared - Route turning Green for Ambulance' : 'Clearance reverted',
        cleared ? spotifyGreen : Colors.orange,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // 404/409: the emergency probably ended meanwhile. Re-sync so the stale card disappears.
      if (code == 404 || code == 409) await _refreshFromServer();
      _showSnack(apiErrorMessage(e), Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  // ======================= relevance, distance, voice =======================

  LatLng? get _junctionPoint {
    final j = _myJunction;
    return j == null ? null : LatLng(j.latitude, j.longitude);
  }


  bool _isRelevant(Emergency e) {
    final point = _junctionPoint;
    if (point == null) return false;

    return _isPathColliding(e.encodedPolyline, point, e.id);
  }


  /// Straight-line metres from the ambulance to my post (null if unknown).
  double? _distanceToPost(Emergency e) {
    final point = _junctionPoint;
    final loc = _ambulances[e.ambulanceUserId];
    if (point == null || loc == null) return null;
    return Geolocator.distanceBetween(loc.latitude, loc.longitude, point.latitude, point.longitude);
  }

  String _formatDistance(double? metres) {
    if (metres == null) return 'Locating...';
    return metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';
  }

  void _evaluateVoice() {
    if (_myJunction == null) return;
    for (final e in _emergencies.values) {
      if (!_isRelevant(e)) continue;
      if (_announcedAmbulances.add(e.id)) {
        _speakGemini('Alert. An ambulance is incoming on your junction path. Stay alert.');
        continue;
      }
      final d = _distanceToPost(e);
      if (d != null && d < 500 && _arrivedAnnounced.add(e.id)) {
        _speakGemini('Alert. The ambulance has reached your junction. Clear the signals immediately.',
            urgent: true);
      }
    }
  }

  // ======================= notification =======================

  void _notifyIfRelevant(Emergency e) {
    if (!_notifiedEmergencyIds.add(e.id)) return; // never notify twice for one emergency
    if (_myJunction != null && !_isRelevant(e)) return; // not on my route
    _showSystemNotification('Priority ${e.criticality} emergency: ${e.ambulanceName} is on the move.');
  }

  Future<void> _showSystemNotification(String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'Real-time alert for police',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'emergency',
      color: Colors.red,
      ledColor: Colors.red,
      ledOnMs: 1000,
      ledOffMs: 500,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique per second (was .millisecond: collides)
      "🚨 AMBULANCE ALERT",
      body,
      details,
    );
  }

  // ======================= voice (Gemini TTS) — unchanged except `urgent` =======================

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

  // `urgent` skips the 10-second spacing rule, so "reached your junction"
  // isn't swallowed because "incoming" was spoken a moment ago.
  Future<void> _speakGemini(String message, {bool urgent = false}) async {
    if (_isSpeaking || !mounted) return;
    final now = DateTime.now();
    if (!urgent && _lastSpeechTime != null && now.difference(_lastSpeechTime!).inSeconds < 10) return;
    setState(() => _isSpeaking = true);
    final String apiKey = dotenv.get('GEMINI_API_KEY', fallback: dotenv.get('GOOGLE_MAPS_API_KEY', fallback: ""));
    if (apiKey.isEmpty) {
      setState(() => _isSpeaking = false);
      return;
    }
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
          final wavBytes = _createWavHeader(base64Decode(audioPart['data']), 24000);
          await _audioPlayer.play(BytesSource(wavBytes));
        }
      } else if (response.statusCode == 429) {
        if (mounted) setState(() => _isQuotaExceeded = true);
      }
    } catch (e) {
      debugPrint("TTS: $e");
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  // ======================= map helpers =======================

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
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 80));
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        if (index >= len) return points; // truncated string: stop instead of crashing
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0;
      result = 0;
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

  // Decoded route for an emergency, cached by emergency id.
  List<LatLng>? _routePoints(Emergency e) {
    final encoded = e.encodedPolyline;
    if (encoded == null) return null;
    return _polylineCache.putIfAbsent(e.id, () => _decodePolyline(encoded));
  }


  bool _isPathColliding(
      String? encodedPolyline,
      LatLng? junctionLoc,
      String emergencyId,
      ) {
    if (encodedPolyline == null || junctionLoc == null) return false;

    try {
      final pathPoints = _polylineCache.putIfAbsent(
        emergencyId,
            () => _decodePolyline(encodedPolyline),
      );

      if (pathPoints.isEmpty) return false;

      const toleranceMetres = 100.0;

      // Check every route segment instead of skipping route points.
      for (int i = 0; i < pathPoints.length - 1; i++) {
        final start = pathPoints[i];
        final end = pathPoints[i + 1];

        final segmentLength = Geolocator.distanceBetween(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        );

        // Sample long segments more densely, at intervals of about 25 m.
        final steps = (segmentLength / 25).ceil().clamp(1, 10000);

        for (int step = 0; step <= steps; step++) {
          final t = step / steps;

          final lat = start.latitude +
              (end.latitude - start.latitude) * t;
          final lng = start.longitude +
              (end.longitude - start.longitude) * t;

          final distance = Geolocator.distanceBetween(
            lat,
            lng,
            junctionLoc.latitude,
            junctionLoc.longitude,
          );

          if (distance <= toleranceMetres) return true;
        }
      }
    } catch (e) {
      debugPrint('Route matching error: $e');
    }

    return false;
  }


  // ======================= UI =======================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Traffic Control Portal', style: TextStyle(fontSize: 18)),
        actions: [
          PopupMenuButton<Junction>(
            icon: const Icon(Icons.settings_input_component, color: spotifyGreen),
            onSelected: _assignJunction,
            itemBuilder: (context) => _junctions
                .map((j) => PopupMenuItem<Junction>(
                value: j, child: Text(j.name, style: const TextStyle(fontSize: 13))))
                .toList(),
          )
        ],
        bottom: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'ALERTS'), Tab(text: 'MAP')],
            indicatorColor: spotifyGreen,
            labelColor: spotifyGreen),
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
    final name = _myJunction?.name;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: Colors.white.withOpacity(0.05),
      child: Row(
        children: [
          Icon(Icons.radar, size: 14, color: name == null ? Colors.orange : spotifyGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                name == null
                    ? "⚠️ SELECT YOUR JUNCTION (TOP-RIGHT)"
                    : "SYSTEM ACTIVE: Scanning Path for Duty at $name",
                style: TextStyle(
                    color: name == null ? Colors.orange : Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          if (_isQuotaExceeded)
            const Text("VOICE QUOTA REACHED",
                style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    final relevant = _emergencies.values.where(_isRelevant).toList();
    if (relevant.isEmpty) {
      return const Center(child: Text("Waiting for incoming ambulances...", style: TextStyle(color: Colors.white30)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: relevant.map(_buildAlertCard).toList(),
    );
  }

  Widget _buildAlertCard(Emergency e) {
    final myJunctionId = _myJunction?.id;
    final isCleared = e.clearedJunctions.any((c) => c.junctionId == myJunctionId);
    final loc = _ambulances[e.ambulanceUserId];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: isCleared ? spotifyGreen.withOpacity(0.2) : darkCard,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isCleared ? spotifyGreen : Colors.white10, width: 2)),
      child: Column(
        children: [
          Row(children: [
            Icon(Icons.local_hospital, color: isCleared ? spotifyGreen : Colors.red),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    isCleared ? "TRAFFIC CLEARED" : "INCOMING: ${e.ambulanceName} · P${e.criticality}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
          ]),
          const Divider(color: Colors.white10, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Distance to your post:", style: TextStyle(color: Colors.white70, fontSize: 13)),
            Text(_formatDistance(_distanceToPost(e)),
                style: const TextStyle(color: spotifyGreen, fontWeight: FontWeight.bold))
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: ElevatedButton(
                      onPressed: () {
                        _tabController.animateTo(1);
                        if (loc != null) {
                          _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(LatLng(loc.latitude, loc.longitude), 17));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: spotifyGreen, foregroundColor: Colors.black),
                      child: const Text("MAP"))),
              const SizedBox(width: 8),
              Expanded(
                  child: ElevatedButton(
                      onPressed: _isClearing ? null : () => _setCleared(e, cleared: !isCleared),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: isCleared ? Colors.white10 : spotifyGreen,
                          foregroundColor: Colors.white),
                      child: Text(isCleared ? "UNDO" : "CLEAR TRAFFIC"))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final markers = <Marker>{
      Marker(
          markerId: const MarkerId("police_me"),
          position: _myLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)),
    };
    final polylines = <Polyline>{};
    Emergency? activeEmergency;
    LiveLocation? activeAmbulance;

    final point = _junctionPoint;
    if (point != null) {
      markers.add(Marker(
          markerId: const MarkerId("assigned_junction"),
          position: point,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)));
    }

    for (final e in _emergencies.values.where(_isRelevant)) {
      activeEmergency ??= e;
      final loc = _ambulances[e.ambulanceUserId];
      if (loc != null) {
        activeAmbulance ??= loc;
        markers.add(Marker(
            markerId: MarkerId("amb_${e.id}"),
            position: LatLng(loc.latitude, loc.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)));
      }

      final points = _routePoints(e);
      if (points == null || points.isEmpty) continue;

      // The cleared part of the route is drawn green, the rest purple.
      // The split is at the cleared junction furthest from the route's start.
      LatLng? splitPoint;
      double furthest = -1;
      for (final c in e.clearedJunctions) {
        final d = Geolocator.distanceBetween(
            points.first.latitude, points.first.longitude, c.latitude, c.longitude);
        if (d > furthest) {
          furthest = d;
          splitPoint = LatLng(c.latitude, c.longitude);
        }
      }

      final split = splitPoint;
      if (split == null) {
        polylines.add(Polyline(polylineId: PolylineId("${e.id}_poly"), points: points, color: emergencyPurple, width: 6));
      } else {
        int splitIdx = 0;
        double minD = double.infinity;
        for (int i = 0; i < points.length; i++) {
          final d = Geolocator.distanceBetween(points[i].latitude, points[i].longitude, split.latitude, split.longitude);
          if (d < minD) {
            minD = d;
            splitIdx = i;
          }
        }
        polylines.add(Polyline(
            polylineId: PolylineId("${e.id}_cleared"),
            points: points.sublist(0, splitIdx + 1),
            color: spotifyGreen,
            width: 8));
        polylines.add(Polyline(
            polylineId: PolylineId("${e.id}_rem"),
            points: points.sublist(splitIdx),
            color: emergencyPurple,
            width: 6));
      }
    }

    return Stack(
      children: [
        GoogleMap(
            initialCameraPosition: CameraPosition(target: _myLocation, zoom: 14),
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: _locationPermissionGranted,
            myLocationButtonEnabled: false,
            markers: markers,
            polylines: polylines,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())
            }),
        if (activeEmergency != null)
          Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: darkCard,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: spotifyGreen, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 4))]),
                  child: Row(children: [
                    Icon(_isSpeaking ? Icons.volume_up : Icons.timer, color: spotifyGreen),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text("Ambulance is ${_formatDistance(_distanceToPost(activeEmergency))} away",
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
                    if (activeAmbulance != null)
                      IconButton(
                          icon: const Icon(Icons.gps_fixed, color: spotifyGreen),
                          onPressed: () => _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
                              LatLng(activeAmbulance!.latitude, activeAmbulance.longitude), 17)))
                  ]))),
        Positioned(
            top: 16,
            right: 16,
            child: Column(children: [
              FloatingActionButton.small(
                  heroTag: "rec",
                  backgroundColor: Colors.black.withOpacity(0.7),
                  onPressed: () => _mapController?.animateCamera(
                      CameraUpdate.newCameraPosition(CameraPosition(target: _myLocation, zoom: 16))),
                  child: const Icon(Icons.my_location, color: spotifyGreen)),
              if (point != null) ...[
                const SizedBox(height: 8),
                FloatingActionButton.small(
                    heroTag: "post",
                    backgroundColor: Colors.black.withOpacity(0.7),
                    onPressed: () => _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 16)),
                    child: const Icon(Icons.flag, color: Colors.green))
              ]
            ])),
      ],
    );
  }
}