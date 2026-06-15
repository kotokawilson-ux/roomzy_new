// lib/services/balance_reminder_service.dart
//
// Reminder + auto-revoke system for RoomzyFind.
//
// Push delivery: OneSignal scheduled notifications (already in pubspec).
// Local persistence: shared_preferences (already in pubspec).
// No new dependencies required.
//
// ── How it works ──────────────────────────────────────────────────────────────
//
//  1. When a booking has balance > 0 and a due-date is set, call
//     scheduleReminders(). This sends one or more future-dated push
//     notifications via the OneSignal REST API (server-side scheduling).
//
//  2. When the user pays in full, call cancelReminders() which deletes
//     the pending OneSignal notifications via the REST cancel endpoint.
//
//  3. On every app launch / resume, call checkAndRevokeOverdue() to
//     find bookings whose due-date has passed with an unpaid balance
//     and flip them to 'cancelled' in Firestore.
//
// ── OneSignal REST API used ───────────────────────────────────────────────────
//   POST https://onesignal.com/api/v1/notifications          — create / schedule
//   DELETE https://onesignal.com/api/v1/notifications/{id}   — cancel
//
// ── Setup ─────────────────────────────────────────────────────────────────────
//  • Set _kOneSignalAppId and _kOneSignalRestKey below (from your OneSignal
//    dashboard → Settings → Keys & IDs).
//  • These values should ideally come from a remote-config / env file; for
//    now hard-coding them here keeps the service self-contained.
//  • In main.dart you already call NotificationService.instance.init() which
//    initialises the OneSignal SDK. Nothing extra needed there.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─── ⚙️  Replace these two values from your OneSignal dashboard ──────────────
const _kOneSignalAppId = 'aad5f0fb-e695-4c28-9537-d34411df4f41';
const _kOneSignalRestKey = 'os_v2_app_vlk7b67gsvgcrfjx2ncbdx2pifsqifs4smaez3m5ecyfq6hh3ed77uuayl7hmtifbzubyodky5wb4xrfu4scvdty3ri2tsh5zuymqcy';
// ─────────────────────────────────────────────────────────────────────────────

const _kOneSignalBase = 'https://onesignal.com/api/v1';
const _kPrefsKey = 'rzf_reminder_notif_ids'; // stores scheduled notif IDs

// ─── Reminder frequency ───────────────────────────────────────────────────────

enum ReminderFrequency {
  daily('Every day', Duration(days: 1)),
  everyThreeDays('Every 3 days', Duration(days: 3)),
  weekly('Once a week', Duration(days: 7));

  const ReminderFrequency(this.label, this.interval);
  final String label;
  final Duration interval;
}

// ─── Reminder settings model ──────────────────────────────────────────────────

class ReminderSettings {
  final bool enabled;
  final ReminderFrequency frequency;
  final int reminderHour; // 24-hr, e.g. 9
  final int reminderMinute; // e.g. 0

  const ReminderSettings({
    this.enabled = true,
    this.frequency = ReminderFrequency.daily,
    this.reminderHour = 9,
    this.reminderMinute = 0,
  });

  ReminderSettings copyWith({
    bool? enabled,
    ReminderFrequency? frequency,
    int? reminderHour,
    int? reminderMinute,
  }) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        frequency: frequency ?? this.frequency,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'frequency': frequency.index,
        'hour': reminderHour,
        'minute': reminderMinute,
      };

  factory ReminderSettings.fromJson(Map<String, dynamic> j) => ReminderSettings(
        enabled: j['enabled'] as bool? ?? true,
        frequency: ReminderFrequency.values[j['frequency'] as int? ?? 0],
        reminderHour: j['hour'] as int? ?? 9,
        reminderMinute: j['minute'] as int? ?? 0,
      );
}

// ─── Service ──────────────────────────────────────────────────────────────────

class BalanceReminderService {
  BalanceReminderService._();
  static final BalanceReminderService instance = BalanceReminderService._();

  // ── Settings persistence ────────────────────────────────────────────────────

  Future<ReminderSettings> loadSettings(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_kPrefsKey}_settings_$bookingId');
    if (raw == null) return const ReminderSettings();
    try {
      return ReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReminderSettings();
    }
  }

  Future<void> saveSettings(String bookingId, ReminderSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '${_kPrefsKey}_settings_$bookingId', jsonEncode(s.toJson()));
  }

  // ── Scheduled notification ID list ─────────────────────────────────────────
  // We store the OneSignal notification IDs so we can cancel them later.

  Future<List<String>> _loadNotifIds(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_kPrefsKey}_ids_$bookingId');
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveNotifIds(String bookingId, List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_kPrefsKey}_ids_$bookingId', jsonEncode(ids));
  }

  // ── Schedule reminders via OneSignal REST API ───────────────────────────────
  //
  // Call this when:
  //   • A due date is set or changed
  //   • The user updates reminder settings
  //   • The app resumes and balance is still owed
  //
  // [oneSignalPlayerId] is the current device's OneSignal player / subscription
  // ID. Retrieve it from your NotificationService:
  //   final playerId = await OneSignal.User.pushSubscription.id;

  Future<void> scheduleReminders({
    required String bookingId,
    required double balance,
    required DateTime dueDate,
    required ReminderSettings settings,
    required String oneSignalPlayerId,
    String hostelName = 'your room',
  }) async {
    // Always cancel previous batch first
    await cancelReminders(bookingId);

    if (!settings.enabled || balance <= 0) return;

    final now = DateTime.now();
    if (dueDate.isBefore(now)) return; // already overdue

    // ── Build fire-time list ─────────────────────────────────────────────────
    final fireTimes = <DateTime>[];

    // Start from next occurrence of the chosen time
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      settings.reminderHour,
      settings.reminderMinute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

    while (next.isBefore(dueDate)) {
      fireTimes.add(next);
      next = next.add(settings.frequency.interval);
    }

    // Always add a same-day final reminder on the due date
    final finalFire = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      settings.reminderHour,
      settings.reminderMinute,
    );
    if (finalFire.isAfter(now)) {
      fireTimes.removeWhere((t) =>
          t.year == finalFire.year &&
          t.month == finalFire.month &&
          t.day == finalFire.day);
      fireTimes.add(finalFire);
    }

    if (fireTimes.isEmpty) return;

    final scheduledIds = <String>[];
    final daysLeft = dueDate.difference(now).inDays;

    for (final fireTime in fireTimes) {
      final isFinalDay = fireTime.year == dueDate.year &&
          fireTime.month == dueDate.month &&
          fireTime.day == dueDate.day;
      final isUrgent = daysLeft <= 3;

      final title = isFinalDay
          ? '⚠️ Last Day — Balance Due for $hostelName'
          : isUrgent
              ? '🔔 Urgent: Balance Due in $daysLeft Day${daysLeft == 1 ? '' : 's'}'
              : '💳 Balance Reminder — $hostelName';

      final body = isFinalDay
          ? 'GHS ${balance.toStringAsFixed(2)} must be paid TODAY or your booking will be cancelled.'
          : 'GHS ${balance.toStringAsFixed(2)} still owed. Due ${_fmtDate(dueDate)}. Tap to pay.';

      final id = await _sendScheduledNotification(
        playerId: oneSignalPlayerId,
        title: title,
        body: body,
        sendAt: fireTime,
        data: {
          'type': 'balance_reminder',
          'bookingId': bookingId,
          'isFinalDay': isFinalDay.toString(),
        },
      );

      if (id != null) scheduledIds.add(id);
    }

    await _saveNotifIds(bookingId, scheduledIds);
    debugPrint(
        '[Reminder] Scheduled ${scheduledIds.length} notifications for $bookingId');
  }

  // ── Cancel all scheduled reminders for a booking ───────────────────────────

  Future<void> cancelReminders(String bookingId) async {
    final ids = await _loadNotifIds(bookingId);
    for (final id in ids) {
      await _cancelOneSignalNotification(id);
    }
    await _saveNotifIds(bookingId, []);
    if (ids.isNotEmpty) {
      debugPrint(
          '[Reminder] Cancelled ${ids.length} notifications for $bookingId');
    }
  }
// ── Move-in nudge reminders ─────────────────────────────────────────────────
  //
  // Schedules a single reminder asking the student to confirm their move-in
  // date. Call this when a booking reaches status 'confirmed' but
  // move_in_date is still null. checkAndNudgeMoveIn() re-calls this daily.

  Future<void> scheduleMoveInReminders({
    required String bookingId,
    required String oneSignalPlayerId,
    String hostelName = 'your room',
  }) async {
    final fireTime = DateTime.now().add(const Duration(days: 1));

    final id = await _sendScheduledNotification(
      playerId: oneSignalPlayerId,
      title: '🔑 Have you moved in?',
      body:
          'If you\'ve entered your room at $hostelName, confirm your move-in date in the app to start your rent schedule.',
      sendAt: fireTime,
      data: {
        'type': 'move_in_reminder',
        'bookingId': bookingId,
      },
    );

    if (id != null) {
      // Store under a distinct key so it doesn't clash with balance reminder IDs
      final existing = await _loadNotifIds('${bookingId}_movein');
      existing.add(id);
      await _saveNotifIds('${bookingId}_movein', existing);
      debugPrint('[Reminder] Scheduled move-in nudge for $bookingId');
    }
  }

  // ── Cancel move-in nudges (call once move_in_date is set) ───────────────────

  Future<void> cancelMoveInReminders(String bookingId) async {
    final ids = await _loadNotifIds('${bookingId}_movein');
    for (final id in ids) {
      await _cancelOneSignalNotification(id);
    }
    await _saveNotifIds('${bookingId}_movein', []);
  }
  // ── Auto-revoke overdue bookings ────────────────────────────────────────────
  //
  // Call this in AppLifecycleState.resumed and on app start.
  // Returns the list of revoked booking IDs (show a snackbar if non-empty).

  Future<List<String>> checkAndRevokeOverdue({required String userId}) async {
    final now = Timestamp.now();
    final revoked = <String>[];

    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('user_id', isEqualTo: userId)
          .where('status', whereIn: ['pending', 'confirmed']).get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
        final dueDateTs = data['balance_due_date'] as Timestamp?;

        if (balance <= 0 || dueDateTs == null) continue;
        if (dueDateTs.compareTo(now) > 0) continue; // not yet due

        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(doc.id)
            .update({
          'status': 'cancelled',
          'cancellation_reason': 'Balance not paid by due date',
          'cancelled_at': FieldValue.serverTimestamp(),
          'auto_revoked': true,
        });

        await cancelReminders(doc.id);
        revoked.add(doc.id);
        debugPrint('[Reminder] Auto-revoked booking ${doc.id}');
      }
    } catch (e) {
      debugPrint('[Reminder] checkAndRevokeOverdue error: $e');
    }

    return revoked;
  }
// ── Check for bookings awaiting move-in confirmation ────────────────────────
  //
  // Call this alongside checkAndRevokeOverdue() in AppLifecycleState.resumed.
  // Re-schedules a move-in nudge once per day for bookings stuck in
  // 'confirmed' status with no move_in_date set yet.

  Future<void> checkAndNudgeMoveIn({
    required String userId,
    required String oneSignalPlayerId,
  }) async {
    if (oneSignalPlayerId.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('user_id', isEqualTo: userId)
          .where('status', isEqualTo: 'confirmed')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['move_in_date'] != null) continue;

        final lastNudgeTs = data['last_move_in_nudge'] as Timestamp?;
        final daysSinceNudge = lastNudgeTs == null
            ? 999
            : DateTime.now().difference(lastNudgeTs.toDate()).inDays;

        if (daysSinceNudge >= 1) {
          await scheduleMoveInReminders(
            bookingId: doc.id,
            oneSignalPlayerId: oneSignalPlayerId,
            hostelName: data['hostel_name'] ?? 'your room',
          );
          await doc.reference.update({
            'last_move_in_nudge': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('[Reminder] checkAndNudgeMoveIn error: $e');
    }
  }
  // ── OneSignal REST helpers ──────────────────────────────────────────────────

  /// Schedules a single push notification via OneSignal REST API.
  /// Returns the OneSignal notification ID on success, null on failure.
  Future<String?> _sendScheduledNotification({
    required String playerId,
    required String title,
    required String body,
    required DateTime sendAt,
    Map<String, String> data = const {},
  }) async {
    try {
      // OneSignal expects UTC ISO-8601: "2024-01-15 09:00:00 UTC"
      final utc = sendAt.toUtc();
      final sendAtStr = '${utc.year}-${_p(utc.month)}-${_p(utc.day)} '
          '${_p(utc.hour)}:${_p(utc.minute)}:00 UTC';

      final payload = {
        'app_id': _kOneSignalAppId,
        'include_subscription_ids': [playerId], // target this device only
        'headings': {'en': title},
        'contents': {'en': body},
        'send_after': sendAtStr,
        'data': data,
        // Android channel — create 'balance_reminders' in OneSignal dashboard
        // or it will fall back to the default channel.
        'android_channel_id': 'balance_reminders',
        'priority': 10,
        'ttl': 86400, // expire after 24 h if not delivered
      };

      final res = await http.post(
        Uri.parse('$_kOneSignalBase/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $_kOneSignalRestKey',
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['id'] as String?;
      } else {
        debugPrint('[Reminder] OneSignal schedule failed: ${res.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[Reminder] _sendScheduledNotification error: $e');
      return null;
    }
  }

  /// Cancels a previously scheduled OneSignal notification.
  Future<void> _cancelOneSignalNotification(String notificationId) async {
    try {
      await http.delete(
        Uri.parse(
            '$_kOneSignalBase/notifications/$notificationId?app_id=$_kOneSignalAppId'),
        headers: {
          'Authorization': 'Basic $_kOneSignalRestKey',
        },
      );
    } catch (e) {
      debugPrint('[Reminder] _cancelOneSignalNotification error: $e');
    }
  }

  // ── Tiny helpers ─────────────────────────────────────────────────────────────

  String _p(int n) => n.toString().padLeft(2, '0');

  String _fmtDate(DateTime d) => '${_p(d.day)}/${_p(d.month)}/${d.year}';
}
