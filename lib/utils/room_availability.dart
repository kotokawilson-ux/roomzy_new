// lib/utils/room_availability.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Watches the `rooms` collection for a set of hostel IDs and computes a
/// live "available rooms" count per hostel — the same logic
/// hostel_detail_screen.dart already uses per-room (capacity - booked > 0),
/// instead of trusting the stale `rooms_available` field on the hostel doc.
class RoomAvailabilityWatcher {
  final void Function(Map<String, int> counts) onUpdate;
  final List<StreamSubscription<QuerySnapshot>> _subs = [];
  final Map<String, Map<String, int>> _chunkCounts = {};

  RoomAvailabilityWatcher({required this.onUpdate});

  void watch(List<String> hostelIds) {
    cancel();
    if (hostelIds.isEmpty) {
      onUpdate({});
      return;
    }

    // Firestore whereIn supports max 30 values — chunk if the list is bigger.
    const chunkSize = 30;
    for (var i = 0; i < hostelIds.length; i += chunkSize) {
      final end =
          (i + chunkSize > hostelIds.length) ? hostelIds.length : i + chunkSize;
      final chunk = hostelIds.sublist(i, end);
      final chunkKey = chunk.join(',');

      final sub = FirebaseFirestore.instance
          .collection('rooms')
          .where('hostel_id', whereIn: chunk)
          .snapshots()
          .listen((snapshot) {
        final counts = <String, int>{};
        for (final id in chunk) {
          counts[id] = 0; // ensure every requested hostel has an entry
        }
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final hostelId = data['hostel_id'] as String?;
          if (hostelId == null) continue;

          final capacity = (data['capacity'] as num?)?.toInt() ?? 0;
          final booked = (data['booked'] as num?)?.toInt() ?? 0;
          final isAvailable = data['available'] as bool? ?? true;

          if (isAvailable && (capacity - booked) > 0) {
            counts[hostelId] = (counts[hostelId] ?? 0) + 1;
          }
        }
        _chunkCounts[chunkKey] = counts;
        _emit();
      });

      _subs.add(sub);
    }
  }

  void _emit() {
    final merged = <String, int>{};
    for (final counts in _chunkCounts.values) {
      merged.addAll(counts);
    }
    onUpdate(merged);
  }

  void cancel() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _chunkCounts.clear();
  }
}
