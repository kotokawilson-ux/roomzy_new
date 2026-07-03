// lib/services/notification_service.dart
//
// ── pubspec.yaml ──────────────────────────────────────────────────────────────
//   onesignal_flutter: ^5.2.5
//   http: ^1.2.0          ← already in your project (used by top_bar.dart)
//
// ── android/app/src/main/AndroidManifest.xml ──────────────────────────────────
//   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

// OneSignal is a mobile-only plugin — import it conditionally so web
// and desktop builds never reference the native channel at all.
import 'package:onesignal_flutter/onesignal_flutter.dart'
    if (dart.library.html) 'notification_service_web_stub.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static GoRouter? _router;
  static GlobalKey<NavigatorState>? _navKey;

  static const _oneSignalAppId = 'aad5f0fb-e695-4c28-9537-d34411df4f41';

  // ── NOTE: REST API key removed from here entirely. It now lives only in
  //    your backend's env vars (Vercel) and is never shipped to the client.
  //    The app ID above is still needed locally for OneSignal.initialize()
  //    (the native mobile SDK init call), which is not a secret.

  // ── Your backend's /api/notify endpoint — update this if your domain changes.
  static const _notifyEndpoint =
      'https://roomzy-backend-eight.vercel.app/api/notify';

  String _lastSavedUid = '';

  bool get _isMobileOnly =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init({
    required GlobalKey<NavigatorState> navKey,
    required GoRouter router,
  }) async {
    _navKey = navKey;
    _router = router;

    if (!_isMobileOnly) {
      debugPrint('[OneSignal] Skipped — only supported on Android/iOS');
      return;
    }

    try {
      OneSignal.initialize(_oneSignalAppId);
      await OneSignal.Notifications.requestPermission(true);

      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        event.notification.display();
      });

      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        final role = data?['role'] as String?;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (role == 'admin') {
            _router?.go('/admin/chat');
          } else {
            _router?.go('/chat');
          }
        });
      });

      debugPrint('[OneSignal] Initialized');
    } catch (e) {
      debugPrint('[OneSignal] Init error (non-fatal): $e');
    }
  }

  String get currentPlayerId {
    if (!_isMobileOnly) return '';
    try {
      return OneSignal.User.pushSubscription.id ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> saveTokenForUser(String uid) async {
    if (uid.isEmpty || !_isMobileOnly) return;
    _lastSavedUid = uid;

    try {
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) {
        debugPrint(
            '[OneSignal] No player ID yet — will retry on token refresh');
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'oneSignalPlayerId': playerId}, SetOptions(merge: true));
      debugPrint('[OneSignal] Player ID saved for user $uid');
    } catch (e) {
      debugPrint('[OneSignal] saveTokenForUser error: $e');
    }
  }

  Future<void> saveTokenForAdmin(String adminUid) async {
    if (adminUid.isEmpty || !_isMobileOnly) return;

    try {
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) return;

      // Private admin doc (sensitive fields, admin-only read)
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminUid)
          .set({'oneSignalPlayerId': playerId}, SetOptions(merge: true));

      // Public token-only doc (safe for any signed-in user to read,
      // so students can notify admin without seeing sensitive admin data)
      await FirebaseFirestore.instance
          .collection('admin_push_tokens')
          .doc(adminUid)
          .set({'oneSignalPlayerId': playerId}, SetOptions(merge: true));

      debugPrint('[OneSignal] Player ID saved for admin $adminUid');
    } catch (e) {
      debugPrint('[OneSignal] saveTokenForAdmin error: $e');
    }
  }

  // ── NOTE: no _isMobileOnly guard here — this is pure Firestore read +
  //    HTTP POST to our own backend, no native OneSignal SDK involved,
  //    so it works on web too.
  Future<void> notifyStudent({
    required String studentUid,
    required String title,
    required String body,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(studentUid)
          .get();
      final playerId = doc.data()?['oneSignalPlayerId'] as String?;
      if (playerId == null || playerId.isEmpty) {
        debugPrint('[OneSignal] No player ID for student $studentUid');
        return;
      }
      await _sendPush(
        playerIds: [playerId],
        title: title,
        body: body,
        data: {'role': 'student', 'uid': studentUid},
      );
    } catch (e) {
      debugPrint('[OneSignal] notifyStudent error: $e');
    }
  }

  // ── NOTE: reads from admin_push_tokens (not admins) — students don't
  //    have Firestore read access to /admins since it holds sensitive
  //    data, so the push token lives in this separate, narrow collection.
  Future<void> notifyAdmin({
    required String title,
    required String body,
    required String studentUid,
  }) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_push_tokens')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        debugPrint('[OneSignal] No admin push token found');
        return;
      }
      final playerId = snap.docs.first.data()['oneSignalPlayerId'] as String?;
      if (playerId == null || playerId.isEmpty) {
        debugPrint('[OneSignal] No player ID for admin');
        return;
      }
      await _sendPush(
        playerIds: [playerId],
        title: title,
        body: body,
        data: {'role': 'admin', 'uid': studentUid},
      );
    } catch (e) {
      debugPrint('[OneSignal] notifyAdmin error: $e');
    }
  }

  // ── Push send — now proxied through our own backend (Vercel), which
  //    holds the OneSignal REST API key server-side. This avoids CORS
  //    failures on web and keeps the key out of the client bundle.
  Future<void> _sendPush({
    required List<String> playerIds,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_notifyEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'playerIds': playerIds,
          'title': title,
          'body': body,
          'data': data,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[OneSignal] Push sent successfully');
      } else {
        debugPrint(
            '[OneSignal] Push failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[OneSignal] _sendPush error: $e');
    }
  }
}
