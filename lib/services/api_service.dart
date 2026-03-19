// lib/services/api_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';

class ApiService {
  ApiService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────────
  // HOSTELS
  // ─────────────────────────────────────────────────────────────

  /// Featured hostels (limit 10)
  static Future<List<Hostel>> getFeaturedHostels() async {
    try {
      final snapshot = await _db.collection('hostels').limit(10).get();

      print('📦 Firestore docs found: ${snapshot.docs.length}');

      if (snapshot.docs.isEmpty) return [];

      final hostels = <Hostel>[];
      for (final doc in snapshot.docs) {
        try {
          final hostel = Hostel.fromJson(doc.id, doc.data());
          hostels.add(hostel);
          print('  ✅ Parsed: ${hostel.hostelName}');
        } catch (e) {
          print('  ❌ Failed to parse doc ${doc.id}: $e');
          print('  📄 Data: ${doc.data()}');
        }
      }
      return hostels;
    } catch (e) {
      print('❌ Firestore error: $e');
      rethrow;
    }
  }

  /// All hostels with optional filters
  static Future<List<Hostel>> getHostels({
    String? townFilter,
    String? schoolId,
    String? search,
  }) async {
    Query query = _db.collection('hostels');

    if (townFilter != null && townFilter.isNotEmpty) {
      query = query.where('town', isEqualTo: townFilter);
    }

    if (schoolId != null && schoolId.isNotEmpty) {
      query = query.where('school_id', isEqualTo: schoolId);
    }

    final snapshot = await query.get();

    return snapshot.docs
        .map((doc) =>
            Hostel.fromJson(doc.id, doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Single hostel by ID
  static Future<Hostel?> getHostelById(String id) async {
    final doc = await _db.collection('hostels').doc(id).get();

    if (!doc.exists) return null;

    return Hostel.fromJson(doc.id, doc.data()!);
  }

  // ─────────────────────────────────────────────────────────────
  // ROOMS
  // ─────────────────────────────────────────────────────────────

  static Future<List<Room>> getRooms(String hostelId) async {
    final snapshot = await _db
        .collection('rooms')
        .where('hostel_id', isEqualTo: hostelId)
        .get();

    return snapshot.docs
        .map((doc) => Room.fromJson(doc.id, doc.data()))
        .toList();
  }

  static Future<Room?> getRoomById(String id) async {
    final doc = await _db.collection('rooms').doc(id).get();

    if (!doc.exists) return null;

    return Room.fromJson(doc.id, doc.data()!);
  }

  // ─────────────────────────────────────────────────────────────
  // BOOKINGS
  // ─────────────────────────────────────────────────────────────

  static Future<Booking> createBooking(Map<String, dynamic> payload) async {
    final ref = await _db.collection('bookings').add(payload);

    final snapshot = await ref.get();

    return Booking.fromJson(snapshot.id, snapshot.data()!);
  }

  static Future<List<Booking>> getBookingsByEmail(String email) async {
    final snapshot =
        await _db.collection('bookings').where('email', isEqualTo: email).get();

    return snapshot.docs
        .map((doc) => Booking.fromJson(doc.id, doc.data()))
        .toList();
  }

  static Future<List<Booking>> getBookingsByHostel(String hostelCode) async {
    final snapshot = await _db
        .collection('bookings')
        .where('hostel_code', isEqualTo: hostelCode)
        .get();

    return snapshot.docs
        .map((doc) => Booking.fromJson(doc.id, doc.data()))
        .toList();
  }

  static Future<void> updateBookingStatus(
      String bookingId, String status) async {
    await _db.collection('bookings').doc(bookingId).update({
      'status': status,
    });
  }

  // ─────────────────────────────────────────────────────────────
  // SCHOOLS
  // ─────────────────────────────────────────────────────────────

  static Future<List<School>> getSchools() async {
    final snapshot = await _db.collection('schools').get();

    return snapshot.docs
        .map((doc) => School.fromJson(doc.id, doc.data()))
        .toList();
  }

  static Future<School?> getSchoolById(String id) async {
    final doc = await _db.collection('schools').doc(id).get();

    if (!doc.exists) return null;

    return School.fromJson(doc.id, doc.data()!);
  }

  // ─────────────────────────────────────────────────────────────
  // LANDLORDS
  // ─────────────────────────────────────────────────────────────

  static Future<Landlord?> getLandlordById(String id) async {
    final doc = await _db.collection('landlords').doc(id).get();

    if (!doc.exists) return null;

    return Landlord.fromJson(doc.id, doc.data()!);
  }

  // ─────────────────────────────────────────────────────────────
  // FACILITIES
  // ─────────────────────────────────────────────────────────────

  static Future<List<Facility>> getFacilities(String hostelId) async {
    final snapshot = await _db
        .collection('facilities')
        .where('hostel_id', isEqualTo: hostelId)
        .get();

    return snapshot.docs
        .map((doc) => Facility.fromJson(doc.id, doc.data()))
        .toList();
  }
}
