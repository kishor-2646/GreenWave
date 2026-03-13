import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Services & Navigation
import '../core/services/auth_service.dart';
import 'ambulance/map_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    const Color bgBlack = Color(0xFF000000);
    const Color cardBg = Color(0xFF1E1E1E);
    const Color brandGreen = Color(0xFF22C55E);

    // Access the auth service via Provider
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      backgroundColor: bgBlack,

      // AppBar
      appBar: AppBar(
        backgroundColor: bgBlack,
        elevation: 0,
        title: const Text(
          "Dashboard",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Text
            const Text(
              "Welcome 👋",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "System status overview",
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 20),

            // Status Cards
            Row(
              children: [
                _statusCard(
                  title: "Active Signals",
                  value: "12",
                  icon: Icons.traffic,
                  color: brandGreen,
                  cardBg: cardBg,
                ),
                const SizedBox(width: 12),
                _statusCard(
                  title: "Ambulances",
                  value: "5",
                  icon: Icons.local_hospital,
                  color: Colors.orange,
                  cardBg: cardBg,
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                _statusCard(
                  title: "Alerts",
                  value: "2",
                  icon: Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  cardBg: cardBg,
                ),
                const SizedBox(width: 12),
                _statusCard(
                  title: "Response Time",
                  value: "4.2s",
                  icon: Icons.timer,
                  color: Colors.blueAccent,
                  cardBg: cardBg,
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Quick Actions
            const Text(
              "Quick Actions",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            _actionTile(
              icon: Icons.map,
              title: "View Live Map",
              subtitle: "Track ambulances & traffic",
              color: brandGreen,
              cardBg: cardBg,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AmbulanceMapPage()),
                );
              },
            ),
            _actionTile(
              icon: Icons.settings,
              title: "System Settings",
              subtitle: "Traffic & signal control",
              color: Colors.grey,
              cardBg: cardBg,
              onTap: () {
                // Future implementation for settings
              },
            ),
            _actionTile(
              icon: Icons.analytics,
              title: "Reports",
              subtitle: "Daily & monthly analytics",
              color: Colors.blueAccent,
              cardBg: cardBg,
              onTap: () {
                // Future implementation for analytics
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Widgets ----------------

  static Widget _statusCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color cardBg,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color cardBg,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}