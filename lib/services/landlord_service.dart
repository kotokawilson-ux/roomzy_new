// lib/services/landlord_service.dart
//
// All Firestore reads & writes scoped to a single landlord.
// Screens pass in the landlordId once (from AuthService.landlordId)
// and this service handles everything else.
// ─────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'dart:async';

class LandlordService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════════════════════
  // LANDLORD PROFILE
  // ═══════════════════════════════════════════════════════════

  /// Fetch the landlord's own document once.
  Future<Landlord?> getLandlord(String landlordId) async {
    try {
      final doc = await _db.collection('landlords').doc(landlordId).get();
      if (!doc.exists || doc.data() == null) return null;
      return Landlord.fromJson(doc.id, doc.data()!);
    } catch (e) {
      debugPrint('LandlordService.getLandlord error: $e');
      return null;
    }
  }

  /// Live stream of the landlord document — for the profile page.
  Stream<Landlord?> streamLandlord(String landlordId) {
    return _db.collection('landlords').doc(landlordId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Landlord.fromJson(doc.id, doc.data()!);
    });
  }

  /// Update the landlord's editable profile fields.
  Future<({bool success, String? error})> updateLandlord({
    required String landlordId,
    required String fullName,
    required String phone,
    String? address,
  }) async {
    try {
      await _db.collection('landlords').doc(landlordId).update({
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        if (address != null) 'address': address.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to update profile: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // HOSTELS
  // ═══════════════════════════════════════════════════════════

  /// Live stream of all hostels owned by this landlord.
  Stream<List<Hostel>> streamHostels(String landlordId) {
    return _db
        .collection('hostels')
        .where('landlord_id', isEqualTo: landlordId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Hostel.fromJson(d.id, d.data())).toList());
  }

  /// Fetch hostels once (for non-reactive use).
  Future<List<Hostel>> getHostels(String landlordId) async {
    try {
      final snap = await _db
          .collection('hostels')
          .where('landlord_id', isEqualTo: landlordId)
          .get();
      return snap.docs.map((d) => Hostel.fromJson(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('LandlordService.getHostels error: $e');
      return [];
    }
  }

  /// Fetch a single hostel.
  Future<Hostel?> getHostel(String hostelId) async {
    try {
      final doc = await _db.collection('hostels').doc(hostelId).get();
      if (!doc.exists || doc.data() == null) return null;
      return Hostel.fromJson(doc.id, doc.data()!);
    } catch (e) {
      debugPrint('LandlordService.getHostel error: $e');
      return null;
    }
  }

  /// Add a new hostel. Returns the new doc ID on success.
  Future<({String? id, String? error})> addHostel(Hostel hostel) async {
    try {
      final ref = await _db.collection('hostels').add({
        ...hostel.toJson(),
        'created_at': FieldValue.serverTimestamp(),
      });
      return (id: ref.id, error: null);
    } catch (e) {
      return (id: null, error: 'Failed to add hostel: $e');
    }
  }

  /// Update an existing hostel.
  Future<({bool success, String? error})> updateHostel(Hostel hostel) async {
    try {
      await _db.collection('hostels').doc(hostel.id).update({
        ...hostel.toJson(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to update hostel: $e');
    }
  }

  /// Delete a hostel and all its rooms in a single batch.
  Future<({bool success, String? error})> deleteHostel(String hostelId) async {
    try {
      final batch = _db.batch();

      // Delete all rooms under this hostel
      final roomsSnap = await _db
          .collection('rooms')
          .where('hostel_id', isEqualTo: hostelId)
          .get();
      for (final doc in roomsSnap.docs) {
        batch.delete(doc.reference);
      }

      // Delete facilities
      final facSnap = await _db
          .collection('facilities')
          .where('hostel_id', isEqualTo: hostelId)
          .get();
      for (final doc in facSnap.docs) {
        batch.delete(doc.reference);
      }

      // Delete the hostel itself
      batch.delete(_db.collection('hostels').doc(hostelId));

      await batch.commit();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to delete hostel: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ROOMS
  // ═══════════════════════════════════════════════════════════

  /// Live stream of all rooms for a specific hostel.
  Stream<List<Room>> streamRooms(String hostelId) {
    return _db
        .collection('rooms')
        .where('hostel_id', isEqualTo: hostelId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Room.fromJson(d.id, d.data())).toList());
  }

  /// Live stream of ALL rooms across all of a landlord's hostels.
  Stream<List<Room>> streamAllRooms(String landlordId) async* {
    // First fetch hostel IDs, then stream rooms for all of them
    final hostels = await getHostels(landlordId);
    if (hostels.isEmpty) {
      yield [];
      return;
    }
    final hostelIds = hostels.map((h) => h.id).toList();

    // Firestore 'whereIn' supports up to 30 values
    yield* _db
        .collection('rooms')
        .where('hostel_id', whereIn: hostelIds.take(30).toList())
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Room.fromJson(d.id, d.data())).toList());
  }

  /// Fetch all rooms for a hostel once.
  Future<List<Room>> getRooms(String hostelId) async {
    try {
      final snap = await _db
          .collection('rooms')
          .where('hostel_id', isEqualTo: hostelId)
          .get();
      return snap.docs.map((d) => Room.fromJson(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('LandlordService.getRooms error: $e');
      return [];
    }
  }

  /// Add a new room. Returns the new doc ID on success.
  Future<({String? id, String? error})> addRoom(Room room) async {
    try {
      final ref = await _db.collection('rooms').add({
        ...room.toJson(),
        'created_at': FieldValue.serverTimestamp(),
      });
      return (id: ref.id, error: null);
    } catch (e) {
      return (id: null, error: 'Failed to add room: $e');
    }
  }

  /// Update a room.
  Future<({bool success, String? error})> updateRoom(Room room) async {
    try {
      await _db.collection('rooms').doc(room.id).update({
        ...room.toJson(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to update room: $e');
    }
  }

  /// Toggle a room's availability on/off.
  Future<({bool success, String? error})> toggleRoomAvailability(
      String roomId, bool available) async {
    try {
      await _db.collection('rooms').doc(roomId).update({
        'available': available,
        'updated_at': FieldValue.serverTimestamp(),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to update availability: $e');
    }
  }

  /// Delete a room.
  Future<({bool success, String? error})> deleteRoom(String roomId) async {
    try {
      await _db.collection('rooms').doc(roomId).delete();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to delete room: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // BOOKINGS
  // ═══════════════════════════════════════════════════════════

  /// Live stream of all bookings across the landlord's hostels.
  /// Ordered by most recent first.
  /// Live stream of all bookings across the landlord's hostels.
  /// Reactively derived from the hostels stream — never goes stale.
  Stream<List<Booking>> streamBookings(String landlordId) async* {
    final hostels = await getHostels(landlordId);
    debugPrint('🏠 hostels: ${hostels.length}');
    if (hostels.isEmpty) {
      yield [];
      return;
    }
    final hostelIds = hostels.map((h) => h.id).take(30).toList();
    debugPrint('🏠 hostelIds: $hostelIds');

    yield* _db
        .collection('bookings')
        .where('hostel_id', whereIn: hostelIds)
        .snapshots()
        .map((snap) {
      debugPrint('📋 snap docs: ${snap.docs.length}');
      return snap.docs.map((d) => Booking.fromJson(d.id, d.data())).toList()
        ..sort((a, b) => b.bookedAt.compareTo(a.bookedAt));
    });
  }

  /// Stream bookings filtered by status: 'booked' | 'confirmed' | 'cancelled' | 'completed'
  Stream<List<Booking>> streamBookingsByStatus(
      String landlordId, String status) async* {
    final hostels = await getHostels(landlordId);
    if (hostels.isEmpty) {
      yield [];
      return;
    }
    final hostelIds = hostels.map((h) => h.id).toList();

    yield* _db
        .collection('bookings')
        .where('hostel_id', whereIn: hostelIds.take(30).toList())
        .where('status', isEqualTo: status)
        .orderBy('booked_at', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Booking.fromJson(d.id, d.data())).toList());
  }

  /// Confirm a booking (booked → confirmed).
  /// Also increments the room's booked count.
  Future<({bool success, String? error})> confirmBooking(
      Booking booking) async {
    try {
      final batch = _db.batch();

      batch.update(_db.collection('bookings').doc(booking.id), {
        'status': 'confirmed',
        'confirmed_at': FieldValue.serverTimestamp(),
      });

      batch.update(_db.collection('rooms').doc(booking.roomId), {
        'booked': FieldValue.increment(booking.slotsBooked),
      });

      await batch.commit();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to confirm booking: $e');
    }
  }

  /// Cancel a booking.
  /// If previously confirmed, decrements the room's booked count.
  Future<({bool success, String? error})> cancelBooking(Booking booking) async {
    try {
      final batch = _db.batch();

      batch.update(_db.collection('bookings').doc(booking.id), {
        'status': 'cancelled',
        'cancelled_at': FieldValue.serverTimestamp(),
      });

      // Only decrement if booking was confirmed (slots were counted)
      if (booking.isConfirmed) {
        batch.update(_db.collection('rooms').doc(booking.roomId), {
          'booked': FieldValue.increment(-booking.slotsBooked),
        });
      }

      await batch.commit();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to cancel booking: $e');
    }
  }

  /// Mark a booking as completed.
  Future<({bool success, String? error})> completeBooking(
      String bookingId) async {
    try {
      await _db.collection('bookings').doc(bookingId).update({
        'status': 'completed',
        'completed_at': FieldValue.serverTimestamp(),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to complete booking: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // FACILITIES
  // ═══════════════════════════════════════════════════════════

  /// Live stream of facilities for a hostel.
  Stream<List<Facility>> streamFacilities(String hostelId) {
    return _db
        .collection('facilities')
        .where('hostel_id', isEqualTo: hostelId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Facility.fromJson(d.id, d.data())).toList());
  }

  /// Add a facility to a hostel.
  Future<({bool success, String? error})> addFacility(Facility facility) async {
    try {
      await _db.collection('facilities').add(facility.toJson());
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to add facility: $e');
    }
  }

  /// Delete a facility.
  Future<({bool success, String? error})> deleteFacility(
      String facilityId) async {
    try {
      await _db.collection('facilities').doc(facilityId).delete();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to delete facility: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // DASHBOARD STATS
  // ═══════════════════════════════════════════════════════════

  /// Returns a single snapshot of key numbers for the dashboard.
  Future<LandlordStats> getDashboardStats(String landlordId) async {
    try {
      final hostels = await getHostels(landlordId);
      final hostelIds = hostels.map((h) => h.id).toList();

      if (hostelIds.isEmpty) {
        return LandlordStats.empty();
      }

      // Rooms
      final roomsSnap = await _db
          .collection('rooms')
          .where('hostel_id', whereIn: hostelIds.take(30).toList())
          .get();
      final rooms =
          roomsSnap.docs.map((d) => Room.fromJson(d.id, d.data())).toList();

      final totalRooms = rooms.length;
      final availableRooms = rooms.where((r) => r.hasSpace).length;
      final occupiedRooms = rooms.where((r) => !r.hasSpace).length;

      // Bookings
      final bookingsSnap = await _db
          .collection('bookings')
          .where('hostel_id', whereIn: hostelIds.take(30).toList())
          .get();
      final bookings = bookingsSnap.docs
          .map((d) => Booking.fromJson(d.id, d.data()))
          .toList();

      final totalBookings = bookings.length;
      final pendingBookings = bookings.where((b) => b.isPending).length;
      final confirmedBookings = bookings.where((b) => b.isConfirmed).length;

      // Recent bookings (last 5)
      final recent = bookings..sort((a, b) => b.bookedAt.compareTo(a.bookedAt));
      final recentBookings = recent.take(5).toList();

      return LandlordStats(
        totalHostels: hostels.length,
        totalRooms: totalRooms,
        availableRooms: availableRooms,
        occupiedRooms: occupiedRooms,
        totalBookings: totalBookings,
        pendingBookings: pendingBookings,
        confirmedBookings: confirmedBookings,
        recentBookings: recentBookings,
      );
    } catch (e) {
      debugPrint('LandlordService.getDashboardStats error: $e');
      return LandlordStats.empty();
    }
  }
}

// ─── LandlordStats ────────────────────────────────────────────
/// Lightweight data class returned by getDashboardStats.
class LandlordStats {
  final int totalHostels;
  final int totalRooms;
  final int availableRooms;
  final int occupiedRooms;
  final int totalBookings;
  final int pendingBookings;
  final int confirmedBookings;
  final List<Booking> recentBookings;

  const LandlordStats({
    required this.totalHostels,
    required this.totalRooms,
    required this.availableRooms,
    required this.occupiedRooms,
    required this.totalBookings,
    required this.pendingBookings,
    required this.confirmedBookings,
    required this.recentBookings,
  });

  factory LandlordStats.empty() => const LandlordStats(
        totalHostels: 0,
        totalRooms: 0,
        availableRooms: 0,
        occupiedRooms: 0,
        totalBookings: 0,
        pendingBookings: 0,
        confirmedBookings: 0,
        recentBookings: [],
      );

  /// Occupancy rate as a value between 0.0 and 1.0.
  double get occupancyRate => totalRooms == 0 ? 0 : occupiedRooms / totalRooms;
}
