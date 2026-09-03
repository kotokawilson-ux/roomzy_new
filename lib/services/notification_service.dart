// lib/services/notification_service.dart
//
// ── pubspec.yaml ──────────────────────────────────────────────────────────────
//   onesignal_flutter: ^5.2.5
//   http: ^1.2.0          ← already in your project (used by top_bar.dart)
//
// ── android/app/src/main/AndroidManifest.xml ──────────────────────────────────
//   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//
// ── CHANGES IN THIS VERSION ─────────────────────────────────────────────────
//   Migrated from single-string `oneSignalPlayerId` to array field
//   `oneSignalPlayerIds` on `admins`, `admin_push_tokens`, and `users` docs.
//   Writes use arrayUnion (never overwrite), reads send to every ID in the
//   array. Fixes: (1) logging in on a new device/shared device silently
//   evicting another device's/account's registration, (2) notifyAdmin()
//   only ever notifying one admin device via `.limit(1)`.
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

// Web Push subscription ID bridge — reads the browser's OneSignal
// subscription ID via the JS SDK loaded in web/index.html. No-ops on
// mobile (see onesignal_web_stub.dart).
import 'onesignal_web.dart';

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

  bool get _isMobileOnly =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ── Cross-platform player ID lookup: web reads from the JS bridge,
  //    mobile reads from the native OneSignal plugin, desktop gets null.
  Future<String?> _currentPlayerIdAsync() async {
    if (kIsWeb) return getOneSignalWebPlayerId();
    if (!_isMobileOnly) return null; // desktop — unsupported
    try {
      return OneSignal.User.pushSubscription.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> init({
    required GlobalKey<NavigatorState> navKey,
    required GoRouter router,
  }) async {
    _navKey = navKey;
    _router = router;

    if (!_isMobileOnly) {
      debugPrint(
          '[OneSignal] Native init skipped — web SDK initializes itself via web/index.html');
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

  // ── Now works on web too, via _currentPlayerIdAsync(). Called from
  //    admin_live_chat_screen.dart's initState() — this is what actually
  //    populates admin_push_tokens. Uses arrayUnion so this device's ID
  //    is added alongside any other devices already registered for this
  //    admin, rather than replacing them.
  Future<void> saveTokenForAdmin(String adminUid) async {
    if (adminUid.isEmpty) return;

    final playerId = await _currentPlayerIdAsync();
    if (playerId == null || playerId.isEmpty) return;

    try {
      // Private admin doc (sensitive fields, admin-only read)
      await FirebaseFirestore.instance.collection('admins').doc(adminUid).set(
        {
          'oneSignalPlayerIds': FieldValue.arrayUnion([playerId]),
        },
        SetOptions(merge: true),
      );

      // Public token-only doc (safe for any signed-in user to read,
      // so students can notify admin without seeing sensitive admin data)
      await FirebaseFirestore.instance
          .collection('admin_push_tokens')
          .doc(adminUid)
          .set(
        {
          'oneSignalPlayerIds': FieldValue.arrayUnion([playerId]),
        },
        SetOptions(merge: true),
      );

      debugPrint('[OneSignal] Player ID saved for admin $adminUid');
    } catch (e) {
      debugPrint('[OneSignal] saveTokenForAdmin error: $e');
    }
  }

  // ── NOTE: no platform guard here — this is pure Firestore read +
  //    HTTP POST to our own backend, no native OneSignal SDK involved,
  //    so it already works on web too. Sends to every device the student
  //    has registered (array), not just one.
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
      final playerIds =
          (doc.data()?['oneSignalPlayerIds'] as List?)?.cast<String>() ??
              const <String>[];
      if (playerIds.isEmpty) {
        debugPrint('[OneSignal] No player IDs for student $studentUid');
        return;
      }
      await _sendPush(
        playerIds: playerIds,
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
  //    Now notifies EVERY registered admin device across every admin doc
  //    (previously `.limit(1)` meant only one admin/device ever got it).
  Future<void> notifyAdmin({
    required String title,
    required String body,
    required String studentUid,
  }) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_push_tokens')
          .get();
      final playerIds = <String>{};
      for (final d in snap.docs) {
        final ids = (d.data()['oneSignalPlayerIds'] as List?)?.cast<String>();
        if (ids != null) playerIds.addAll(ids);
      }
      if (playerIds.isEmpty) {
        debugPrint('[OneSignal] No player IDs for admin');
        return;
      }
      await _sendPush(
        playerIds: playerIds.toList(),
        title: title,
        body: body,
        data: {'role': 'admin', 'uid': studentUid},
      );
    } catch (e) {
      debugPrint('[OneSignal] notifyAdmin error: $e');
    }
  }

  // ── Push send — proxied through our own backend (Vercel), which
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
