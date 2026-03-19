// ignore: unused_import
import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────
/// AppConstants
/// Central place for app configuration such as API URLs,
/// timeouts, keys, and shared constants.
///
/// All PHP files are flat inside /api/ — no subfolders.
/// Server: https://roomzyfind.great-site.net
/// ─────────────────────────────────────────────────────────────
class AppConstants {
  AppConstants._(); // Prevent instantiation

  // ── App Info ────────────────────────────────────────────────
  static const String appName = 'RoomzyFind';
  static const String appTagline = 'Find Your Perfect Student Home';

  // ── API Base URL ────────────────────────────────────────────
  static const String baseUrl = 'https://roomzyfind.great-site.net/api';

  /// Used to build full image URLs from relative database paths.
  /// Example:
  /// buildImageUrl('images/hostels/img_1.jpg')
  /// → 'https://roomzyfind.great-site.net/api/images/hostels/img_1.jpg'
  static const String imageBase = baseUrl;

  // ── Network Timeouts ────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  // ── Authentication Endpoints ───────────────────────────────
  static const String loginUser = '$baseUrl/login_user.php';
  static const String loginLandlord = '$baseUrl/login_landlord.php';
  static const String loginAdmin = '$baseUrl/login_admin.php';
  static const String registerUser = '$baseUrl/register_user.php';

  // ── Hostel Endpoints ───────────────────────────────────────
  static const String getHostels = '$baseUrl/get_hostels.php';
  static const String getHostelById = '$baseUrl/get_hostel.php';
  static const String getFeaturedHostels = '$baseUrl/get_featured_hostels.php';

  // ── Room Endpoints ─────────────────────────────────────────
  static const String getRoomsByHostel = '$baseUrl/get_rooms.php';

  // ── Booking Endpoints ──────────────────────────────────────
  static const String createBooking = '$baseUrl/create_booking.php';
  static const String getUserBookings = '$baseUrl/get_user_bookings.php';
  static const String cancelBooking = '$baseUrl/cancel_booking.php';

  // ── Schools ────────────────────────────────────────────────
  static const String getSchools = '$baseUrl/get_schools.php';

  // ── Landlord Endpoints ─────────────────────────────────────
  static const String landlordHostels = '$baseUrl/get_my_hostels.php';
  static const String addHostel = '$baseUrl/add_hostel.php';
  static const String addRoom = '$baseUrl/add_room.php';

  // ── Admin Endpoints ────────────────────────────────────────
  static const String getDashboardStats = '$baseUrl/get_stats.php';
  static const String getActivityLogs = '$baseUrl/get_logs.php';

  // ── Contact Endpoint ───────────────────────────────────────
  static const String sendContact = '$baseUrl/send_message.php';

  // ── SharedPreferences Keys ─────────────────────────────────
  static const String keyUserId = 'user_id';
  static const String keyUserName = 'user_name';
  static const String keyUserEmail = 'user_email';
  static const String keyUserRole = 'user_role';
  static const String keyIsLoggedIn = 'is_logged_in';

  // ── User Roles ─────────────────────────────────────────────
  static const String roleStudent = 'student';
  static const String roleLandlord = 'landlord';
  static const String roleAdmin = 'admin';

  // ── Booking Status ─────────────────────────────────────────
  static const String bookingPending = 'pending';
  static const String bookingConfirmed = 'confirmed';
  static const String bookingCancelled = 'cancelled';

  // ── Room Status ────────────────────────────────────────────
  static const String roomAvailable = 'available';
  static const String roomOccupied = 'occupied';
}
