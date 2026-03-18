import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:geolocator/geolocator.dart';
import '../../core/services/auth_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  GoogleMapController? _mapController;
  late TabController _tabController;

  final LatLng _mapCenter = const LatLng(12.9716, 77.5946);

  // Uber-Style Marker descriptors
  BitmapDescriptor? _policeLogo;
  BitmapDescriptor? _ambulanceIdleLogo;
  BitmapDescriptor? _ambulanceEmergencyLogo;
  BitmapDescriptor? _junctionLogo;
  BitmapDescriptor? _destinationLogo;
  bool _logosLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfessionalLogos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181818),
        elevation: 0,
        title: const Text("GREENWAVE GLOBAL COMMAND", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
        actions: [
          const Icon(Icons.security, color: Color(0xFF1DB954)),
          const SizedBox(width: 20),
          IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.white70), onPressed: () => authService.signOut()),
          const SizedBox(width: 20),
        ],
      ),
      body: Row(
        children: [
          /// GLOBAL MAP AREA (70%)
          Expanded(
            flex: 7,
            child: !_logosLoaded
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)))
                : StreamBuilder<QuerySnapshot>(
              stream: _db.collection('ambulanceLocations').snapshots(),
              builder: (context, ambSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: _db.collection('policeLocations').snapshots(),
                  builder: (context, polSnapshot) {
                    Set<Marker> markers = {};
                    Set<Polyline> polylines = {};

                    if (ambSnapshot.hasData) {
                      for (var doc in ambSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final bool isEmergency = data['status'] == 'emergency';
                        final double? lat = data['latitude']?.toDouble();
                        final double? lng = data['longitude']?.toDouble();

                        if (lat != null && lng != null && lat != 0) {
                          final LatLng pos = LatLng(lat, lng);

                          markers.add(Marker(
                            markerId: MarkerId("amb_${doc.id}"),
                            position: pos,
                            icon: isEmergency ? (_ambulanceEmergencyLogo ?? BitmapDescriptor.defaultMarker) : (_ambulanceIdleLogo ?? BitmapDescriptor.defaultMarker),
                            anchor: const Offset(0.5, 0.5),
                            flat: true,
                            infoWindow: InfoWindow(title: "Unit ${doc.id.substring(0,4)}"),
                          ));

                          if (isEmergency) {
                            if (data['destLat'] != null && data['destLng'] != null && data['destLat'] != 0) {
                              markers.add(Marker(
                                markerId: MarkerId("dest_${doc.id}"),
                                position: LatLng(data['destLat'], data['destLng']),
                                icon: _destinationLogo ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                                infoWindow: const InfoWindow(title: "Destination Hospital"),
                              ));
                            }

                            if (data['encodedPolyline'] != null) {
                              final List<LatLng> points = _decodePolyline(data['encodedPolyline']);
                              if (points.isNotEmpty) {
                                LatLng? splitPoint;
                                if (data['clearedJunctions'] != null) {
                                  double furthestD = -1;
                                  (data['clearedJunctions'] as Map).forEach((k, v) {
                                    if (v['lat'] != null && v['lng'] != null) {
                                      double d = Geolocator.distanceBetween(points.first.latitude, points.first.longitude, v['lat'], v['lng']);
                                      if (d > furthestD) { furthestD = d; splitPoint = LatLng(v['lat'], v['lng']); }
                                    }
                                  });
                                }

                                if (splitPoint == null) {
                                  polylines.add(Polyline(polylineId: PolylineId("${doc.id}_p"), points: points, color: Colors.purpleAccent, width: 6));
                                } else {
                                  int splitIdx = 0; double minD = 1000000;
                                  for (int i = 0; i < points.length; i++) {
                                    double d = Geolocator.distanceBetween(points[i].latitude, points[i].longitude, splitPoint!.latitude, splitPoint!.longitude);
                                    if (d < minD) { minD = d; splitIdx = i; }
                                  }
                                  polylines.add(Polyline(polylineId: PolylineId("${doc.id}_cl"), points: points.sublist(0, splitIdx + 1), color: const Color(0xFF22C55E), width: 8));
                                  polylines.add(Polyline(polylineId: PolylineId("${doc.id}_rem"), points: points.sublist(splitIdx), color: Colors.purpleAccent, width: 6));
                                }
                              }
                            }
                          }
                        }
                      }
                    }

                    if (polSnapshot.hasData) {
                      for (var doc in polSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        if (data['junctionLat'] != null && data['junctionLat'] != 0) {
                          final LatLng juncPos = LatLng(data['junctionLat'], data['junctionLng']);
                          markers.add(Marker(markerId: MarkerId("pol_${doc.id}"), position: juncPos, icon: _policeLogo ?? BitmapDescriptor.defaultMarker, anchor: const Offset(0.5, 0.5)));
                          markers.add(Marker(markerId: MarkerId("junc_${doc.id}"), position: juncPos, icon: _junctionLogo ?? BitmapDescriptor.defaultMarker, anchor: const Offset(0.5, 0.5)));
                        }
                      }
                    }

                    return GoogleMap(
                      initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 13),
                      onMapCreated: (c) => _mapController = c,
                      markers: markers,
                      polylines: polylines,
                      myLocationButtonEnabled: false,
                      style: _darkMapStyle,
                    );
                  },
                );
              },
            ),
          ),

          /// SIDE PANEL
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFF181818), border: Border(left: BorderSide(color: Colors.white10))),
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF1DB954),
                    labelColor: const Color(0xFF1DB954),
                    unselectedLabelColor: Colors.white38,
                    labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(icon: Icon(Icons.emergency_outlined, size: 18), text: "LOGS"),
                      Tab(icon: Icon(Icons.local_hospital, size: 18), text: "DRIVERS"),
                      Tab(icon: Icon(Icons.local_police, size: 18), text: "POLICE"),
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

  Widget _buildIncidentsTab() {
    return Column(
      children: [
        Container(padding: const EdgeInsets.all(16), width: double.infinity, color: Colors.black26, child: const Text("ACTIVE EMERGENCY LOGS", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('emergency_alerts').orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final alert = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                  return _buildLogItem(alert, alert['criticality'] ?? 3);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAmbulanceListTab() {
    return Column(
      children: [
        Container(padding: const EdgeInsets.all(16), width: double.infinity, color: Colors.black26, child: const Text("REGISTERED DRIVERS", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('users').where('role', isEqualTo: 'Ambulance Driver').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final userData = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                  final String uid = userData['uid'];
                  return StreamBuilder<DocumentSnapshot>(
                    stream: _db.collection('ambulanceLocations').doc(uid).snapshots(),
                    builder: (context, locSnapshot) {
                      final locData = locSnapshot.data?.data() as Map<String, dynamic>?;
                      final bool isEmergency = locData?['status'] == 'emergency';
                      final bool isOnline = locSnapshot.data?.exists ?? false;
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: isEmergency ? Colors.redAccent.withOpacity(0.2) : Colors.white10, child: Icon(Icons.local_hospital, color: isEmergency ? Colors.redAccent : Colors.grey, size: 18)),
                        title: Text(userData['fullName'] ?? "Driver", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(userData['hospital'] ?? "Not Assigned", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        trailing: isOnline ? const Icon(Icons.online_prediction, color: Colors.greenAccent, size: 18) : const Icon(Icons.cloud_off, color: Colors.white10, size: 16),
                      );
                    },
                  );
                },
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
        Container(padding: const EdgeInsets.all(16), width: double.infinity, color: Colors.black26, child: const Text("POLICE DEPLOYMENTS", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('policeLocations').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                  return ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.local_police, color: Colors.white, size: 18)),
                    title: Text(data['assignedJunction'] ?? "Stationed", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text("ID: ${snapshot.data!.docs[index].id.substring(0, 8)}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> alert, int crit) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF242424), borderRadius: BorderRadius.circular(12), border: Border.all(color: _getCritColor(crit).withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.circle, size: 8, color: _getCritColor(crit)),
            const SizedBox(width: 8),
            Text("PRIORITY $crit", style: TextStyle(color: _getCritColor(crit), fontWeight: FontWeight.bold, fontSize: 10)),
            const Spacer(),
            const Icon(Icons.bolt, color: Colors.white10, size: 12),
          ]),
          const SizedBox(height: 8),
          Text(alert['message'] ?? "Emergency active", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 36), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () { if (alert['lat'] != null) _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(alert['lat'], alert['lng']), 16)); },
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

  // --- REWRITTEN: Stable Standard Decoder ---
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

  final String _darkMapStyle = '''[{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"feature": "administrative","elementType": "geometry","stylers": [{"color": "#757575"}]},{"feature": "water","elementType": "geometry","stylers": [{"color": "#000000"}]}]''';
}