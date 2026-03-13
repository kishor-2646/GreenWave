import 'package:flutter/material.dart';
import 'sign_up.dart'; // 👈 Updated SignUpPage

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    const Color bgBlack = Color(0xFF121212);
    const Color cardGrey = Color(0xFF1E1E1E);
    const Color brandGreen = Color(0xFF22C55E);

    return Scaffold(
      backgroundColor: bgBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text(
                "Select Your Role",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choose how you want to access the system",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: ListView(
                  children: [
                    // 🚑 Ambulance Driver
                    _buildRoleCard(
                      context: context,
                      title: "Ambulance Driver",
                      description:
                      "Request traffic clearance and navigate to destinations with optimized routes",
                      buttonText: "Continue as Driver",
                      icon: Icons.medical_services_outlined,
                      cardColor: cardGrey,
                      accentColor: brandGreen,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpPage(role: "Ambulance Driver"),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // 🚓 Traffic Police
                    _buildRoleCard(
                      context: context,
                      title: "Traffic Police",
                      description:
                      "Receive real-time alerts and coordinate traffic clearance for emergency vehicles",
                      buttonText: "Continue as Officer",
                      icon: Icons.shield_outlined,
                      cardColor: cardGrey,
                      accentColor: brandGreen,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpPage(role: "Traffic Police"),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String description,
    required String buttonText,
    required IconData icon,
    required Color cardColor,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.black26,
            child: Icon(icon, color: accentColor, size: 30),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  buttonText,
                  style: TextStyle(
                      color: accentColor, fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: accentColor, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
