// lib/services/payment_notify_service.dart
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';

class PaymentNotifyService {
  /// Fire-and-forget. Call this right after ANY successful payment write
  /// (batch.commit() / transaction) — deposit, balance installment, or
  /// full payment, MoMo or manual/verified. Never awaited by the caller,
  /// never allowed to throw into the success flow.
  static void notifyPaymentSuccess({
    required String bookingId,
    String? userId,
    required String hostelName,
    required String roomNumber,
    required double amountPaid,
    required double balance,
    required bool isFullyPaid,
  }) {
    http
        .post(
      Uri.parse('$_kBackendUrl/notify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': isFullyPaid ? 'booking_confirmed' : 'deposit_paid',
        'bookingId': bookingId,
        'userId': userId ?? FirebaseAuth.instance.currentUser?.uid ?? '',
        'hostelName': hostelName,
        'roomNumber': roomNumber,
        'amountPaid': amountPaid,
        'balance': balance,
        'isFullyPaid': isFullyPaid,
      }),
    )
        .catchError((e) {
      debugPrint('payment success notify failed (non-fatal): $e');
      return http.Response('', 200);
    });
  }
}
