// lib/services/booking_storage_service.dart

import 'package:shared_preferences/shared_preferences.dart';

/// Saves booking IDs locally on the device.
/// Used to show only the current user's bookings on the bookings screen.
class BookingStorageService {
  static const _key = 'my_booking_ids';

  /// Save a new booking ID to local storage
  static Future<void> saveBookingId(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    if (!existing.contains(bookingId)) {
      existing.add(bookingId);
      await prefs.setStringList(_key, existing);
    }
  }

  /// Get all locally saved booking IDs
  static Future<List<String>> getBookingIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// Clear all saved booking IDs (for testing/logout)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
