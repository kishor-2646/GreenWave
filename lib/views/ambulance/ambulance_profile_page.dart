import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/auth_service.dart';
import '../auth/login.dart';

class AmbulanceProfilePage extends StatefulWidget {
  const AmbulanceProfilePage({super.key});

  @override
  State<AmbulanceProfilePage> createState() => _AmbulanceProfilePageState();
}

class _AmbulanceProfilePageState extends State<AmbulanceProfilePage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isEditing = false;
  bool _isSaving = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _hospitalController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _hospitalController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  void _handleLogout(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
      );
    }
  }

  Future<void> _updateProfile(String uid) async {
    setState(() => _isSaving = true);
    try {
      await _db.collection('users').doc(uid).update({
        'fullName': _nameController.text.trim(),
        'hospital': _hospitalController.text.trim(),
        'mobile': _mobileController.text.trim(),
      });

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile updated successfully"), backgroundColor: Color(0xFF22C55E))
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandGreen = Color(0xFF22C55E);
    const Color cardBg = Color(0xFF1E1E1E);
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("My Profile", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // EDIT/SAVE TOGGLE BUTTON
          if (!_isSaving)
            IconButton(
              icon: Icon(_isEditing ? Icons.check_circle : Icons.edit_note,
                  color: _isEditing ? brandGreen : Colors.white, size: 28),
              onPressed: () {
                if (_isEditing) {
                  _updateProfile(user!.uid);
                } else {
                  setState(() => _isEditing = true);
                }
              },
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _db.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: brandGreen));

          final userData = snapshot.data?.data() as Map<String, dynamic>?;

          // Sync controllers with DB data when not editing
          if (!_isEditing) {
            _nameController.text = userData?['fullName'] ?? "";
            _hospitalController.text = userData?['hospital'] ?? "";
            _mobileController.text = userData?['mobile'] ?? "";
          }

          final String driverId = user?.uid.substring(0, 8).toUpperCase() ?? "GW-AMB-01";

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildAvatar(brandGreen),
                const SizedBox(height: 24),

                // Name Section
                if (_isEditing)
                  _buildEditField(_nameController, "Full Name", Icons.person)
                else
                  Text(_nameController.text, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),

                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: brandGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text("ID: $driverId", style: const TextStyle(color: brandGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 40),

                // Editable Detail Sections
                _isEditing
                    ? Column(
                  children: [
                    _buildEditField(_hospitalController, "Affiliated Hospital", Icons.local_hospital),
                    const SizedBox(height: 16),
                    _buildEditField(_mobileController, "Contact Number", Icons.phone_android, keyboardType: TextInputType.phone),
                  ],
                )
                    : Column(
                  children: [
                    _buildProfileDetail(Icons.local_hospital, "Affiliated Hospital", _hospitalController.text, cardBg),
                    _buildProfileDetail(Icons.badge, "Employment Status", "On Duty (Verified)", cardBg),
                    _buildProfileDetail(Icons.phone_android, "Contact Info", _mobileController.text, cardBg),
                  ],
                ),

                const SizedBox(height: 40),

                if (_isSaving)
                  const CircularProgressIndicator(color: brandGreen)
                else
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleLogout(context),
                      icon: const Icon(Icons.logout_rounded, color: Colors.white),
                      label: const Text("SIGN OUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(Color brandGreen) {
    return Center(
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: brandGreen, width: 3)),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey[900],
              backgroundImage: const NetworkImage("https://images.unsplash.com/photo-1633332755192-727a05c4013d?w=200&auto=format&fit=crop"),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
              child: const Icon(Icons.verified, color: Colors.white, size: 20),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEditField(TextEditingController controller, String label, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: const Color(0xFF22C55E)),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white10)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF22C55E))),
      ),
    );
  }

  Widget _buildProfileDetail(IconData icon, String label, String value, Color bg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF22C55E), size: 22),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}