// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/models.dart';

// OneSignal is a mobile-only plugin — import it conditionally so web
// builds never reference the native channel at all. Reuses the same
// stub notification_service.dart already defines.
import 'package:onesignal_flutter/onesignal_flutter.dart'
    if (dart.library.html) 'notification_service_web_stub.dart';

// Web Push subscription ID bridge — reads the browser's OneSignal
// subscription ID via the JS SDK loaded in web/index.html.
import 'onesignal_web.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  FirebaseFirestore _db = FirebaseFirestore.instance;

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _sessionLoaded = false;
  String? _errorMessage;
// add near the other fields
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userRole => _currentUser?.role;

  /// Quick access to the linked landlord document ID (null if not a landlord).
  String? get landlordId => _currentUser?.landlordId;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Push notification registration ────────────────────────────
  //
  // Saves this device's OneSignal subscription ID onto the user's
  // Firestore doc as an entry in `oneSignalPlayerIds` (array) —
  // this exact field name is what every handler in notify.js reads.
  // Called after every successful signup AND every successful login
  // (not just once), so a returning user on a new device — or a
  // device that only just got notification permission granted —
  // stays correctly registered.
  //
  // Uses arrayUnion instead of a plain overwrite so that logging in
  // on a second device (or a different account on a shared
  // device/browser) ADDS a subscription ID instead of stealing/
  // replacing whatever was already registered. This is what fixes
  // the "messages stopped coming" bug: previously a single
  // `oneSignalPlayerId` string field meant the last login on any
  // given device silently overwrote every other registration for
  // that account.
  //
  // Never blocks or fails the calling flow; push registration is
  // best-effort.
  Future<void> _registerPushId(String uid) async {
    try {
      final playerId = kIsWeb
          ? await getOneSignalWebPlayerId()
          : OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) return;
      await _db.collection('users').doc(uid).set({
        'oneSignalPlayerIds': FieldValue.arrayUnion([playerId]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('AuthService: failed to register push id: $e');
    }
  }

  // ─── Session ──────────────────────────────────────────────────

  /// Called once by AuthGate on cold launch.
  Future<void> loadSession() async {
    if (_sessionLoaded) return;
    _sessionLoaded = true;

    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      _setLoading(true);
      try {
        await _fetchAndCacheProfile(firebaseUser.uid);
        await _registerPushId(firebaseUser.uid); // ← add this
      } catch (_) {
        // Network/Firestore error resolving profile — treat as logged out
        // for redirect purposes rather than hanging isInitialized forever.
        _currentUser = null;
      }
      _setLoading(false);
    }
    _isInitialized = true;
    notifyListeners();
  }

  // ─── Login ────────────────────────────────────────────────────

  // NEW — 'super_admin' added so the promoted role passes login validation.
  static const _validRoles = {'admin', 'super_admin', 'landlord', 'student'};

  Future<bool> _signIn(String email, String password) async {
    _setLoading(true);
    _clearError();
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      bool profileOk;
      try {
        profileOk = await _fetchAndCacheProfile(cred.user!.uid);
      } catch (e) {
        final msg = e.toString();
        final isCorruptedClient = msg.contains('INTERNAL ASSERTION FAILED') ||
            msg.contains('ca9') ||
            msg.contains('b815');

        if (isCorruptedClient) {
          // Known Firestore Web SDK bug: a listener's watch-target state
          // gets desynced (usually from a stream being torn down while
          // its target registration was still in flight elsewhere in the
          // app), which corrupts the shared client for the rest of the
          // session. Recover by tearing down and reinitializing the
          // Firestore client, then retry the fetch once.
          debugPrint(
              'AuthService: detected corrupted Firestore client, resetting — $e');
          try {
            await _db.terminate();
            _db = FirebaseFirestore.instance;
            profileOk = await _fetchAndCacheProfile(cred.user!.uid);
          } catch (e2) {
            debugPrint('AuthService: retry after reset also failed — $e2');
            _setError(
                'Could not reach the server. Please fully close and reopen the app, then try again.');
            return false;
          }
        } else {
          debugPrint('AuthService: profile fetch errored during login — $e');
          _setError(
              'Could not reach the server. Please check your connection and try again.');
          return false;
        }
      }
      // ── Safeguard: profile fetch SUCCEEDED but came back empty,
      // has an unrecognized role, or is a landlord missing their
      // landlordId → this is a genuinely broken/incomplete account.
      // Block it and sign out.
      final user = _currentUser;
      final roleOk = profileOk &&
          user != null &&
          _validRoles.contains(user.role) &&
          (user.role != 'landlord' ||
              (user.landlordId != null && user.landlordId!.isNotEmpty));

      if (!roleOk) {
        debugPrint(
            'AuthService: blocking login — invalid/incomplete profile for uid=${cred.user!.uid}');
        await _auth.signOut();
        _currentUser = null;
        _setError(
            'Your account isn\'t set up correctly. Please contact support.');
        return false;
      }

      // ── Register (or refresh) this device's push subscription for
      // whichever role just logged in — student, landlord, or admin.
      // Fire-and-forget: never blocks or fails the login itself.
      await _registerPushId(cred.user!.uid);

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
      _isInitialized = true;
      notifyListeners();

      // Register this device's push ID before firing the welcome
      // notify — if OneSignal already has a subscription ID at this
      // point (permission granted during onboarding, etc.), the
      // welcome push can actually land instead of silently no-op'ing.
      await _registerPushId(uid);
      _notifyStudentRegistered(userId: uid, username: username.trim());

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

  static const _notifyEndpoint =
      'https://roomzy-backend-eight.vercel.app/api/notify';

  // Fire-and-forget — never blocks or fails registration if the
  // notification call itself has a problem.
  Future<void> _notifyLandlordSignup({
    required String landlordId,
    required String businessName,
  }) async {
    try {
      await http.post(
        Uri.parse(_notifyEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'landlord_signup',
          'landlordId': landlordId,
          'businessName': businessName,
        }),
      );
    } catch (e) {
      debugPrint('AuthService: landlord signup notify failed (non-fatal): $e');
    }
  }

  Future<void> _notifyStudentRegistered({
    required String userId,
    required String username,
  }) async {
    try {
      await http.post(
        Uri.parse(_notifyEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'student_registered',
          'userId': userId,
          'username': username,
        }),
      );
    } catch (e) {
      debugPrint(
          'AuthService: student registered notify failed (non-fatal): $e');
    }
  }
  // ─── Register (Landlord — self-service) ───────────────────────
  //
  // Lets a landlord sign themselves up from the app, no admin
  // involvement required. This is different from
  // `createLandlordAccount` (below), which is the admin-driven flow.
  //
  // Flow:
  //   1. Create the Firebase Auth account directly (this signs the
  //      new landlord in immediately, same as registerStudent).
  //   2. Create the `landlords` doc — stamped with
  //      `registered_by: 'self'` and `verified: false` so the admin
  //      panel can flag it for review.
  //   3. Create the `users` doc with role: 'landlord' + landlord_id
  //      pointing back at the landlord doc.
  //
  // If step 2 or 3 fails after the Auth account was already created,
  // we best-effort delete the orphaned Auth account so the person can
  // simply try registering again with the same email.

  Future<bool> registerLandlord({
    required String businessName,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();

    User? createdUser;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      createdUser = cred.user;
      final uid = createdUser!.uid;

      final landlordCode = _generateLandlordCode(businessName, phone);

      final landlordRef = await _db.collection('landlords').add({
        'full_name': businessName.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'landlord_code': landlordCode,
        'profile_image': '',
        'auth_uid': uid,
        'registered_at': FieldValue.serverTimestamp(),
        // Self-service signup — flagged for admin review until verified.
        'registered_by': 'self',
        'verified': false,
      });

      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'username': businessName.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'role': 'landlord',
        'landlord_id': landlordRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _currentUser = UserModel(
        id: uid,
        username: businessName.trim(),
        email: email.trim(),
        phone: phone.trim(),
        role: 'landlord',
        landlordId: landlordRef.id,
      );
      _sessionLoaded = true;
      _isInitialized = true;
      notifyListeners();

      // Fire-and-forget — landlord is already registered successfully
      // by this point; a notify failure shouldn't undo that.
      await _registerPushId(uid);
      _notifyLandlordSignup(
        landlordId: landlordRef.id,
        businessName: businessName.trim(),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      _setError(_authError(e.code));
      return false;
    } catch (e) {
      debugPrint('AuthService: landlord self-registration failed — $e');
      // Roll back the Auth account so a retry with the same email
      // doesn't hit "email-already-in-use" for a broken registration.
      try {
        await createdUser?.delete();
      } catch (_) {
        // If deletion needs a recent login we can't force it here —
        // not fatal, the person can still contact support.
      }
      _setError('Registration failed. Please try again.');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Mirrors the admin dialog's auto-code logic: uppercase name (no
  /// spaces) + last 3 digits of phone, so self-registered and
  /// admin-created landlords get consistent-looking codes.
  String _generateLandlordCode(String name, String phone) {
    final n = name.trim().replaceAll(' ', '').toUpperCase();
    final p = phone.trim();
    if (n.isEmpty) return 'LL${DateTime.now().millisecondsSinceEpoch}';
    if (p.length >= 3) return '$n-${p.substring(p.length - 3)}';
    return n.length > 6 ? n.substring(0, 6) : n;
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
        'registered_by': 'admin',
        'verified': true,
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

  // ─── Create Admin Account (Super Admin only) ──────────────────
  //
  // Mirrors createLandlordAccount: creates the Firebase Auth account
  // via a secondary FirebaseApp so the currently signed-in super
  // admin's own session is untouched, then writes the Firestore
  // `users` doc using the REAL Auth uid as the doc ID (not .add()
  // with a random ID — that's what was broken before: a Firestore
  // doc existed with a role and a password field, but no actual
  // Auth account backing it, so login always failed).

  Future<({bool success, String? error})> createAdminAccount({
    required String username,
    required String email,
    required String password,
    required String role, // 'admin' or 'super_admin'
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final secondaryApp = await Firebase.initializeApp(
        name: 'admin_creation_${DateTime.now().millisecondsSinceEpoch}',
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

      await _db.collection('users').doc(newUid).set({
        'uid': newUid,
        'username': username.trim(),
        'email': email.trim(),
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('AuthService: admin account created — uid=$newUid role=$role');
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      final msg = _authError(e.code);
      _setError(msg);
      return (success: false, error: msg);
    } catch (e) {
      final msg = 'Failed to create admin account: $e';
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
  // ─── Update Landlord Profile (name/phone/address) ─────────────
  //
  // Unlike the generic `updateProfile` above (which only touches the
  // `users` doc), this also syncs the `landlords/{id}` doc — that's
  // the collection the admin panels (LandlordsPane, UsersPane) actually
  // read from, so without this a landlord's own edits would silently
  // never show up for admins.

  Future<({bool success, String? error})> updateLandlordProfile({
    required String fullName,
    required String phone,
    required String address,
  }) async {
    final uid = _auth.currentUser?.uid;
    final landlordId = _currentUser?.landlordId;
    if (uid == null) return (success: false, error: 'Not logged in.');
    if (landlordId == null) {
      return (success: false, error: 'No linked landlord record.');
    }

    _setLoading(true);
    _clearError();
    try {
      await _db.collection('users').doc(uid).update({
        'username': fullName.trim(),
        'phone': phone.trim(),
      });
      await _db.collection('landlords').doc(landlordId).update({
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      _currentUser = _currentUser?.copyWith(
        username: fullName.trim(),
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

  // ─── Change Email ───────────────────────────────────────────────
  //
  // Requires re-auth like changePassword. Uses verifyBeforeUpdateEmail
  // rather than the old updateEmail() — Firebase now requires this on
  // most projects. IMPORTANT: this sends a confirmation link to the
  // NEW address; the Auth login email does NOT change until that link
  // is clicked. We stamp a `pending_email` field on both docs so the
  // UI (and admin, if you want to surface it later) can show "change
  // in progress" without prematurely overwriting the still-active
  // login email.

  Future<({bool success, String? error})> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null || firebaseUser.email == null) {
      return (success: false, error: 'Not logged in.');
    }
    final uid = firebaseUser.uid;
    final trimmedNewEmail = newEmail.trim();

    _setLoading(true);
    _clearError();
    try {
      final credential = EmailAuthProvider.credential(
        email: firebaseUser.email!,
        password: currentPassword.trim(),
      );
      await firebaseUser.reauthenticateWithCredential(credential);

      await firebaseUser.verifyBeforeUpdateEmail(trimmedNewEmail);

      await _db.collection('users').doc(uid).update({
        'pending_email': trimmedNewEmail,
      });
      if (_currentUser?.landlordId != null) {
        await _db
            .collection('landlords')
            .doc(_currentUser!.landlordId)
            .update({'pending_email': trimmedNewEmail});
      }

      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      final msg = _authError(e.code);
      _setError(msg);
      return (success: false, error: msg);
    } catch (e) {
      final msg = 'Email change failed. Please try again.';
      _setError(msg);
      return (success: false, error: msg);
    } finally {
      _setLoading(false);
    }
  }
  // ─── Logout ───────────────────────────────────────────────────
  //
  // Only removes THIS device's subscription ID from the array — other
  // devices/sessions this account is logged into elsewhere stay
  // registered and keep receiving pushes. Previously this deleted the
  // whole `oneSignalPlayerId` field, which meant any hiccup between
  // logout and the next login's re-registration left the account with
  // zero working devices until the next successful login.

  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        final playerId = kIsWeb
            ? await getOneSignalWebPlayerId()
            : OneSignal.User.pushSubscription.id;
        if (playerId != null && playerId.isNotEmpty) {
          await _db.collection('users').doc(uid).update({
            'oneSignalPlayerIds': FieldValue.arrayRemove([playerId]),
          });
        }
      } catch (_) {
        // Non-fatal — logout should proceed even if this cleanup fails.
      }
    }
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

  Future<bool> _fetchAndCacheProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _currentUser = UserModel.fromJson(uid, doc.data()!);
        debugPrint(
            'AuthService: profile loaded — uid=$uid role=${_currentUser?.role} landlordId=${_currentUser?.landlordId}');
        notifyListeners();
        return true;
      } else {
        debugPrint('AuthService: no Firestore profile for uid: $uid');
        _currentUser = null;
        return false;
      }
    } catch (e) {
      debugPrint('AuthService: failed to fetch profile — $e');
      _currentUser = null;
      // A thrown exception means we couldn't determine the profile state
      // at all (network/Firestore error) — this is NOT the same as "no
      // profile exists". Rethrow so callers can tell the two apart instead
      // of treating a connection hiccup as a bad account.
      rethrow;
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
