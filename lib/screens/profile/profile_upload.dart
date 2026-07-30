// lib/profile/profile_upload.dart
// ─────────────────────────────────────────────────────────────────────────────
// Cloudinary image upload with progress + file validation, and the
// RingPainter used by the profile-completion card.
//
// HeroPainter was removed here — it was never referenced anywhere;
// profile_hero.dart paints its own background via _MeshNoisePainter.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ── Config ────────────────────────────────────────────────────────────────────
// Put your real values in a .env / build-config and inject via --dart-define.
// Never hard-code credentials in source control.
const _kCloudName =
    String.fromEnvironment('CLOUDINARY_CLOUD_NAME', defaultValue: 'dfv9yibba');
const _kUploadPreset = String.fromEnvironment('CLOUDINARY_PRESET',
    defaultValue: 'avatars_unsigned');
const _kFolder = 'avatars';

// Validation limits
const _kMaxBytes = 5 * 1024 * 1024; // 5 MB
const _kAllowedExts = {'.jpg', '.jpeg', '.png', '.webp'};

// ── Validation ─────────────────────────────────────────────────────────────────
class UploadValidationException implements Exception {
  const UploadValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Throws [UploadValidationException] if the file fails type or size checks.
/// Type is checked first (zero-cost string op) so we never hit the network
/// with an invalid type; size is checked second.
void validateUpload(Uint8List bytes, String filename) {
  final ext = _extension(filename).toLowerCase();
  if (!_kAllowedExts.contains(ext)) {
    throw UploadValidationException(
      'Unsupported file type "$ext". Use JPG, PNG, or WebP.',
    );
  }
  if (bytes.length > _kMaxBytes) {
    throw const UploadValidationException('Image must be under 5 MB.');
  }
}

String _extension(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot == -1 ? '' : filename.substring(dot);
}

// ── Upload ─────────────────────────────────────────────────────────────────────
/// Uploads [bytes] to Cloudinary and returns the secure URL, or throws.
///
/// [onProgress] receives values from 0.0 → 1.0 as bytes are streamed.
Future<String> cloudinaryUpload(
  Uint8List bytes,
  String filename, {
  void Function(double progress)? onProgress,
}) async {
  validateUpload(bytes, filename);

  final safeFilename = filename.isNotEmpty
      ? filename
      : 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_kCloudName/image/upload',
  );

  final request = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _kUploadPreset
    ..fields['folder'] = _kFolder
    ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: safeFilename));

  final streamed = await request.send(); // throws on network error

  // BytesBuilder amortises allocations like a StringBuffer: O(n) total,
  // vs. List<int> + addAll which copies the whole accumulated list on
  // every chunk (O(n²)).
  final builder = BytesBuilder(copy: false);
  int received = 0;
  final total = streamed.contentLength ?? bytes.length;

  await for (final chunk in streamed.stream) {
    builder.add(chunk);
    received += chunk.length;
    // Clamp to 0.95 so the caller's UI doesn't flash "done" before we parse.
    onProgress?.call((received / total).clamp(0.0, 0.95));
  }

  if (streamed.statusCode != 200) {
    final body = utf8.decode(builder.takeBytes(), allowMalformed: true);
    debugPrint('Cloudinary error ${streamed.statusCode}: $body');
    throw Exception('Upload failed (HTTP ${streamed.statusCode}).');
  }

  final responseBytes = builder.takeBytes();
  onProgress?.call(1.0); // only signal done after parse-ready

  final json = jsonDecode(utf8.decode(responseBytes)) as Map<String, dynamic>;
  final url = json['secure_url'] as String?;
  if (url == null || url.isEmpty) {
    throw Exception('Cloudinary returned no URL.');
  }
  return url;
}

// ── Painter ────────────────────────────────────────────────────────────────────

/// Animated ring used in the profile-completion widget.
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.progress,
    required this.foreground,
    required this.background,
  });

  final double progress;
  final Color foreground;
  final Color background;

  static const _strokeWidth = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track (background arc)
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = background
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Progress arc
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = foreground
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress ||
      old.foreground != foreground ||
      old.background != background;
}
