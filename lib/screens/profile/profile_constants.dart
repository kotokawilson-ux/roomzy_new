// lib/profile/profile_constants.dart
// ─────────────────────────────────────────────────────────────────────────────
// All colour tokens, text styles, and tiny stateless helpers used across
// every profile file.  Import this file in every other profile_*.dart file.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
const Color kTeal = Color(0xFF00897B);
const Color kTealDark = Color(0xFF00695C);
const Color kTealLight = Color(0xFFE0F2F1);
const Color kAccent = Color(0xFFFF6B35);
const Color kGold = Color(0xFFFFB300);
const Color kBg = Color(0xFFF4F7FA);
const Color kSurface = Colors.white;
const Color kBorder = Color(0xFFEAEEF3);
const Color kTextPrimary = Color(0xFF0D1B2A);
const Color kTextSecond = Color(0xFF5C6B7A);
// Alias so every file can use either name without red lines
const Color kTextSecondary = kTextSecond;
const Color kTextTertiary = Color(0xFFB0BEC5);
const Color kRed = Color(0xFFE53935);

// Per-section icon-background colours
const Color kPurpleBg = Color(0xFFF3E5F5);
const Color kPurple = Color(0xFF7B1FA2);
const Color kBlueBg = Color(0xFFE3F2FD);
const Color kBlue = Color(0xFF1565C0);
const Color kCyanBg = Color(0xFFE0F7FA);
const Color kCyan = Color(0xFF00838F);
const Color kGreenBg = Color(0xFFE8F5E9);
const Color kGreen = Color(0xFF2E7D32);
const Color kSlatesBg = Color(0xFFECEFF1);
const Color kSlate = Color(0xFF37474F);
const Color kDeepPurpleBg = Color(0xFFF3E5F5);
const Color kDeepPurple = Color(0xFF6A1B9A);
const Color kGoldBg = Color(0xFFFFF8E1);
const Color kAccentBg = Color(0xFFFFF0EB);
const Color kRedBg = Color(0xFFFFEBEE);

// ── App version ────────────────────────────────────────────────────────────────
const String kAppVersion = '1.0.0';

// ── Text styles ────────────────────────────────────────────────────────────────
abstract final class KText {
  // headings
  static const h1 = TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      letterSpacing: -.8);
  static const h2 = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w900,
      color: kTextPrimary,
      letterSpacing: -.5);
  static const sectionTitle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: kTextPrimary,
      letterSpacing: -.3);

  // body
  static const body = TextStyle(fontSize: 14, color: kTextPrimary);
  static const bodyS = TextStyle(fontSize: 13, color: kTextSecond);
  static const bodyXS =
      TextStyle(fontSize: 12, color: kTextSecond, height: 1.4);
  static const caption = TextStyle(
      fontSize: 11, color: kTextTertiary, fontWeight: FontWeight.w600);

  // emphasis
  static const labelLg =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kTextPrimary);
  static const labelMd =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTextPrimary);
  static const labelSm = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
  static const labelXS = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);

  // on-dark
  static const onDarkTitle = TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      letterSpacing: -1.5);
  static const onDarkSub =
      TextStyle(fontSize: 13, color: Color(0xA6FFFFFF)); // 65 % white
  static const onDarkCaption = TextStyle(
      fontSize: 11,
      color: Color(0xA6FFFFFF),
      fontWeight: FontWeight.w600,
      letterSpacing: .5);
  static const onDarkValue =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white);
}

// ── Route constants ────────────────────────────────────────────────────────────
abstract final class KRoutes {
  static const login = '/login';
  static const explore = '/explore';
  static const bookings = '/bookings';
  static const saved = '/saved';
  static const payments = '/payments';
  static const support = '/support';
  static const documents = '/documents';
  static const help = '/help';
  // Profile settings routes
  static const changePassword = '/change-password';
  static const verifyStudent = '/verify-student';
  static const language = '/language';
  static const appearance = '/appearance';
  static const privacy = '/privacy';
  static const rateApp = '/rate-app';
  static const about = '/about';
}

// ── Decoration helpers ─────────────────────────────────────────────────────────
/// Standard card decoration (white, rounded, subtle shadow).
BoxDecoration kCardDecoration({Color? borderColor}) => BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: borderColor ?? kBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .05),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    );

/// Teal gradient used on the hero header.
const kHeroGradient = LinearGradient(
  colors: [Color(0xFF004D40), kTealDark, kTeal],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Teal gradient used on the loyalty card (slightly wider).
const kLoyaltyGradient = LinearGradient(
  colors: [Color(0xFF004D40), kTealDark, kTeal, Color(0xFF26A69A)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// ── Tier model ─────────────────────────────────────────────────────────────────
class LoyaltyTier {
  const LoyaltyTier({
    required this.label,
    required this.min,
    required this.max,
    required this.color,
  });
  final String label;
  final int min;
  final int max; // for Platinum, max == min (no upper bound)
  final Color color;
}

const kTiers = [
  LoyaltyTier(label: 'Bronze', min: 0, max: 1000, color: Color(0xFFCD7F32)),
  LoyaltyTier(label: 'Silver', min: 1000, max: 2000, color: Color(0xFF9E9E9E)),
  LoyaltyTier(label: 'Gold', min: 2000, max: 3000, color: kGold),
  LoyaltyTier(
      label: 'Platinum', min: 3000, max: 3000, color: Color(0xFF80CBC4)),
];

/// Returns the tier the user currently belongs to.
LoyaltyTier tierFor(int pts) =>
    kTiers.lastWhere((t) => pts >= t.min, orElse: () => kTiers.first);

// ── Profile-completion helper ──────────────────────────────────────────────────
/// Returns how many of the 6 profile fields are filled in.
int completionCount(Map<String, dynamic> data, String fallbackEmail) {
  final fields = <String?>[
    data['email'] as String? ?? fallbackEmail,
    data['phone'] as String?,
    data['photoUrl'] as String?,
    data['studentId'] as String?,
    data['emergencyContact'] as String?,
    data['university'] as String?,
  ];
  return fields.where((v) => (v ?? '').isNotEmpty).length;
}

/// Human-readable labels matching the order in [completionCount].
const kCompletionLabels = [
  'Email',
  'Phone',
  'Photo',
  'ID Card',
  'Emergency',
  'University',
];

// ── Referral-code generator ────────────────────────────────────────────────────
// Fix #5: removed `// ignore: deprecated_member_use` suppressor and the
// reliance on hashCode for seeding.
//
// The old approach used `uid.hashCode ^ uid.codeUnits.fold(...)`.
// Problems:
//   1. hashCode is NOT stable across Dart VM restarts or platforms —
//      the same UID can produce a different code on iOS vs Android.
//   2. Suppressing a deprecation warning silently rather than fixing it
//      means you'll break when the deprecated API is removed.
//
// Fix: derive the seed purely from codeUnits (stable, no hashCode needed).
// The same UID will always produce the same 8-character code on every
// platform and Dart version.

/// Generates a deterministic 8-character referral code from the user's UID.
String generateReferralCode(String uid) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  // Stable seed: fold over codeUnits only — no hashCode dependency.
  final seed = uid.codeUnits.fold(0, (int a, int b) => a * 31 + b);
  final rng = _SeededRandom(seed);
  return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
}

/// Simple linear-congruential PRNG so the code is deterministic across restarts.
class _SeededRandom {
  _SeededRandom(int seed) : _state = seed.abs() & 0x7FFFFFFF;
  int _state;
  int nextInt(int max) {
    _state = (1664525 * _state + 1013904223) & 0x7FFFFFFF;
    return _state % max;
  }
}

const List<Color> kHeroGradientColors = [
  Color(0xFF1A1A2E),
  Color(0xFF16213E),
  Color(0xFF0F3460),
  Color(0xFF533483),
];
