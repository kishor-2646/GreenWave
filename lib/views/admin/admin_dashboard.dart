import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/models/app_user.dart';
import '../../core/models/emergency.dart';
import '../../core/models/live_location.dart';
import '../../core/models/police_assignment.dart';
import '../../core/network/api_error.dart';
import '../../core/network/realtime_service.dart';
import '../../core/repositories/emergency_repository.dart';
import '../../core/repositories/location_repository.dart';
import '../../core/repositories/police_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/services/auth_service.dart';
import '../auth/login.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  late TabController _tabController;

  final LatLng _mapCenter = const LatLng(12.9716, 77.5946);

  // ---- dependencies ----
  late final RealtimeService _realtime;
  final UserRepository _userRepo = UserRepository();
  final EmergencyRepository _emergencyRepo = EmergencyRepository();
  final PoliceRepository _policeRepo = PoliceRepository();
  final LocationRepository _locationRepo = LocationRepository();

  // ---- state that mirrors the SERVER ----
  List<AppUser> _drivers = [];
  List<PoliceAssignment> _assignments = [];
  final Map<String, Emergency> _emergencies = {}; // id -> emergency (active + recent history)
  final Map<String, LiveLocation> _ambulances = {}; // ambulance user id -> last known position

  final Map<String, List<LatLng>> _polylineCache = {}; // key = emergency id

  // A unit counts as "online" if it reported a position this recently.
  static const Duration _onlineWindow = Duration(minutes: 5);
  Timer? _clock; // re-evaluates online/offline badges while nothing else changes

  StreamSubscription? _emergencySubscription;
  StreamSubscription? _ambulanceSubscription;
  StreamSubscription? _assignmentSubscription;
  StreamSubscription? _reconnectSubscription;

  // Uber-style marker descriptors
  BitmapDescriptor? _policeLogo;
  BitmapDescriptor? _ambulanceIdleLogo;
  BitmapDescriptor? _ambulanceEmergencyLogo;
  BitmapDescriptor? _junctionLogo;
  BitmapDescriptor? _destinationLogo;
  bool _logosLoaded = false;

  @override
  void initState() {
    super.initState();
    _realtime = context.read<RealtimeService>();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfessionalLogos();
    _startRealtime();
    _refreshFromServer();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _emergencySubscription?.cancel();
    _ambulanceSubscription?.cancel();
    _assignmentSubscription?.cancel();
    _reconnectSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ======================= data =======================

  void _startRealtime() {
    _emergencySubscription = _realtime.topic('/topic/emergencies').listen(_onEmergencyEvent);
    _ambulanceSubscription = _realtime.topic('/topic/ambulance-updates').listen(_onAmbulanceLocation);
    // A police officer picking a junction is rare, so we simply re-fetch the list.
    _assignmentSubscription = _realtime.topic('/topic/police-assignments').listen((_) => _refreshAssignments());
    _reconnectSubscription = _realtime.onConnected.listen((_) => _refreshFromServer());
  }

  Future<void> _refreshAssignments() async {
    final assignments = await safeCall(_policeRepo.getAssignments());
    if (!mounted || assignments == null) return;
    setState(() => _assignments = assignments);
  }

  Future<void> _refreshFromServer() async {
    final drivers = await safeCall(_userRepo.getByRole('AMBULANCE_DRIVER'));
    final assignments = await safeCall(_policeRepo.getAssignments());
    final history = await safeCall(_emergencyRepo.getHistory());
    final active = await safeCall(_emergencyRepo.getActive());
    final ambulances = await safeCall(_locationRepo.getAmbulances());
    if (!mounted) return;

    setState(() {
      if (drivers != null) _drivers = drivers;
      if (assignments != null) _assignments = assignments;

      if (history != null || active != null) {
        _emergencies.clear();
        // `...?x` spreads x only if it is not null. Active goes last so its fresher data wins.
        for (final e in [...?history, ...?active]) {
          _emergencies[e.id] = e;
        }
        _polylineCache.removeWhere((id, _) => !_emergencies.containsKey(id));
      }

      if (ambulances != null) {
        _ambulances.clear();
        for (final l in ambulances) {
          _ambulances[l.userId] = l;
        }
      }
    });
  }

  void _onEmergencyEvent(Map<String, dynamic> json) {
    if (!mounted) return;
    try {
      final event = EmergencyEvent.fromJson(json);
      // Ended emergencies stay in the map so the log keeps showing them as ENDED.
      setState(() => _emergencies[event.emergency.id] = event.emergency);
    } catch (e) {
      debugPrint('Bad emergency event: $e');
    }
  }

  void _onAmbulanceLocation(Map<String, dynamic> json) {
    if (!mounted) return;
    try {
      final loc = LiveLocation.fromJson(json);
      setState(() => _ambulances[loc.userId] = loc);
    } catch (e) {
      debugPrint('Bad location event: $e');
    }
  }

  // ======================= derived values =======================

  bool _isOnline(LiveLocation? loc) =>
      loc != null && DateTime.now().difference(loc.updatedAt) < _onlineWindow;

  Emergency? _activeFor(String ambulanceUserId) {
    for (final e in _emergencies.values) {
      if (e.isActive && e.ambulanceUserId == ambulanceUserId) return e;
    }
    return null;
  }

  List<Emergency> get _activeEmergencies => _emergencies.values.where((e) => e.isActive).toList();

  // Newest first.
  List<Emergency> get _logEntries =>
      _emergencies.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  List<LatLng>? _routePoints(Emergency e) {
    final encoded = e.encodedPolyline;
    if (encoded == null) return null;
    return _polylineCache.putIfAbsent(e.id, () => _decodePolyline(encoded));
  }

  void _locate(Emergency e) {
    final loc = _ambulances[e.ambulanceUserId];
    final target = loc != null
        ? LatLng(loc.latitude, loc.longitude)
        : LatLng(e.destinationLat, e.destinationLng);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
  }

  String _formatTime(DateTime t) {
    final l = t.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month} $h:$m';
  }

  Future<void> _logout() async {
    await context.read<AuthService>().signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  // ======================= markers (unchanged) =======================

  Future<void> _loadProfessionalLogos() async {
    try {
      final pLogo = await _createUberMarker(const Color(0xFF3B82F6), Icons.local_police);
      final aIdle = await _createUberMarker(Colors.grey, Icons.local_hospital);
      final aEmerg = await _createUberMarker(const Color(0xFFEF4444), Icons.emergency);
      final jLogo = await _createUberMarker(const Color(0xFF22C55E), Icons.flag);
      final dLogo = await _createUberMarker(const Color(0xFFFFCC00), Icons.place);

      if (mounted) {
        setState(() {
          _policeLogo = pLogo;
          _ambulanceIdleLogo = aIdle;
          _ambulanceEmergencyLogo = aEmerg;
          _junctionLogo = jLogo;
          _destinationLogo = dLogo;
          _logosLoaded = true;
        });
      }
    } catch (e) {
      debugPrint("SYSTEM_ERROR: Marker Load Failed: $e");
    }
  }

  Future<BitmapDescriptor> _createUberMarker(Color color, IconData icon) async {
    const int size = 65;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);

    final Paint borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.2, borderPaint);

    final Paint fillPaint = Paint()..color = color;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.8, fillPaint);

    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(fontSize: 28, fontFamily: icon.fontFamily, color: Colors.white, package: icon.fontPackage),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2));

    final ui.Image image = await pictureRecorder.endRecording().toImage(size, size);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  // ======================= UI =======================


  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181818),
        elevation: 0,
        title: const Text("GREENWAVE GLOBAL COMMAND",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
        actions: [
          const Icon(Icons.security, color: Color(0xFF1DB954)),
          const SizedBox(width: 20),
          IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.white70), onPressed: _logout),
          const SizedBox(width: 20),
        ],
      ),

      body: isMobile
          ? Column(
        children: [
          Expanded(
            flex: 5,
            child: !_logosLoaded
                ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF1DB954),
              ),
            )
                : _buildMap(),
          ),
          Expanded(
            flex: 6,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF181818),
                border: Border(
                  top: BorderSide(color: Colors.white10),
                ),
              ),
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF1DB954),
                    labelColor: const Color(0xFF1DB954),
                    unselectedLabelColor: Colors.white38,
                    labelStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.emergency_outlined, size: 18),
                        text: "LOGS",
                      ),
                      Tab(
                        icon: Icon(Icons.local_hospital, size: 18),
                        text: "DRIVERS",
                      ),
                      Tab(
                        icon: Icon(Icons.local_police, size: 18),
                        text: "POLICE",
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildIncidentsTab(),
                        _buildAmbulanceListTab(),
                        _buildPoliceJunctionTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      )
          : Row(
        children: [
          Expanded(
            flex: 7,
            child: !_logosLoaded
                ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF1DB954),
              ),
            )
                : _buildMap(),
          ),
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF181818),
                border: Border(
                  left: BorderSide(color: Colors.white10),
                ),
              ),
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF1DB954),
                    labelColor: const Color(0xFF1DB954),
                    unselectedLabelColor: Colors.white38,
                    labelStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.emergency_outlined, size: 18),
                        text: "LOGS",
                      ),
                      Tab(
                        icon: Icon(Icons.local_hospital, size: 18),
                        text: "DRIVERS",
                      ),
                      Tab(
                        icon: Icon(Icons.local_police, size: 18),
                        text: "POLICE",
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildIncidentsTab(),
                        _buildAmbulanceListTab(),
                        _buildPoliceJunctionTab(),
                      ],
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

  Widget _buildMap() {
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    // Ambulances: only units that reported recently, so there are no ghost markers.
    for (final loc in _ambulances.values) {
      if (!_isOnline(loc)) continue;
      final inEmergency = _activeFor(loc.userId) != null;
      markers.add(Marker(
        markerId: MarkerId("amb_${loc.userId}"),
        position: LatLng(loc.latitude, loc.longitude),
        icon: inEmergency
            ? (_ambulanceEmergencyLogo ?? BitmapDescriptor.defaultMarker)
            : (_ambulanceIdleLogo ?? BitmapDescriptor.defaultMarker),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        infoWindow: InfoWindow(title: loc.fullName),
      ));
    }

    // Active emergencies: destination marker plus the route, green where cleared.
    for (final e in _activeEmergencies) {
      markers.add(Marker(
        markerId: MarkerId("dest_${e.id}"),
        position: LatLng(e.destinationLat, e.destinationLng),
        icon: _destinationLogo ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: const InfoWindow(title: "Destination Hospital"),
      ));

      final points = _routePoints(e);
      if (points == null || points.isEmpty) continue;

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
        polylines.add(Polyline(
            polylineId: PolylineId("${e.id}_p"), points: points, color: Colors.purpleAccent, width: 6));
      } else {
        int splitIdx = 0;
        double minD = double.infinity;
        for (int i = 0; i < points.length; i++) {
          final d = Geolocator.distanceBetween(
              points[i].latitude, points[i].longitude, split.latitude, split.longitude);
          if (d < minD) {
            minD = d;
            splitIdx = i;
          }
        }
        polylines.add(Polyline(
            polylineId: PolylineId("${e.id}_cl"),
            points: points.sublist(0, splitIdx + 1),
            color: const Color(0xFF22C55E),
            width: 8));
        polylines.add(Polyline(
            polylineId: PolylineId("${e.id}_rem"),
            points: points.sublist(splitIdx),
            color: Colors.purpleAccent,
            width: 6));
      }
    }

    // Police: a badge and a flag at each assigned junction.
    for (final a in _assignments) {
      final pos = LatLng(a.latitude, a.longitude);
      markers.add(Marker(
        markerId: MarkerId("pol_${a.userId}"),
        position: pos,
        icon: _policeLogo ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: a.officerName, snippet: a.junctionName),
      ));
      markers.add(Marker(
        markerId: MarkerId("junc_${a.userId}"),
        position: pos,
        icon: _junctionLogo ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
      ));
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 13),
      onMapCreated: (c) => _mapController = c,
      markers: markers,
      polylines: polylines,
      myLocationButtonEnabled: false,
      style: null,
    );
  }

  Widget _buildIncidentsTab() {
    final entries = _logEntries;
    return Column(
      children: [
        Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.black26,
            child: Text("EMERGENCY LOGS · ${_activeEmergencies.length} ACTIVE",
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text("No emergencies yet", style: TextStyle(color: Colors.white30)))
              : ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) => _buildLogItem(entries[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildAmbulanceListTab() {
    return Column(
      children: [
        Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.black26,
            child: const Text("REGISTERED DRIVERS",
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: _drivers.isEmpty
              ? const Center(child: Text("No drivers found", style: TextStyle(color: Colors.white30)))
              : ListView.builder(
            itemCount: _drivers.length,
            itemBuilder: (context, index) {
              final driver = _drivers[index];
              final loc = _ambulances[driver.id];
              final isOnline = _isOnline(loc);
              final isEmergency = _activeFor(driver.id) != null;
              return ListTile(
                onTap: loc == null
                    ? null
                    : () => _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(LatLng(loc.latitude, loc.longitude), 16)),
                leading: CircleAvatar(
                    backgroundColor: isEmergency ? Colors.redAccent.withOpacity(0.2) : Colors.white10,
                    child: Icon(Icons.local_hospital,
                        color: isEmergency ? Colors.redAccent : Colors.grey, size: 18)),
                title: Text(driver.fullName,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text(driver.hospital ?? "Not Assigned",
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: isOnline
                    ? const Icon(Icons.online_prediction, color: Colors.greenAccent, size: 18)
                    : const Icon(Icons.cloud_off, color: Colors.white10, size: 16),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPoliceJunctionTab() {
    return Column(
      children: [
        Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.black26,
            child: const Text("POLICE DEPLOYMENTS",
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: _assignments.isEmpty
              ? const Center(child: Text("No officers on duty", style: TextStyle(color: Colors.white30)))
              : ListView.builder(
            itemCount: _assignments.length,
            itemBuilder: (context, index) {
              final a = _assignments[index];
              return ListTile(
                onTap: () => _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(LatLng(a.latitude, a.longitude), 16)),
                leading: const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.local_police, color: Colors.white, size: 18)),
                title: Text(a.junctionName,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text(a.officerName,
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Emergency e) {
    final crit = e.criticality;
    final color = _getCritColor(crit);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(e.isActive ? 0.5 : 0.15))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "PRIORITY $crit",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                e.isActive ? "ACTIVE" : "ENDED",
                style: TextStyle(
                  color: e.isActive ? Colors.greenAccent : Colors.white30,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(e.ambulanceName,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text("${_formatTime(e.startedAt)} · ${e.clearedJunctions.length} junction(s) cleared",
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => _locate(e),
            child: const Text("LOCATE UNIT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Color _getCritColor(int level) {
    if (level >= 5) return Colors.redAccent;
    if (level >= 3) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  // --- Stable standard decoder (unchanged) ---
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        if (index >= len) return points;
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

  final String _darkMapStyle = '''[{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"feature": "administrative","elementType": "geometry","stylers": [{"color": "#757575"}]},{"feature": "water","elementType": "geometry","stylers": [{"color": "#000000"}]}]''';
}