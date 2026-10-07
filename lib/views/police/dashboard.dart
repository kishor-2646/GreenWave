import 'package:flutter/material.dart';
import 'package:green_wave/views/ambulance/ambulance_dashboard.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import 'police_map_page.dart';
import '../admin/admin_dashboard.dart';

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

  void _handleRoleRouting() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

    if (user != null) {
      final role = user.role;

      if (mounted) {
        if (role == "AMBULANCE_DRIVER") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const AmbulanceDashboard(),
            ),
          );
        } else if (role == "POLICE") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const PoliceMapPage(),
            ),
          );
        } else if (role == "ADMIN") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminDashboard(),
            ),
          );
        } else {
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
        child: CircularProgressIndicator(
          color: Color(0xFF22C55E),
        ),
      ),
    );
  }
}