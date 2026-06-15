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
  static const _oneSignalRestApiKey =
      'os_v2_app_vlk7b67gsvgcrfjx2ncbdx2pifsqifs4smaez3m5ecyfq6hh3ed77uuayl7hmtifbzubyodky5wb4xrfu4scvdty3ri2tsh5zuymqcy';

  String _lastSavedUid = '';

  // ── Platform guard ────────────────────────────────────────────────────────
  // OneSignal only works on Android and iOS.
  // Web, Windows, macOS, Linux all skip every OneSignal call at runtime.
  bool get _isMobileOnly =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ── Init ──────────────────────────────────────────────────────────────────
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

      // Show heads-up banner even when app is in foreground (like WhatsApp)
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

  // ── Current OneSignal player/subscription ID ──────────────────────────────
  // Returns empty string on web/desktop or if OneSignal hasn't assigned an ID.
  String get currentPlayerId {
    if (!_isMobileOnly) return '';
    try {
      return OneSignal.User.pushSubscription.id ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Save player ID for a regular user ─────────────────────────────────────
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

  // ── Save player ID for admin ───────────────────────────────────────────────
  Future<void> saveTokenForAdmin(String adminUid) async {
    if (adminUid.isEmpty || !_isMobileOnly) return;

    try {
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminUid)
          .set({'oneSignalPlayerId': playerId}, SetOptions(merge: true));
      debugPrint('[OneSignal] Player ID saved for admin $adminUid');
    } catch (e) {
      debugPrint('[OneSignal] saveTokenForAdmin error: $e');
    }
  }

  // ── Notify a student (called from admin) ──────────────────────────────────
  Future<void> notifyStudent({
    required String studentUid,
    required String title,
    required String body,
  }) async {
    if (!_isMobileOnly) return;
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

  // ── Notify admin (called from student chat) ───────────────────────────────
  Future<void> notifyAdmin({
    required String title,
    required String body,
    required String studentUid,
  }) async {
    if (!_isMobileOnly) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('admins').limit(1).get();
      if (snap.docs.isEmpty) {
        debugPrint('[OneSignal] No admin documents found');
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

  // ── REST push via OneSignal API ────────────────────────────────────────────
  Future<void> _sendPush({
    required List<String> playerIds,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.onesignal.com/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key $_oneSignalRestApiKey',
        },
        body: jsonEncode({
          'app_id': _oneSignalAppId,
          'include_player_ids': playerIds,
          'headings': {'en': title},
          'contents': {'en': body},
          'data': data,
          'android_channel_id': 'chat_messages',
          'priority': 10,
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
