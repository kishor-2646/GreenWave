import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/services/auth_service.dart';
import 'ambulance/map_page.dart';


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
  bool alertSent = false;
  late AnimationController blinkController;

  @override
  void initState() {
    super.initState();
    blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    destinationController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    blinkController.dispose();
    destinationController.removeListener(_onSearchChanged);
    destinationController.dispose();
    super.dispose();
  }

  // Google Places Autocomplete API Call
  void _onSearchChanged() async {
    if (destinationController.text.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    final String url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${destinationController.text}&key=$_googleApiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _suggestions = data['predictions'];
          });
        }
      }
    } catch (e) {
      debugPrint("Autocomplete error: $e");
    }
  }

  // Convert Address to Coordinates using Geocoding API
  Future<LatLng?> _getCoordsFromAddress(String address) async {
    final String url =
        "https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$_googleApiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final loc = data['results'][0]['geometry']['location'];
          return LatLng(loc['lat'], loc['lng']);
        }
      }
    } catch (e) {
      debugPrint("Geocoding error: $e");
    }
    return null;
  }

  void _handleEmergencyStart(String address) async {
    setState(() => _isSearching = true);

    LatLng? destination = await _getCoordsFromAddress(address);

    if (mounted) {
      setState(() => _isSearching = false);
      if (destination != null) {
        setState(() => alertSent = true);
        // Pass coordinates to Map Page
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AmbulanceMapPage(initialDestination: destination)
            )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not find location coordinates."))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandGreen = Color(0xFF22C55E);
    const Color cardBg = Color(0xFF1E1E1E);
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Ambulance Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await authService.signOut();
              if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
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
                  const SizedBox(height: 16),
                  const Text("Enter Hospital or Location Address", style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 12),

                  // Search Input with Smart Suggestions
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
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: brandGreen)),
                    ),
                  ),

                  // Smart Suggestions List
                  if (_suggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(_suggestions[index]['description'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () {
                              destinationController.text = _suggestions[index]['description'];
                              setState(() => _suggestions = []);
                              _handleEmergencyStart(destinationController.text);
                            },
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSearching ? null : () => _handleEmergencyStart(destinationController.text),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: brandGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      child: _isSearching
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("🚨 START EMERGENCY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tap and Select Widget
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmbulanceMapPage())),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.map_rounded, color: brandGreen),
                        SizedBox(width: 10),
                        Text("Tap and select location", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Spacer(),
                        Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Open the live map to precisely pick your destination hospital by tapping.",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(15),
                        image: const DecorationImage(
                          image: NetworkImage("https://images.unsplash.com/photo-1524661135-423995f22d0b?q=80&w=500&auto=format&fit=crop"),
                          fit: BoxFit.cover,
                          opacity: 0.3,
                        ),
                      ),
                      child: const Icon(Icons.touch_app, color: brandGreen, size: 40),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}