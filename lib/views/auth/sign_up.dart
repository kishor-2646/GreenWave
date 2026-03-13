import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import 'login.dart';

class SignUpPage extends StatefulWidget {
  final String role;

  const SignUpPage({super.key, required this.role});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  String? uploadedFileName;
  bool isPasswordHidden = true;
  bool _isLoading = false;

  final RegExp passwordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&]).{8,}$');

  Future<void> pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        uploadedFileName = result.files.single.name;
      });
    }
  }

  void submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (uploadedFileName == null) {
        _showMessage("Please upload verification document");
        return;
      }

      setState(() => _isLoading = true);
      final authService = Provider.of<AuthService>(context, listen: false);

      try {
        await authService.signUp(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
          fullName: fullNameController.text.trim(),
          mobile: mobileController.text.trim(),
          role: widget.role,
          documentName: uploadedFileName!,
        );

        if (mounted) {
          _showMessage("Account created successfully!");
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
        }
      } catch (e) {
        _showMessage(e.toString(), isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : const Color(0xFF22C55E)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text("${widget.role} Sign Up", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                buildTextField(controller: fullNameController, label: "Full Name", validator: (v) => v!.isEmpty ? "Required" : null),
                buildTextField(controller: emailController, label: "Email ID", keyboardType: TextInputType.emailAddress, validator: (v) => !v!.contains('@') ? "Invalid email" : null),
                buildTextField(controller: mobileController, label: "Mobile Number", keyboardType: TextInputType.number, validator: (v) => v!.length < 10 ? "Invalid mobile" : null),
                buildTextField(
                  controller: passwordController,
                  label: "Password",
                  obscureText: isPasswordHidden,
                  suffixIcon: IconButton(
                    icon: Icon(isPasswordHidden ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                    onPressed: () => setState(() => isPasswordHidden = !isPasswordHidden),
                  ),
                  validator: (v) => !passwordRegex.hasMatch(v!) ? "Weak password" : null,
                ),
                buildTextField(controller: confirmPasswordController, label: "Confirm Password", obscureText: true, validator: (v) => v != passwordController.text ? "Mismatch" : null),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: pickDocument,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.upload_file, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(child: Text(uploadedFileName ?? "Upload Verification Document", style: TextStyle(color: uploadedFileName == null ? Colors.grey : Colors.white))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : submitForm,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Create Account", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTextField({required TextEditingController controller, required String label, bool obscureText = false, TextInputType keyboardType = TextInputType.text, Widget? suffixIcon, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(color: Colors.grey),
          suffixIcon: suffixIcon,
          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF22C55E)), borderRadius: BorderRadius.circular(12)),
          errorBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.red), borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}