import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/services/auth_service.dart';
import 'ambulance_map_page.dart';
import 'ambulance_profile_page.dart';

class AmbulanceDashboard extends StatefulWidget {
  const AmbulanceDashboard({super.key});

  @override
  State<AmbulanceDashboard> createState() => _AmbulanceDashboardState();
}

class _AmbulanceDashboardState extends State<AmbulanceDashboard>
    with SingleTickerProviderStateMixin {
  final TextEditingController destinationController = TextEditingController();
  final String _googleApiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: "");

  List<dynamic> _suggestions = [];
  bool _isSearching = false;
  int _selectedCriticality = 3;

  final Map<int, Color> _criticalityColors = {
    1: const Color(0xFF22C55E), // Stable - Green
    2: const Color(0xFF84CC16), // Guarded - Lime
    3: const Color(0xFFEAB308), // Serious - Yellow
    4: const Color(0xFFF97316), // Severe - Orange
    5: const Color(0xFFEF4444), // Critical - Red
  };

  @override
  void initState() {
    super.initState();
    destinationController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    destinationController.removeListener(_onSearchChanged);
    destinationController.dispose();
    super.dispose();
  }

  String _getCriticalityName(int level) {
    switch (level) {
      case 1: return "STABLE";
      case 2: return "GUARDED";
      case 3: return "SERIOUS";
      case 4: return "SEVERE";
      case 5: return "CRITICAL";
      default: return "";
    }
  }

  void _onSearchChanged() async {
    final query = destinationController.text.trim();
    if (query.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    final String url = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_googleApiKey";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && mounted) setState(() => _suggestions = data['predictions']);
      }
    } catch (e) { debugPrint("Autocomplete error: $e"); }
  }

  Future<LatLng?> _getCoordsFromAddress(String address) async {
    final String url = "https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$_googleApiKey";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final loc = data['results'][0]['geometry']['location'];
          return LatLng(loc['lat'], loc['lng']);
        }
      }
    } catch (e) { debugPrint("Geocoding error: $e"); }
    return null;
  }

  void _handleEmergencyStart(String address) async {
    if (address.isEmpty) return;
    setState(() => _isSearching = true);
    LatLng? destination = await _getCoordsFromAddress(address);
    if (mounted) {
      setState(() => _isSearching = false);
      if (destination != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => AmbulanceMapPage(initialDestination: destination, criticality: _selectedCriticality)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandGreen = Color(0xFF22C55E);
    const Color cardBg = Color(0xFF1E1E1E);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Ambulance Dashboard", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: brandGreen, size: 28),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmbulanceProfilePage())),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- SECTION 1: HOSPITAL DESTINATION ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: brandGreen),
                      SizedBox(width: 10),
                      Text("Hospital Destination", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text("Enter Hospital or Location Address", style: TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: destinationController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "e.g., City General Hospital",
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.black,
                      prefixIcon: const Icon(Icons.search, color: brandGreen, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(color: const Color(0xFF262626), borderRadius: BorderRadius.circular(12)),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(_suggestions[index]['description'], style: const TextStyle(color: Colors.white, fontSize: 12)),
                          onTap: () {
                            destinationController.text = _suggestions[index]['description'];
                            setState(() => _suggestions = []);
                            _handleEmergencyStart(destinationController.text);
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSearching ? null : () => _handleEmergencyStart(destinationController.text),
                      style: ElevatedButton.styleFrom(backgroundColor: brandGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: _isSearching
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("🚨 START EMERGENCY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --- SECTION 2: TAP AND SELECT LOCATION (RESTORED) ---
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AmbulanceMapPage(criticality: _selectedCriticality))),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.map, color: brandGreen),
                        const SizedBox(width: 10),
                        const Text("Tap and select location", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.2), size: 16),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 80,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(15),
                        image: const DecorationImage(
                          image: NetworkImage("https://images.unsplash.com/photo-1524661135-423995f22d0b?q=80&w=500&auto=format&fit=crop"),
                          fit: BoxFit.cover,
                          opacity: 0.2,
                        ),
                      ),
                      child: const Center(child: Icon(Icons.touch_app, color: brandGreen, size: 30)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --- SECTION 3: PATIENT CRITICALITY (REVERTED TO OLD STYLE) ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.health_and_safety, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text("Patient Criticality", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text("Select complexity level to alert police teams", style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (index) {
                      int level = index + 1;
                      bool isSelected = _selectedCriticality == level;
                      Color color = _criticalityColors[level]!;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCriticality = level),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isSelected ? 55 : 45,
                          height: isSelected ? 55 : 45,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? color : color.withOpacity(0.3),
                              width: isSelected ? 3 : 1,
                            ),
                            boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)] : [],
                          ),
                          child: Center(
                            child: Text(
                              "$level",
                              style: TextStyle(
                                color: isSelected ? Colors.white : color.withOpacity(0.5),
                                fontWeight: FontWeight.bold,
                                fontSize: isSelected ? 20 : 16,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Stable", style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text(
                          _getCriticalityName(_selectedCriticality),
                          style: TextStyle(color: _criticalityColors[_selectedCriticality], fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)
                      ),
                      const Text("Critical", style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}