// lib/screens/bookings/booking_confirm_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../../services/balance_reminder_service.dart';
import '../../services/move_in_service.dart';

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

  // ── Reminder state ──────────────────────────────────────────────────────
  ReminderSettings _reminderSettings = const ReminderSettings();

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
      // ── 1. Auto-revoke check before rendering ─────────────────────────
      await _checkRevoke();

      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      if (!doc.exists) throw Exception('Booking not found');
      if (!mounted) return;

      final data = {'id': doc.id, ...doc.data()!};

      // ── 2. Load saved reminder settings ───────────────────────────────
      final settings =
          await BalanceReminderService.instance.loadSettings(widget.bookingId);

      if (!mounted) return;
      setState(() {
        _booking = data;
        _reminderSettings = settings;
        _loading = false;
      });
      _anim.forward();

      // ── 3. Re-arm reminders if balance still owed ─────────────────────
      _maybeRescheduleReminders(data, settings);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkRevoke() async {
    final doc = await FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
    final dueDateTs = data['balance_due_date'] as Timestamp?;
    final status = data['status'] as String? ?? '';

    if (balance <= 0 ||
        dueDateTs == null ||
        status == 'cancelled' ||
        status == 'declined') return;

    if (dueDateTs.toDate().isBefore(DateTime.now())) {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .update({
        'status': 'cancelled',
        'cancellation_reason': 'Balance not paid by due date',
        'cancelled_at': FieldValue.serverTimestamp(),
        'auto_revoked': true,
      });
      await BalanceReminderService.instance.cancelReminders(widget.bookingId);
    }
  }

  Future<void> _maybeRescheduleReminders(
      Map<String, dynamic> booking, ReminderSettings settings) async {
    final balance = (booking['balance'] as num?)?.toDouble() ?? 0.0;
    final dueDateTs = booking['balance_due_date'] as Timestamp?;
    if (balance <= 0 || dueDateTs == null) return;
    final dueDate = dueDateTs.toDate();
    if (dueDate.isBefore(DateTime.now())) return;

    // Fetch this device's OneSignal subscription ID
    final playerId = OneSignal.User.pushSubscription.id;
    if (playerId == null || playerId.isEmpty) return;

    await BalanceReminderService.instance.scheduleReminders(
      bookingId: widget.bookingId,
      balance: balance,
      dueDate: dueDate,
      settings: settings,
      oneSignalPlayerId: playerId,
      hostelName: booking['hostel_name'] ?? 'your room',
    );
  }

  Future<void> _saveDueDate(DateTime picked) async {
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .update({'balance_due_date': Timestamp.fromDate(picked)});
    await _load();
  }

  Future<void> _updateReminderSettings(ReminderSettings updated) async {
    setState(() => _reminderSettings = updated);
    await BalanceReminderService.instance
        .saveSettings(widget.bookingId, updated);

    if (_booking != null) {
      await _maybeRescheduleReminders(_booking!, updated);
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

  // ── Shimmer ───────────────────────────────────────────────────────────────
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

  // ── Error ─────────────────────────────────────────────────────────────────
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

  // ── Content ───────────────────────────────────────────────────────────────
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
    final autoRevoked = b['auto_revoked'] == true;
    final moveInDateTs = b['move_in_date'] as Timestamp?;
    final hasMovedIn = moveInDateTs != null;
    final awaitingMoveIn = isConfirmed && !hasMovedIn;
    // ── Due date ────────────────────────────────────────────────────────────
    final dueDateTs = b['balance_due_date'] as Timestamp?;
    final dueDate = dueDateTs?.toDate();
    final isOverdue =
        dueDate != null && dueDate.isBefore(DateTime.now()) && balance > 0;
    final daysUntilDue = dueDate != null && !isOverdue
        ? dueDate.difference(DateTime.now()).inDays
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 8),

        // ── Auto-revoke banner ──────────────────────────────────────────────
        if (autoRevoked) ...[
          _AutoRevokedBanner(hostelName: hostelName),
          const SizedBox(height: 16),
        ],

        // ── Status Hero Card ────────────────────────────────────────────────
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
                              ? autoRevoked
                                  ? 'Booking Auto-Cancelled'
                                  : 'Booking Cancelled'
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
                              ? autoRevoked
                                  ? 'Balance was not paid by the due date.'
                                  : 'This booking has been cancelled'
                              : isDepositPaid
                                  ? 'Deposit received. Awaiting landlord confirmation.'
                                  : 'Complete your MoMo payment to confirm',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.85)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Booking ref pill
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

        const SizedBox(height: 16),
        // ── Move-in prompt ────────────────────────────────────────────────────
        if (awaitingMoveIn) ...[
          _MoveInPromptCard(
            bookingId: widget.bookingId,
            onConfirmed: _load,
          ),
          const SizedBox(height: 16),
        ],
        // ── Due date + countdown card ────────────────────────────────────────
        if (hasMovedIn &&
            balance > 0 &&
            status != 'cancelled' &&
            status != 'declined') ...[
          _DueDateCard(
            dueDate: dueDate,
            balance: balance,
            daysUntilDue: daysUntilDue,
            isOverdue: isOverdue,
            onPickDate: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: dueDate ?? now.add(const Duration(days: 7)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
                helpText: 'Set Balance Payment Deadline',
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(
                        primary: _kPrimary, onPrimary: Colors.white),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) await _saveDueDate(picked);
            },
          ),
          const SizedBox(height: 16),
        ],

        // ── Payment details card ─────────────────────────────────────────────
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

        // ── Balance payment card ─────────────────────────────────────────────
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

        // ── Reminder settings panel ──────────────────────────────────────────
        if (hasMovedIn &&
            balance > 0 &&
            status != 'cancelled' &&
            status != 'declined') ...[
          const SizedBox(height: 16),
          _ReminderSettingsCard(
            bookingId: widget.bookingId,
            balance: balance,
            dueDate: dueDate,
            settings: _reminderSettings,
            onChanged: _updateReminderSettings,
          ),
        ],

        const SizedBox(height: 16),

        // ── Booking details card ─────────────────────────────────────────────
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

        // ── Guest details card ───────────────────────────────────────────────
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

        // ── Action buttons ───────────────────────────────────────────────────
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
// DUE DATE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _DueDateCard extends StatelessWidget {
  final DateTime? dueDate;
  final double balance;
  final int? daysUntilDue;
  final bool isOverdue;
  final VoidCallback onPickDate;

  const _DueDateCard({
    required this.dueDate,
    required this.balance,
    required this.daysUntilDue,
    required this.isOverdue,
    required this.onPickDate,
  });

  Color get _accentColor => isOverdue
      ? _kRed
      : daysUntilDue != null && daysUntilDue! <= 3
          ? _kOrange
          : _kPrimary;

  String get _dueDateLabel {
    if (dueDate == null) return 'No deadline set';
    if (isOverdue) return 'Overdue — booking at risk';
    if (daysUntilDue == 0) return 'Due TODAY';
    if (daysUntilDue == 1) return 'Due TOMORROW';
    return 'Due in $daysUntilDue days';
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isOverdue
                  ? Icons.timer_off_rounded
                  : daysUntilDue != null && daysUntilDue! <= 3
                      ? Icons.warning_amber_rounded
                      : Icons.event_rounded,
              color: _accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Balance Payment Deadline',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                      fontWeight: FontWeight.w600)),
              Text(
                dueDate != null ? _fmt(dueDate!) : 'Tap to set a deadline',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: dueDate != null ? _kDark : Colors.black38),
              ),
            ]),
          ),
          // Edit date button
          GestureDetector(
            onTap: onPickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: _accentColor.withOpacity(0.3)),
              ),
              child: Text(
                dueDate != null ? 'Change' : 'Set Date',
                style: TextStyle(
                    color: _accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ]),
        if (dueDate != null) ...[
          const SizedBox(height: 12),
          // Countdown bar
          _CountdownBar(
            daysUntilDue: daysUntilDue,
            isOverdue: isOverdue,
            accentColor: _accentColor,
            dueDateLabel: _dueDateLabel,
          ),
        ],
        if (isOverdue) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kRed.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: _kRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your booking may have been cancelled due to overdue balance.',
                  style: TextStyle(
                      fontSize: 12,
                      color: _kRed.withOpacity(0.85),
                      fontWeight: FontWeight.w500),
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
// COUNTDOWN BAR
// ─────────────────────────────────────────────────────────────────────────────

class _CountdownBar extends StatelessWidget {
  final int? daysUntilDue;
  final bool isOverdue;
  final Color accentColor;
  final String dueDateLabel;

  const _CountdownBar({
    required this.daysUntilDue,
    required this.isOverdue,
    required this.accentColor,
    required this.dueDateLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Progress: how much of a 30-day window is left
    final totalWindow = 30;
    final remaining = daysUntilDue?.clamp(0, totalWindow) ?? 0;
    final progress = isOverdue ? 0.0 : remaining / totalWindow;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
          dueDateLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentColor,
          ),
        ),
        if (!isOverdue && daysUntilDue != null)
          Text(
            '$daysUntilDue day${daysUntilDue == 1 ? '' : 's'} left',
            style: const TextStyle(fontSize: 11, color: Colors.black38),
          ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: accentColor.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTO-REVOKED BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _AutoRevokedBanner extends StatelessWidget {
  final String hostelName;
  const _AutoRevokedBanner({required this.hostelName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kRed.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kRed.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: _kRed.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.timer_off_rounded, color: _kRed, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Booking Automatically Cancelled',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: _kRed)),
            const SizedBox(height: 4),
            Text(
              'Your booking for $hostelName was cancelled because the balance payment deadline passed without full payment.',
              style: TextStyle(
                  fontSize: 12, color: _kRed.withOpacity(0.8), height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'You can search for another available room.',
              style: TextStyle(
                  fontSize: 11,
                  color: _kRed.withOpacity(0.6),
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      ]),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// MOVE-IN PROMPT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _MoveInPromptCard extends StatefulWidget {
  final String bookingId;
  final VoidCallback onConfirmed;

  const _MoveInPromptCard({
    required this.bookingId,
    required this.onConfirmed,
  });

  @override
  State<_MoveInPromptCard> createState() => _MoveInPromptCardState();
}

class _MoveInPromptCardState extends State<_MoveInPromptCard> {
  bool _busy = false;

  Future<void> _confirmMoveIn() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Move-In',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Confirm that today is the day you entered your room and received your key. '
          'Your rent due date will be calculated from this date and cannot be changed later.',
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Not yet', style: TextStyle(color: Colors.black45)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Yes, I moved in today',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await MoveInService.instance.confirmMoveIn(widget.bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Move-in confirmed! Your payment schedule is now active.'),
        backgroundColor: _kGreen,
      ));
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: _kRed,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kOrange.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _kOrange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.key_rounded, color: _kOrange, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Have you moved in?',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: _kDark)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Tap "Confirm Move-In" on the day you collect your key and enter the room. '
          'This starts your payment schedule and rent due dates.',
          style: TextStyle(
              fontSize: 12, color: _kOrange.withOpacity(0.85), height: 1.5),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _confirmMoveIn,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded, size: 18),
            label: Text(_busy ? 'Confirming…' : 'Confirm Move-In Today',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// REMINDER SETTINGS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderSettingsCard extends StatefulWidget {
  final String bookingId;
  final double balance;
  final DateTime? dueDate;
  final ReminderSettings settings;
  final ValueChanged<ReminderSettings> onChanged;

  const _ReminderSettingsCard({
    required this.bookingId,
    required this.balance,
    required this.dueDate,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<_ReminderSettingsCard> createState() => _ReminderSettingsCardState();
}

class _ReminderSettingsCardState extends State<_ReminderSettingsCard> {
  bool _expanded = false;
  bool _requestingPermission = false;

  Future<void> _toggleReminders(bool on) async {
    if (on) {
      setState(() => _requestingPermission = true);
      // OneSignal handles the OS permission prompt
      await OneSignal.Notifications.requestPermission(true);
      setState(() => _requestingPermission = false);
      final hasPermission = OneSignal.Notifications.permission;
      if (!hasPermission && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Allow notifications to receive payment reminders.'),
          backgroundColor: _kOrange,
        ));
        return;
      }
    }
    widget.onChanged(widget.settings.copyWith(enabled: on));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final hasDueDate = widget.dueDate != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: s.enabled
                ? _kPrimary.withOpacity(0.25)
                : Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color:
                  s.enabled ? _kPrimary.withOpacity(0.04) : Colors.transparent,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(20),
                bottom: _expanded ? Radius.zero : const Radius.circular(20),
              ),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: s.enabled
                      ? _kPrimary.withOpacity(0.12)
                      : Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  s.enabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: s.enabled ? _kPrimary : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Payment Reminders',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _kDark)),
                      Text(
                        s.enabled
                            ? '${s.frequency.label} at ${_fmtTime(s.reminderHour, s.reminderMinute)}'
                            : 'Reminders are off',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black45),
                      ),
                    ]),
              ),
              if (_requestingPermission)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kPrimary))
              else
                Switch.adaptive(
                  value: s.enabled,
                  onChanged: _toggleReminders,
                  activeColor: _kPrimary,
                ),
            ]),
          ),
        ),

        // ── Expanded settings ────────────────────────────────────────────────
        if (_expanded) ...[
          const Divider(height: 1, color: Color(0xFFEEF2F6)),
          Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!hasDueDate) ...[
                _InfoChip(
                  icon: Icons.info_outline_rounded,
                  text:
                      'Set a balance deadline above to enable scheduled reminders.',
                  color: _kOrange,
                ),
                const SizedBox(height: 14),
              ],

              // Frequency selector
              const Text('Remind me',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kDark)),
              const SizedBox(height: 10),
              ...ReminderFrequency.values.map((freq) => _FrequencyTile(
                    freq: freq,
                    selected: s.frequency == freq,
                    onTap: () => widget.onChanged(s.copyWith(frequency: freq)),
                  )),

              const SizedBox(height: 16),

              // Time picker
              const Text('At what time?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kDark)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                        hour: s.reminderHour, minute: s.reminderMinute),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(
                            primary: _kPrimary, onPrimary: Colors.white),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    widget.onChanged(s.copyWith(
                        reminderHour: picked.hour,
                        reminderMinute: picked.minute));
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.access_time_rounded,
                        color: _kPrimary, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _fmtTime(s.reminderHour, s.reminderMinute),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _kDark),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.black26, size: 18),
                  ]),
                ),
              ),

              if (s.enabled && hasDueDate) ...[
                const SizedBox(height: 16),
                _InfoChip(
                  icon: Icons.check_circle_outline_rounded,
                  text:
                      'You\'ll be reminded ${s.frequency.label.toLowerCase()} at ${_fmtTime(s.reminderHour, s.reminderMinute)} until the deadline.',
                  color: _kGreen,
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  String _fmtTime(int h, int m) {
    final period = h < 12 ? 'AM' : 'PM';
    final hour = h == 0
        ? 12
        : h > 12
            ? h - 12
            : h;
    return '${hour.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FREQUENCY TILE
// ─────────────────────────────────────────────────────────────────────────────

class _FrequencyTile extends StatelessWidget {
  final ReminderFrequency freq;
  final bool selected;
  final VoidCallback onTap;

  const _FrequencyTile({
    required this.freq,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              selected ? _kPrimary.withOpacity(0.07) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                selected ? _kPrimary.withOpacity(0.4) : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? _kPrimary : Colors.grey[400],
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            freq.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _kPrimary : _kDark,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoChip(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  color: color.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                  height: 1.4)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BALANCE PAYMENT CARD  (unchanged from original)
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
  int _payMode = 0;
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

      if (isTest) {
        await Future.delayed(const Duration(seconds: 2));
      } else {
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

      final bookingRef2 = FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId);

      await FirebaseFirestore.instance.runTransaction((txn) async {
        txn.update(bookingRef2, {
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

      await bookingRef2.collection('payments').add({
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

      // Cancel reminders if fully paid
      if (isFinalPayment) {
        await BalanceReminderService.instance.cancelReminders(widget.bookingId);
      }

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
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

// ── Extension to convert BorderSide to a Border usable in BoxDecoration ────
extension _BorderSideX on BorderSide {
  Paint toPaint() => Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;

  Border asBorder() => Border.all(color: color, width: width);
}
