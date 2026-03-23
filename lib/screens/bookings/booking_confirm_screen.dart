// lib/screens/bookings/booking_confirm_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Constants ───────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF0F766E);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kOrange = Color(0xFFEA580C);

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

  Widget _buildContent() {
    final b = _booking!;
    final bookingRef = (b['id'] as String).toUpperCase().substring(0, 8);
    final status = b['status'] ?? 'pending';
    final paymentStatus = b['payment_status'] ?? 'pending';
    final isPaid = paymentStatus == 'paid';
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 8),

        // ── Status Hero Card ──────────────────────────────────────
        FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isConfirmed && isPaid
                      ? [_kGreen, const Color(0xFF15803D)]
                      : status == 'cancelled'
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
                    isConfirmed && isPaid
                        ? Icons.check_circle_rounded
                        : status == 'cancelled'
                            ? Icons.cancel_rounded
                            : Icons.pending_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isConfirmed && isPaid
                      ? 'Booking Confirmed & Paid!'
                      : status == 'cancelled'
                          ? 'Booking Cancelled'
                          : 'Booking Pending Payment',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  isConfirmed && isPaid
                      ? 'Your room is secured. See you soon!'
                      : status == 'cancelled'
                          ? 'This booking has been cancelled'
                          : 'Complete your MoMo payment to confirm',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.85)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Booking ref — tap to copy
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

        // ── Payment status card ─────────────────────────────────────
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
              value: isPaid ? '✓ PAID' : 'PENDING',
              color: isPaid ? _kGreen : _kOrange,
            )),
          ]),
          const SizedBox(height: 16),
          _DetailRow(label: 'Payment Method', value: momoType),
          _DetailRow(label: 'MoMo Number', value: momoNumber),
          _DetailRow(
              label: 'Amount Paid', value: 'GHS ${amount.toStringAsFixed(2)}'),
          if (payRef != '—') _DetailRow(label: 'Paystack Ref', value: payRef),
        ])),

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

// ─── Reusable widgets ─────────────────────────────────────────────────────────

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
