import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
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
  bool _locationPermissionGranted = false;

  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color darkCard = Color(0xFF282828);
  static const Color bgBlack = Color(0xFF121212);
  static const Color emergencyPurple = Colors.purpleAccent;

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
  String? _lastAnnouncedJunction;
  bool _isSpeaking = false;

  final Map<String, List<LatLng>> _polylineCache = {};
  final Set<String> _announcedAmbulances = {};

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription? _ambulanceSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermissionsAndInit();
    _startAmbulanceListener();
  }

  @override
  void dispose() {
    _ambulanceSubscription?.cancel();
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionsAndInit() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      if (mounted) setState(() => _locationPermissionGranted = true);
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));

      Geolocator.getPositionStream().listen((Position position) {
        if (mounted) setState(() => _myLocation = LatLng(position.latitude, position.longitude));
      });
    }
  }

  void _startAmbulanceListener() {
    _ambulanceSubscription?.cancel();
    _ambulanceSubscription = _db
        .collection('ambulanceLocations')
        .where('status', isEqualTo: 'emergency')
        .snapshots()
        .listen((snapshot) {

      if (snapshot.docs.isEmpty) {
        _announcedAmbulances.clear();
        _polylineCache.clear();
        _lastAnnouncedJunction = null;
        return;
      }

      if (_junctionLocation == null) return;

      final matchingAmbs = snapshot.docs.where((doc) {
        return _isAmbulanceRelevant(doc.data(), doc.id);
      }).toList();

      if (matchingAmbs.isNotEmpty) {
        _processVoiceUpdates(matchingAmbs.first.data());
      }
    });
  }

  bool _isAmbulanceRelevant(Map<String, dynamic> data, String id) {
    if (_junctionLocation == null) return false;
    bool pathCollision = _isPathColliding(data['encodedPolyline'], _junctionLocation, id);
    if (pathCollision) return true;
    if (data['latitude'] != null) {
      double dist = Geolocator.distanceBetween(data['latitude'], data['longitude'], _junctionLocation!.latitude, _junctionLocation!.longitude);
      if (dist < 5000) return true;
    }
    return false;
  }

  Future<void> _markTrafficCleared(String ambUid) async {
    if (_myAssignedJunction == null || _junctionLocation == null) return;
    try {
      final key = _myAssignedJunction!.replaceAll('.', '_');
      await _db.collection('ambulanceLocations').doc(ambUid).set({
        'clearedJunctions': {
          key: {
            'name': _myAssignedJunction,
            'lat': _junctionLocation!.latitude,
            'lng': _junctionLocation!.longitude,
            'clearedAt': FieldValue.serverTimestamp(),
          }
        }
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cleared - Route turning Green for Ambulance"), backgroundColor: spotifyGreen, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) { debugPrint("Clearance Error: $e"); }
  }

  Future<void> _unmarkTrafficCleared(String ambUid) async {
    if (_myAssignedJunction == null) return;
    try {
      final key = _myAssignedJunction!.replaceAll('.', '_');
      await _db.collection('ambulanceLocations').doc(ambUid).update({
        'clearedJunctions.$key': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Clearance reverted"), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) { debugPrint("Unmark Error: $e"); }
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
    setState(() => _isSpeaking = true);
    final String apiKey = dotenv.get('GEMINI_API_KEY', fallback: dotenv.get('GOOGLE_MAPS_API_KEY', fallback: ""));
    final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$apiKey");
    final payload = {
      "contents": [{ "parts": [{ "text": message }] }],
      "generationConfig": {
        "responseModalities": ["AUDIO"],
        "speechConfig": { "voiceConfig": { "prebuiltVoiceConfig": { "voiceName": "Aoede" } } }
      }
    };
    try {
      final response = await http.post(url, body: jsonEncode(payload), headers: {"Content-Type": "application/json"});
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final audioPart = result['candidates']?[0]?['content']?['parts']?[0]?['inlineData'];
        if (audioPart != null) {
          final String base64Data = audioPart['data'];
          final wavBytes = _createWavHeader(base64Decode(base64Data), 24000);
          await _audioPlayer.play(BytesSource(wavBytes));
        }
      }
    } catch (e) { debugPrint("TTS Error: $e"); } finally { if (mounted) setState(() => _isSpeaking = false); }
  }

  void _processVoiceUpdates(Map<String, dynamic> data) {
    if (_myAssignedJunction == null) return;
    final String ambId = data['uid'] ?? 'unknown';
    if (!_announcedAmbulances.contains(ambId)) {
      _announcedAmbulances.add(ambId);
      _speakGemini("Alert. An ambulance is incoming on your junction path. Stay alerted and updated as it moves near.");
      return;
    }
    final currentJunction = data['nearestJunction']?.toString();
    if (currentJunction == null || currentJunction == _lastAnnouncedJunction) return;
    final List path = data['pathJunctions'] ?? [];
    int myIdx = path.indexWhere((j) => _fuzzyMatch(j.toString(), _myAssignedJunction!));
    int ambIdx = path.indexWhere((j) => _fuzzyMatch(j.toString(), currentJunction));
    if (myIdx != -1 && ambIdx != -1 && ambIdx <= myIdx) {
      _lastAnnouncedJunction = currentJunction;
      int remaining = myIdx - ambIdx;
      String eta = _getEtaForJunction(data['junctionEtas'], _myAssignedJunction);
      String voiceMessage = remaining == 0
          ? "Alert. The ambulance has reached your junction. Clear the signals immediately."
          : "Update. The ambulance has crossed $currentJunction. It is $remaining junctions away. Estimated arrival is $eta.";
      _speakGemini(voiceMessage);
    }
  }

  void _updateDutyJunction(String junctionName) {
    final location = _junctionData[junctionName];
    setState(() {
      _myAssignedJunction = junctionName;
      _junctionLocation = location;
      _lastAnnouncedJunction = null;
      _announcedAmbulances.clear();
      _polylineCache.clear();
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
    if (_mapController != null && location != null) _fitMapToPoints([_myLocation, location]);
    _startAmbulanceListener();
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

  bool _isPathColliding(String? encodedPolyline, LatLng? junctionLoc, String ambId) {
    if (encodedPolyline == null || junctionLoc == null) return false;
    try {
      final List<LatLng> pathPoints = _polylineCache[ambId] ?? _decodePolyline(encodedPolyline);
      _polylineCache[ambId] = pathPoints;
      for (int i = 0; i < pathPoints.length; i += 5) {
        double distance = Geolocator.distanceBetween(pathPoints[i].latitude, pathPoints[i].longitude, junctionLoc.latitude, junctionLoc.longitude);
        if (distance < 1500) return true;
      }
    } catch (e) { debugPrint("Decoding error: $e"); }
    return false;
  }

  bool _fuzzyMatch(String target, String source) {
    String t = target.toLowerCase(); String s = source.toLowerCase();
    if (t.contains(s) || s.contains(t)) return true;
    final stopWords = {'signal', 'junction', 'circle', 'flyover', 'road', 'rd', 'main', 'block', 'onto', 'at'};
    List<String> keywords = s.split(' ').where((w) => w.length >= 3 && !stopWords.contains(w)).toList();
    return keywords.isNotEmpty && keywords.every((k) => t.contains(k));
  }

  String _getEtaForJunction(Map<String, dynamic>? etas, String? myJunction) {
    if (etas == null || myJunction == null) return "Calculating...";
    try {
      String? matchingKey = etas.keys.firstWhere((k) => _fuzzyMatch(k, myJunction), orElse: () => "");
      return (matchingKey != null && matchingKey.isNotEmpty) ? etas[matchingKey] : "Calculating...";
    } catch (e) { return "Calculating..."; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Traffic Control Portal', style: TextStyle(fontSize: 18)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_input_component, color: spotifyGreen),
            onSelected: _updateDutyJunction,
            itemBuilder: (context) => _junctionData.keys.map((j) => PopupMenuItem(value: j, child: Text(j, style: const TextStyle(fontSize: 13)))).toList(),
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
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16), color: Colors.white.withOpacity(0.05),
      child: Row(
        children: [
          Icon(Icons.radar, size: 14, color: _myAssignedJunction == null ? Colors.orange : spotifyGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                _myAssignedJunction == null
                    ? "⚠️ SELECT YOUR JUNCTION (TOP-RIGHT)"
                    : "SYSTEM ACTIVE: Scanning Path for Duty at $_myAssignedJunction",
                style: TextStyle(color: _myAssignedJunction == null ? Colors.orange : Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600)
            ),
          ),
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
          return _isAmbulanceRelevant(data, doc.id);
        }).toList();

        if (relevantDocs.isEmpty) return const Center(child: Text("Waiting for incoming ambulances...", style: TextStyle(color: Colors.white30)));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: relevantDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String ambUid = data['uid'] ?? doc.id;
            double dist = _junctionLocation != null ? Geolocator.distanceBetween(data['latitude'], data['longitude'], _junctionLocation!.latitude, _junctionLocation!.longitude) : 10000;
            bool isNear = dist < 1500;
            String eta = _getEtaForJunction(data['junctionEtas'], _myAssignedJunction);

            bool isCleared = false;
            if (data['clearedJunctions'] != null && _myAssignedJunction != null) {
              isCleared = data['clearedJunctions'][_myAssignedJunction!.replaceAll('.', '_')] != null;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: isCleared ? spotifyGreen.withOpacity(0.2) : (isNear ? Colors.red.withOpacity(0.3) : darkCard), borderRadius: BorderRadius.circular(15), border: Border.all(color: isCleared ? spotifyGreen : (isNear ? Colors.red : Colors.white10), width: 2)),
              child: Column(
                children: [
                  Row(children: [Icon(Icons.local_hospital, color: isNear ? Colors.white : (isCleared ? spotifyGreen : Colors.red)), const SizedBox(width: 10), Expanded(child: Text(isCleared ? "TRAFFIC CLEARED" : "INCOMING AMBULANCE", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]),
                  const Divider(color: Colors.white10, height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("ETA to your post:", style: TextStyle(color: Colors.white70, fontSize: 13)), Text(eta, style: TextStyle(color: spotifyGreen, fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: ElevatedButton(onPressed: () { _tabController.animateTo(1); _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(data['latitude'], data['longitude']), 17)); }, style: ElevatedButton.styleFrom(backgroundColor: spotifyGreen, foregroundColor: Colors.black), child: const Text("MAP"))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: ElevatedButton(
                              onPressed: () => isCleared ? _unmarkTrafficCleared(ambUid) : _markTrafficCleared(ambUid),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCleared ? Colors.white10 : spotifyGreen,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(isCleared ? "UNDO" : "CLEAR TRAFFIC")
                          )
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMap() {
    return StreamBuilder<QuerySnapshot>(
        stream: _db.collection('ambulanceLocations').where('status', isEqualTo: 'emergency').snapshots(),
        builder: (context, snapshot) {
          Set<Marker> markers = {Marker(markerId: const MarkerId("police_me"), position: _myLocation, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue))};
          Set<Polyline> polylines = {};
          Map<String, dynamic>? activeAmb;
          if (_junctionLocation != null) markers.add(Marker(markerId: const MarkerId("assigned_junction"), position: _junctionLocation!, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)));

          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final String id = data['uid'] ?? doc.id;
              if (_isAmbulanceRelevant(data, id)) {
                activeAmb = data;
                markers.add(Marker(markerId: MarkerId(doc.id), position: LatLng(data['latitude'], data['longitude']), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)));

                if (data['encodedPolyline'] != null) {
                  final List<LatLng> points = _polylineCache[id] ?? _decodePolyline(data['encodedPolyline']);
                  _polylineCache[id] = points;

                  LatLng? splitPoint;
                  if (data['clearedJunctions'] != null) {
                    double furthestD = -1;
                    data['clearedJunctions'].forEach((k, v) {
                      if (v['lat'] != null && v['lng'] != null) {
                        double d = Geolocator.distanceBetween(points.first.latitude, points.first.longitude, v['lat'], v['lng']);
                        if (d > furthestD) { furthestD = d; splitPoint = LatLng(v['lat'], v['lng']); }
                      }
                    });
                  }

                  if (splitPoint == null) {
                    polylines.add(Polyline(polylineId: PolylineId("${doc.id}_poly"), points: points, color: emergencyPurple, width: 6));
                  } else {
                    int splitIdx = 0; double minD = 1000000;
                    for (int i = 0; i < points.length; i++) {
                      double d = Geolocator.distanceBetween(points[i].latitude, points[i].longitude, splitPoint!.latitude, splitPoint!.longitude);
                      if (d < minD) { minD = d; splitIdx = i; }
                    }
                    polylines.add(Polyline(polylineId: PolylineId("${doc.id}_cleared"), points: points.sublist(0, splitIdx + 1), color: spotifyGreen, width: 8));
                    polylines.add(Polyline(polylineId: PolylineId("${doc.id}_rem"), points: points.sublist(splitIdx), color: emergencyPurple, width: 6));
                  }
                }
              }
            }
          }
          return Stack(
            children: [
              GoogleMap(initialCameraPosition: CameraPosition(target: _myLocation, zoom: 14), onMapCreated: (c) => _mapController = c, myLocationEnabled: _locationPermissionGranted, myLocationButtonEnabled: false, markers: markers, polylines: polylines, gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{ Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()) }),
              if (activeAmb != null)
                Positioned(
                  bottom: 20, left: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: darkCard, borderRadius: BorderRadius.circular(15), border: Border.all(color: spotifyGreen, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 4))]),
                    child: Row(children: [Icon(_isSpeaking ? Icons.volume_up : Icons.timer, color: spotifyGreen), const SizedBox(width: 12), Expanded(child: Text("Ambulance arriving in ${_getEtaForJunction(activeAmb['junctionEtas'], _myAssignedJunction)}", style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.gps_fixed, color: spotifyGreen), onPressed: () => _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(activeAmb!['latitude'], activeAmb['longitude']), 17)))]),
                  ),
                ),
              Positioned(top: 16, right: 16, child: Column(children: [FloatingActionButton.small(heroTag: "rec", backgroundColor: Colors.black.withOpacity(0.7), onPressed: () => _mapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: _myLocation, zoom: 16))), child: const Icon(Icons.my_location, color: spotifyGreen)), if (_junctionLocation != null) ...[const SizedBox(height: 8), FloatingActionButton.small(heroTag: "post", backgroundColor: Colors.black.withOpacity(0.7), onPressed: () => _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_junctionLocation!, 16)), child: const Icon(Icons.flag, color: Colors.green))]])),
            ],
          );
        }
    );
  }
}