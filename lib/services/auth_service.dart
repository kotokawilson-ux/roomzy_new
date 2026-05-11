// lib/services/auth_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;

  // ── FIXED: isLoggedIn only checks Firebase auth, not _currentUser ──────────
  // Previously: _auth.currentUser != null && _currentUser != null
  // Problem: right after login, _currentUser could briefly be null even though
  // Firebase says the user is logged in, causing the router redirect to think
  // the user is logged out and routing them to /home via AuthGate.
  bool get isLoggedIn => _auth.currentUser != null;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userRole => _currentUser?.role;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> loadSession() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await _fetchAndCacheProfile(firebaseUser.uid);
    }
  }

  Future<bool> _signIn(String email, String password) async {
    _setLoading(true);
    _clearError();
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      await _fetchAndCacheProfile(cred.user!.uid);

      if (_currentUser == null) {
        debugPrint(
            'AuthService: user signed in but profile not found in Firestore.');
      }

      return true;
    } on FirebaseAuthException catch (e) {
      _setError(_authError(e.code));
      return false;
    } catch (e) {
      _setError('Something went wrong. Please try again.');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> loginStudent(String email, String password) =>
      _signIn(email, password);

  Future<bool> loginLandlord(String email, String password) =>
      _signIn(email, password);

  Future<bool> loginAdmin(String email, String password) =>
      _signIn(email, password);

  Future<bool> registerStudent({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final uid = cred.user!.uid;
      final userData = {
        'uid': uid,
        'username': username.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'role': 'student',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await _db.collection('users').doc(uid).set(userData);

      _currentUser = UserModel(
        id: uid,
        username: username.trim(),
        email: email.trim(),
        phone: phone.trim(),
        role: 'student',
      );
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _setError(_authError(e.code));
      return false;
    } catch (e) {
      _setError('Registration failed. Please try again.');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e.code);
    }
  }

  Future<void> _fetchAndCacheProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _currentUser = UserModel.fromJson(uid, doc.data()!);
        debugPrint('AuthService: profile loaded — role: ${_currentUser?.role}');
        notifyListeners();
      } else {
        debugPrint('AuthService: no Firestore document found for uid: $uid');
      }
    } catch (e) {
      debugPrint('AuthService: failed to fetch user profile — $e');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String _authError(String code) => switch (code) {
        'user-not-found' => 'No account found with this email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-credential' => 'Invalid email or password.',
        'invalid-email' => 'Please enter a valid email address.',
        'email-already-in-use' => 'An account already exists with this email.',
        'weak-password' => 'Password must be at least 6 characters.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Something went wrong. Please try again.',
      };
}
