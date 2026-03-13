import 'package:flutter/material.dart';
import 'package:green_wave/views/ambulance_dashboard.dart';
import 'package:provider/provider.dart';

// Services & Navigation
import '../core/services/auth_service.dart';
import 'police/police_map_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    _handleRoleRouting();
  }

  /// Checks the role and redirects the user to their specific dashboard
  void _handleRoleRouting() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final uid = authService.currentUser?.uid;

    if (uid != null) {
      final role = await authService.getUserRole(uid);
      if (mounted) {
        if (role == "Ambulance Driver") {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AmbulanceDashboard())
          );
        } else if (role == "Traffic Police") {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const PoliceMapPage())
          );
        } else {
          // Fallback or generic view if role is missing
          setState(() {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF22C55E)),
      ),
    );
  }
}