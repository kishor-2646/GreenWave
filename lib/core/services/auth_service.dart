import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream of auth state changes
  Stream<User?> get userState => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign Up with Role
  Future<UserCredential?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String mobile,
    required String role,
    required String documentName,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        await _db.collection('users').doc(result.user!.uid).set({
          'uid': result.user!.uid,
          'fullName': fullName,
          'email': email,
          'mobile': mobile,
          'role': role,
          'documentUrl': documentName,
          'isVerified': false,
          'createdAt': FieldValue.serverTimestamp(),
          'onDuty': false,
        });
      }
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // Login
  Future<UserCredential> login(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      rethrow;
    }
  }

  // Functional Forgot Password logic
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  // Sign Out
  Future<void> signOut() async => await _auth.signOut();

  // Get User Role
  Future<String?> getUserRole(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        return (doc.data() as Map<String, dynamic>)['role'];
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}