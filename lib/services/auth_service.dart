// lib/services/auth_service.dart

import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// ─────────────────────────────────────────────────────────────
/// AuthService — placeholder until auth is implemented
/// All methods are stubbed and safe to use across the app.
/// ─────────────────────────────────────────────────────────────
class AuthService extends ChangeNotifier {
  UserModel? _currentUser;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => false; // always false for now
  bool get isLoading => false; // never loading
  String? get errorMessage => null; // no errors
  String? get userRole => null; // no role

  // No-op — nothing to load yet
  Future<void> loadSession() async {}

  // No-op stubs — implement when auth screens are ready
  Future<bool> loginStudent(String email, String password) async => false;
  Future<bool> loginLandlord(String email, String password) async => false;
  Future<bool> loginAdmin(String email, String password) async => false;

  Future<bool> registerStudent({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async =>
      false;

  Future<void> logout() async {}
}
