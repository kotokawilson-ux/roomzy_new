// lib/services/auth_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'package:firebase_core/firebase_core.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _sessionLoaded = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userRole => _currentUser?.role;

  /// Quick access to the linked landlord document ID (null if not a landlord).
  String? get landlordId => _currentUser?.landlordId;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Session ──────────────────────────────────────────────────

  /// Called once by AuthGate on cold launch.
  Future<void> loadSession() async {
    if (_sessionLoaded) return;
    _sessionLoaded = true;

    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      _setLoading(true);
      await _fetchAndCacheProfile(firebaseUser.uid);
      _setLoading(false);
    }
  }

  // ─── Login ────────────────────────────────────────────────────

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
        debugPrint('AuthService: signed in but no Firestore profile found.');
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

  // ─── Register (Student) ───────────────────────────────────────

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
      _sessionLoaded = true;
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

  // ─── Create Landlord Account (Admin only) ─────────────────────
  //
  // Flow:
  //   1. Admin calls this from the admin panel.
  //   2. We create a Firebase Auth account for the landlord.
  //   3. We write a 'users' doc with role: 'landlord' + landlord_id.
  //   4. We update the existing 'landlords' doc with the new auth_uid.
  //
  // The current admin session is NOT affected — we use a secondary
  // FirebaseApp instance so createUserWithEmailAndPassword doesn't
  // swap the signed-in user.

  Future<({bool success, String? error})> createLandlordAccount({
    required String landlordDocId, // existing Firestore landlord doc ID
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String landlordCode,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      // ── 1. Create Auth account via secondary app ──────────────
      final secondaryApp = await Firebase.initializeApp(
        name: 'landlord_creation_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      String newUid;
      try {
        final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
        final cred = await secondaryAuth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
        newUid = cred.user!.uid;
        await secondaryAuth.signOut();
      } finally {
        await secondaryApp.delete();
      }

      // ── 2. Write users doc ────────────────────────────────────
      await _db.collection('users').doc(newUid).set({
        'uid': newUid,
        'username': fullName.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'role': 'landlord',
        'landlord_id': landlordDocId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ── 3. Stamp auth_uid onto the landlords doc ──────────────
      await _db.collection('landlords').doc(landlordDocId).update({
        'auth_uid': newUid,
      });

      debugPrint(
          'AuthService: landlord account created — uid=$newUid landlordDoc=$landlordDocId');
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      final msg = _authError(e.code);
      _setError(msg);
      return (success: false, error: msg);
    } catch (e) {
      final msg = 'Failed to create landlord account: $e';
      _setError(msg);
      return (success: false, error: msg);
    } finally {
      _setLoading(false);
    }
  }

  // ─── Update Profile ───────────────────────────────────────────
  //
  // Landlords (and students) can update their username and phone.
  // Email changes require re-authentication so we keep that separate.

  Future<({bool success, String? error})> updateProfile({
    required String username,
    required String phone,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return (success: false, error: 'Not logged in.');

    _setLoading(true);
    _clearError();
    try {
      await _db.collection('users').doc(uid).update({
        'username': username.trim(),
        'phone': phone.trim(),
      });

      // Keep local cache in sync
      _currentUser = _currentUser?.copyWith(
        username: username.trim(),
        phone: phone.trim(),
      );
      notifyListeners();
      return (success: true, error: null);
    } catch (e) {
      final msg = 'Profile update failed. Please try again.';
      _setError(msg);
      return (success: false, error: msg);
    } finally {
      _setLoading(false);
    }
  }

  // ─── Change Password ──────────────────────────────────────────
  //
  // Requires the user's current password to re-authenticate first
  // (Firebase requires recent auth for sensitive operations).

  Future<({bool success, String? error})> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null || firebaseUser.email == null) {
      return (success: false, error: 'Not logged in.');
    }

    _setLoading(true);
    _clearError();
    try {
      // Re-authenticate
      final credential = EmailAuthProvider.credential(
        email: firebaseUser.email!,
        password: currentPassword.trim(),
      );
      await firebaseUser.reauthenticateWithCredential(credential);

      // Update password
      await firebaseUser.updatePassword(newPassword.trim());

      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      final msg = _authError(e.code);
      _setError(msg);
      return (success: false, error: msg);
    } catch (e) {
      final msg = 'Password change failed. Please try again.';
      _setError(msg);
      return (success: false, error: msg);
    } finally {
      _setLoading(false);
    }
  }

  // ─── Logout ───────────────────────────────────────────────────

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    _sessionLoaded = false;
    notifyListeners();
  }

  // ─── Password Reset ───────────────────────────────────────────

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e.code);
    }
  }

  // ─── Internal ─────────────────────────────────────────────────

  Future<void> _fetchAndCacheProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _currentUser = UserModel.fromJson(uid, doc.data()!);
        debugPrint(
            'AuthService: profile loaded — uid=$uid role=${_currentUser?.role} landlordId=${_currentUser?.landlordId}');
        notifyListeners();
      } else {
        debugPrint('AuthService: no Firestore profile for uid: $uid');
      }
    } catch (e) {
      debugPrint('AuthService: failed to fetch profile — $e');
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
        'requires-recent-login' => 'Please log out and log back in to do this.',
        _ => 'Something went wrong. Please try again.',
      };
}
