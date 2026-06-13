// lib/screens/bookings/booking_confirm_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

// ─── Constants ───────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF0F766E);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kOrange = Color(0xFFEA580C);
const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';

// ─────────────────────────────────────────────────────────────────────────────
// BOOKING CONFIRM SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class BookingConfirmScreen extends StatefulWidget {
  final String bookingId;
  const BookingConfirmScreen({super.key, required this.bookingId});

  @override
  State<BookingConfirmScreen> createState() => _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends State<BookingConfirmScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _booking;
  bool _loading = true;
  String? _error;

  late AnimationController _anim;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _scale = Tween<double>(begin: 0.4, end: 1)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.elasticOut));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeIn));
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      if (!doc.exists) throw Exception('Booking not found');
      if (!mounted) return;
      setState(() {
        _booking = {'id': doc.id, ...doc.data()!};
        _loading = false;
      });
      _anim.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: const Text('Booking Receipt',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_rounded),
            tooltip: 'All Bookings',
            onPressed: () => context.go('/bookings'),
          ),
        ],
      ),
      body: _loading
          ? _buildShimmer()
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  // ── Shimmer ──────────────────────────────────────────────────────────────
  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const SizedBox(height: 20),
          Container(
              height: 150,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24))),
          const SizedBox(height: 16),
          Container(
              height: 200,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 16),
          Container(
              height: 140,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20))),
        ]),
      ),
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 56, color: _kRed),
        const SizedBox(height: 12),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 20),
        ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: const Text('Try Again')),
      ]),
    ));
  }

  // ── Content ──────────────────────────────────────────────────────────────
  Widget _buildContent() {
    final b = _booking!;
    final bookingRef = (b['id'] as String).toUpperCase().substring(0, 8);
    final status = b['status'] ?? 'pending';
    final paymentStatus = b['payment_status'] ?? 'pending';
    final isPaid = paymentStatus == 'paid' ||
        paymentStatus == 'fully_paid' ||
        paymentStatus == 'deposit_paid';
    final isConfirmed = status == 'confirmed';
    final name = b['name'] ?? '—';
    final email = b['email'] ?? '—';
    final phone = b['phone'] ?? '—';
    final momoNumber = b['momo_number'] ?? '—';
    final momoType = b['momo_type'] ?? 'Mobile Money';
    final hostelName = b['hostel_name'] ?? '—';
    final roomNumber = b['room_number'] ?? '—';
    final slots = b['slots_booked'] ?? 1;
    final amount = (b['amount'] ?? 0.0).toDouble();
    final payRef = b['payment_reference'] ?? '—';
    final notes = b['notes'] ?? '';
    final hostelId = b['hostel_id'] ?? '';
    final hostelPhone = b['hostel_phone'] ?? '';
    final amountPaid = (b['amount_paid'] ?? 0.0).toDouble();
    final balance = (b['balance'] ?? 0.0).toDouble();
    final depositAmount = (b['deposit_amount'] ?? 0.0).toDouble();
    final isFullyPaid =
        paymentStatus == 'fully_paid' || (isPaid && balance == 0);
    final isDepositPaid = paymentStatus == 'deposit_paid';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 8),

        // ── Status Hero Card ────────────────────────────────────────
        FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isConfirmed && isFullyPaid
                      ? [_kGreen, const Color(0xFF15803D)]
                      : isConfirmed && isDepositPaid
                          ? [_kPrimary, const Color(0xFF0D9488)]
                          : status == 'cancelled' || status == 'declined'
                              ? [_kRed, const Color(0xFFB91C1C)]
                              : [_kOrange, const Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: (isConfirmed && isPaid ? _kGreen : _kOrange)
                        .withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: Icon(
                    isConfirmed && isFullyPaid
                        ? Icons.check_circle_rounded
                        : isConfirmed && isDepositPaid
                            ? Icons.verified_rounded
                            : status == 'cancelled' || status == 'declined'
                                ? Icons.cancel_rounded
                                : isDepositPaid
                                    ? Icons.lock_open_rounded
                                    : Icons.pending_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isConfirmed && isFullyPaid
                      ? 'Booking Confirmed & Paid!'
                      : isConfirmed && isDepositPaid
                          ? 'Confirmed — Deposit Paid'
                          : status == 'cancelled' || status == 'declined'
                              ? 'Booking Cancelled'
                              : isDepositPaid
                                  ? 'Deposit Paid — Awaiting Confirmation'
                                  : 'Booking Pending Payment',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  isConfirmed && isFullyPaid
                      ? 'Your room is fully secured. See you soon!'
                      : isConfirmed && isDepositPaid
                          ? 'Balance of GHS ${balance.toStringAsFixed(2)} due on arrival.'
                          : status == 'cancelled' || status == 'declined'
                              ? 'This booking has been cancelled'
                              : isDepositPaid
                                  ? 'Deposit received. Awaiting landlord confirmation.'
                                  : 'Complete your MoMo payment to confirm',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.85)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Booking ref pill — tap to copy
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: bookingRef));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Booking ID copied!'),
                        duration: Duration(seconds: 2)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.tag_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('REF: $bookingRef',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 1.5)),
                      const SizedBox(width: 8),
                      const Icon(Icons.copy_rounded,
                          size: 14, color: Colors.white70),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Payment details card ────────────────────────────────────
        _Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _CardHeader(icon: Icons.payments_rounded, title: 'Payment Details'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _PayStatusBox(
              label: 'Booking Status',
              value: status.toUpperCase(),
              color: status == 'confirmed'
                  ? _kGreen
                  : status == 'cancelled'
                      ? _kRed
                      : _kOrange,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _PayStatusBox(
              label: 'Payment Status',
              value: paymentStatus == 'fully_paid'
                  ? '✓ FULLY PAID'
                  : paymentStatus == 'deposit_paid'
                      ? '⬤ DEPOSIT PAID'
                      : paymentStatus == 'paid'
                          ? '✓ PAID'
                          : 'PENDING',
              color: paymentStatus == 'fully_paid' || paymentStatus == 'paid'
                  ? _kGreen
                  : paymentStatus == 'deposit_paid'
                      ? _kOrange
                      : _kRed,
            )),
          ]),
          const SizedBox(height: 16),
          _DetailRow(label: 'Payment Method', value: momoType),
          _DetailRow(label: 'MoMo Number', value: momoNumber),
          _DetailRow(
              label: 'Total Amount', value: 'GHS ${amount.toStringAsFixed(2)}'),
          _DetailRow(
              label: 'Amount Paid',
              value: 'GHS ${amountPaid.toStringAsFixed(2)}'),
          if (balance > 0)
            _DetailRow(
                label: 'Balance Due',
                value: 'GHS ${balance.toStringAsFixed(2)}'),
          if (depositAmount > 0)
            _DetailRow(
                label: 'Deposit',
                value: 'GHS ${depositAmount.toStringAsFixed(2)}'),
          if (payRef != '—') _DetailRow(label: 'Paystack Ref', value: payRef),
        ])),

        // ── Balance payment card (outside the details card) ─────────
        if (balance > 0 && status != 'cancelled' && status != 'declined') ...[
          const SizedBox(height: 16),
          _BalancePaymentCard(
            bookingId: widget.bookingId,
            balance: balance,
            totalAmount: amount,
            amountPaid: amountPaid,
            depositAmount: depositAmount,
            momoNumber: momoNumber,
            momoProvider: b['momo_provider'] ?? 'mtn',
            hostelId: b['hostel_id'] ?? '',
            roomId: b['room_id'] ?? '',
            onPaymentComplete: _load,
          ),
        ],

        const SizedBox(height: 16),

        // ── Booking details card ────────────────────────────────────
        _Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _CardHeader(
              icon: Icons.receipt_long_rounded, title: 'Booking Details'),
          const SizedBox(height: 16),
          _DetailRow(label: 'Hostel', value: hostelName),
          _DetailRow(label: 'Room No.', value: roomNumber),
          _DetailRow(
              label: 'Slots Booked',
              value: '$slots slot${slots > 1 ? 's' : ''}'),
          if (notes.isNotEmpty) _DetailRow(label: 'Notes', value: notes),
        ])),

        const SizedBox(height: 16),

        // ── Guest details card ──────────────────────────────────────
        _Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _CardHeader(icon: Icons.person_rounded, title: 'Guest Details'),
          const SizedBox(height: 16),
          _DetailRow(label: 'Name', value: name),
          _DetailRow(label: 'Email', value: email),
          _DetailRow(label: 'Phone', value: phone),
        ])),

        const SizedBox(height: 20),

        // ── Action buttons ──────────────────────────────────────────
        if (hostelPhone.isNotEmpty) ...[
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:$hostelPhone')),
                icon: const Icon(Icons.phone_rounded),
                label: const Text('Call Hostel',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              )),
          const SizedBox(height: 12),
        ],

        if (hostelId.isNotEmpty) ...[
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go('/hostels/$hostelId'),
                icon: const Icon(Icons.apartment_rounded),
                label: const Text('View Hostel',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              )),
          const SizedBox(height: 12),
        ],

        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/bookings'),
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('All My Bookings',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black54,
                side: const BorderSide(color: Colors.black12),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            )),

        const SizedBox(height: 12),

        SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Back to Home',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.black38,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            )),

        const SizedBox(height: 24),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BALANCE PAYMENT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _BalancePaymentCard extends StatefulWidget {
  final String bookingId;
  final double balance;
  final double totalAmount;
  final double amountPaid;
  final double depositAmount;
  final String momoNumber;
  final String momoProvider;
  final String hostelId;
  final String roomId;
  final VoidCallback onPaymentComplete;

  const _BalancePaymentCard({
    required this.bookingId,
    required this.balance,
    required this.totalAmount,
    required this.amountPaid,
    required this.depositAmount,
    required this.momoNumber,
    required this.momoProvider,
    required this.hostelId,
    required this.roomId,
    required this.onPaymentComplete,
  });

  @override
  State<_BalancePaymentCard> createState() => _BalancePaymentCardState();
}

class _BalancePaymentCardState extends State<_BalancePaymentCard> {
  bool _expanded = false;
  int _payMode = 0; // 0 = full balance, 1 = custom
  double _customAmount = 0;
  final _customCtrl = TextEditingController();
  final _momoCtrl = TextEditingController();
  String _provider = 'mtn';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _momoCtrl.text = widget.momoNumber;
    _provider = widget.momoProvider;
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _momoCtrl.dispose();
    super.dispose();
  }

  double get _amountToPay {
    if (_payMode == 0) return widget.balance;
    return _customAmount.clamp(100.0, widget.balance);
  }

  Future<void> _pay() async {
    if (_momoCtrl.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid MoMo number'),
        backgroundColor: _kRed,
      ));
      return;
    }

    setState(() => _busy = true);
    try {
      final ref = 'RZF-BAL-${DateTime.now().millisecondsSinceEpoch}';
      final isTest = const {
        '0551234987',
        '0571234987',
        '0201234987',
        '0261234987',
      }.contains(_momoCtrl.text.trim().replaceAll(' ', ''));

      // ── Read booking for commission fields ──────────────────────────────
      final bookingDoc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      final bData = bookingDoc.data()!;

      final commissionOwed = (bData['commission_owed'] as num?)?.toDouble() ??
          (widget.totalAmount * 0.05);
      final commissionCollected =
          (bData['commission_collected'] as num?)?.toDouble() ?? 0.0;
      final commissionRemaining = commissionOwed - commissionCollected;
      final paymentCount = (bData['payment_count'] as num?)?.toInt() ?? 1;
      final newTotalPaid = widget.amountPaid + _amountToPay;
      final isFinalPayment = newTotalPaid >= widget.totalAmount;

      final commissionThisPayment = isFinalPayment ? commissionRemaining : 0.0;
      final landlordGets = _amountToPay - commissionThisPayment;
      final newBalance =
          (widget.totalAmount - newTotalPaid).clamp(0.0, widget.totalAmount);

      // ── Test mode: skip backend entirely ───────────────────────────────
      if (isTest) {
        await Future.delayed(const Duration(seconds: 2));
      } else {
        // ── Charge via backend ──────────────────────────────────────────
        final chargeRes = await http.post(
          Uri.parse('$_kBackendUrl/charge-momo'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'bookingId': widget.bookingId,
            'email': bData['email'],
            'amount': _amountToPay,
            'phone': _momoCtrl.text.trim(),
            'provider': _provider == 'mtn' ? 'mtn' : 'vod',
            'reference': ref,
            'isBalancePayment': true,
          }),
        );

        final chargeData = jsonDecode(chargeRes.body);
        if (chargeData['error'] != null) throw Exception(chargeData['error']);

        // ── Poll for confirmation ─────────────────────────────────────────
        bool confirmed = false;
        for (int i = 0; i < 12; i++) {
          await Future.delayed(const Duration(seconds: 5));
          if (!mounted) return;
          final verifyRes = await http.post(
            Uri.parse('$_kBackendUrl/verify-payment'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'reference': ref}),
          );
          final vData = jsonDecode(verifyRes.body);
          if (vData['status'] == 'success') {
            confirmed = true;
            break;
          }
          if (vData['status'] == 'failed') break;
        }

        if (!confirmed) {
          throw Exception(
              'Payment not confirmed. Check your MoMo and try again.');
        }
      }

      // ── Update Firestore ────────────────────────────────────────────────
      final bookingRef = FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId);

      await FirebaseFirestore.instance.runTransaction((txn) async {
        txn.update(bookingRef, {
          'amount_paid': newTotalPaid,
          'balance': newBalance,
          'payment_status': isFinalPayment ? 'fully_paid' : 'deposit_paid',
          'status': 'confirmed',
          'commission_collected': commissionCollected + commissionThisPayment,
          'commission_remaining': commissionRemaining - commissionThisPayment,
          'payment_count': FieldValue.increment(1),
          'last_paid_at': FieldValue.serverTimestamp(),
          if (isFinalPayment) 'fully_paid_at': FieldValue.serverTimestamp(),
        });
      });

      // ── Record in payments subcollection (outside transaction) ──────────
      await bookingRef.collection('payments').add({
        'amount': _amountToPay,
        'commission_taken': commissionThisPayment,
        'landlord_received': landlordGets,
        'payment_number': paymentCount + 1,
        'is_first': false,
        'is_final': isFinalPayment,
        'method': 'momo',
        'provider': _provider,
        'reference': ref,
        'status': 'paid',
        'note': isFinalPayment
            ? 'Final payment — balance cleared'
            : 'Partial balance payment',
        'is_test': isTest,
        'paid_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isFinalPayment
            ? isTest
                ? '🧪 Test: Balance cleared! Fully paid.'
                : '🎉 Balance cleared! Fully paid.'
            : 'Payment of GHS ${_amountToPay.toStringAsFixed(2)} recorded.'),
        backgroundColor: _kGreen,
      ));
      widget.onPaymentComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment failed: $e'),
        backgroundColor: _kRed,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kOrange.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: _kOrange.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: [
        // ── Header — always visible ───────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _kOrange.withOpacity(0.06),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(20),
                bottom: _expanded ? Radius.zero : const Radius.circular(20),
              ),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _kOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_rounded,
                    color: _kOrange, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Balance Due',
                          style: TextStyle(
                              fontSize: 12,
                              color: _kOrange,
                              fontWeight: FontWeight.w600)),
                      Text(
                        'GHS ${widget.balance.toStringAsFixed(2)} remaining',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: _kDark),
                      ),
                    ]),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  _expanded ? 'Close' : 'Pay Now',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ),

        // ── Expandable body ───────────────────────────────────────────────
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Pay mode selector
              const Text('How much to pay?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kDark)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _payMode = 0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _payMode == 0
                            ? _kGreen.withOpacity(0.08)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _payMode == 0
                              ? _kGreen.withOpacity(0.5)
                              : const Color(0xFFE2E8F0),
                          width: _payMode == 0 ? 1.5 : 1,
                        ),
                      ),
                      child: Column(children: [
                        Icon(Icons.check_circle_rounded,
                            color: _payMode == 0 ? _kGreen : Colors.grey[400],
                            size: 22),
                        const SizedBox(height: 6),
                        Text('Full Balance',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _payMode == 0 ? _kGreen : _kDark)),
                        Text('GHS ${widget.balance.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: _payMode == 0
                                    ? _kGreen
                                    : Colors.grey[500])),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _payMode = 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _payMode == 1
                            ? _kPrimary.withOpacity(0.08)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _payMode == 1
                              ? _kPrimary.withOpacity(0.5)
                              : const Color(0xFFE2E8F0),
                          width: _payMode == 1 ? 1.5 : 1,
                        ),
                      ),
                      child: Column(children: [
                        Icon(Icons.tune_rounded,
                            color: _payMode == 1 ? _kPrimary : Colors.grey[400],
                            size: 22),
                        const SizedBox(height: 6),
                        Text('Custom Amount',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _payMode == 1 ? _kPrimary : _kDark)),
                        Text('Partial payment',
                            style: TextStyle(
                                fontSize: 11,
                                color: _payMode == 1
                                    ? _kPrimary
                                    : Colors.grey[500])),
                      ]),
                    ),
                  ),
                ),
              ]),

              // Custom amount field
              if (_payMode == 1) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _customCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) =>
                      setState(() => _customAmount = double.tryParse(v) ?? 0),
                  decoration: InputDecoration(
                    labelText: 'Amount (GHS)',
                    hintText:
                        'Min GHS 100 · Max GHS ${widget.balance.toStringAsFixed(2)}',
                    prefixIcon: const Icon(Icons.edit_rounded,
                        color: _kPrimary, size: 18),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _kPrimary, width: 1.5)),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // MoMo provider
              const Text('Mobile Money Network',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kDark)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _provider = 'mtn'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _provider == 'mtn'
                            ? _kPrimary.withOpacity(0.08)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _provider == 'mtn'
                              ? _kPrimary.withOpacity(0.5)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: const Column(children: [
                        Text('🟡', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 4),
                        Text('MTN MoMo',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _provider = 'vodafone'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _provider == 'vodafone'
                            ? _kPrimary.withOpacity(0.08)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _provider == 'vodafone'
                              ? _kPrimary.withOpacity(0.5)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: const Column(children: [
                        Text('🔴', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 4),
                        Text('Vodafone Cash',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 14),

              // MoMo number field
              TextField(
                controller: _momoCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'MoMo Number',
                  prefixIcon: const Icon(Icons.phone_android_rounded,
                      color: _kPrimary, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: _kPrimary, width: 1.5)),
                ),
              ),

              const SizedBox(height: 20),

              // Summary strip
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Paying now',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                          Text(
                            'GHS ${_amountToPay.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900),
                          ),
                        ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Remaining after',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                    Text(
                      'GHS ${(widget.balance - _amountToPay).clamp(0, widget.balance).toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                ]),
              ),

              const SizedBox(height: 16),

              // Pay button
              GestureDetector(
                onTap: _busy ? null : _pay,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _busy
                        ? LinearGradient(
                            colors: [Colors.grey[350]!, Colors.grey[300]!])
                        : const LinearGradient(
                            colors: [_kPrimary, Color(0xFF0D9488)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _busy
                        ? []
                        : [
                            BoxShadow(
                                color: _kPrimary.withOpacity(0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5))
                          ],
                  ),
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text(
                            'Pay GHS ${_amountToPay.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: _kPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: _kPrimary),
      ),
      const SizedBox(width: 10),
      Text(title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
    ]);
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black45,
                    fontWeight: FontWeight.w500))),
        const SizedBox(width: 8),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _kDark))),
      ]),
    );
  }
}

class _PayStatusBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _PayStatusBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.black45,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}
