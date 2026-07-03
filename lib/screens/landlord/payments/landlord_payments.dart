// lib/screens/landlord/payments/landlord_payments.dart
// ─────────────────────────────────────────────────────────────────────────────
// RoomzyFind — Landlord Payments / Earnings Screen (v3 — modern rebuild)
//
// Mirrors lib/screens/admin/panes/payments_pane.dart, but scoped to ONE
// landlord. Money-moving actions available here:
//   • "Request payout"   — landlord-initiated. Hits api/refundPayment.js
//                           with { action: "payout" } in the body. The
//                           backend recomputes the available balance
//                           server-side and moves money via Paystack
//                           Transfer; every balance shown in this file is
//                           display-only and can never itself authorize a
//                           transfer.
//   • "Check settlement" — read-only. Asks Paystack "has this settled
//                           yet?", which a landlord has every right to know.
//   • No "Verify with Paystack" / "Refund" — those remain admin-only.
//
// Data model is identical to the admin pane's PaymentRecord because it reads
// the exact same Firestore schema: bookings/{id}/payments/{id}. The ONLY
// difference is every query is scoped with
//   .where('landlord_id', isEqualTo: widget.landlordId)
// which must be backed up by a Firestore rule (see notes at the bottom) —
// the client-side filter alone is convenience, not security.
//
// v3 visual rebuild adds: a gradient hero card with a live earnings
// sparkline, a real payout request flow, quick date-range presets, sort
// controls, avatar-style transaction rows, and a redesigned detail sheet
// with a settlement timeline. No changes to the underlying Firestore
// queries' security scoping.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  static const pageBg = Color(0xFFF5F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF9FAFB);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF1F2937);
  static const textLight = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const green = Color(0xFF2D6A4F);
  static const greenDark = Color(0xFF1B4332);
  static const greenLight = Color(0xFFD8F3DC);
  static const greenFaint = Color(0xFFF0FAF3);
  static const amber = Color(0xFFB45309);
  static const amberBg = Color(0xFFFEF3C7);
  static const red = Color(0xFFB91C1C);
  static const redBg = Color(0xFFFEE2E2);
  static const violet = Color(0xFF6D28D9);
  static const violetBg = Color(0xFFF3EEFF);
  static const teal = Color(0xFF0F766E);
  static const tealBg = Color(0xFFCCFBF1);
  static const blue = Color(0xFF2563EB);
  static const blueBg = Color(0xFFDBEAFE);
  static const pink = Color(0xFFDB2777);
  static const pinkBg = Color(0xFFFCE7F3);

  static List<BoxShadow> softShadow = [
    BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 16,
        offset: const Offset(0, 6)),
  ];
}

const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';
final _db = FirebaseFirestore.instance;
final _fmt = NumberFormat.currency(symbol: 'GH₵ ', decimalDigits: 2);
final _fmtCompact = NumberFormat.compactCurrency(symbol: 'GH₵ ');
final _dateFmt = DateFormat('MMM d, yyyy · HH:mm');
final _dayFmt = DateFormat('MMM d');

DateTime? _parseFlexibleDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _initials(String? name) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return '?';
  final parts = n.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

const _kAvatarPalette = [
  _C.green,
  _C.violet,
  _C.teal,
  _C.blue,
  _C.pink,
  _C.amber,
];

Color _avatarColor(String seed) {
  if (seed.isEmpty) return _C.textMuted;
  final sum = seed.codeUnits.fold<int>(0, (a, b) => a + b);
  return _kAvatarPalette[sum % _kAvatarPalette.length];
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED — available-balance stream
// Used by BOTH the hero header ("Available now") and the payout action card,
// so the two numbers on screen are always identical. This mirrors the exact
// formula the backend enforces server-side in api/refundPayment.js's
// handlePayout(): eligible manual_required payments minus already-requested
// payouts. It is display-only — the backend recomputes it independently
// before ever moving money.
// ─────────────────────────────────────────────────────────────────────────────

Stream<double> _availableBalanceStream(String landlordId) {
  return _db
      .collectionGroup('payments')
      .where('landlord_id', isEqualTo: landlordId)
      .where('status', isEqualTo: 'paid')
      .where('settlement_status', isEqualTo: 'manual_required')
      .snapshots()
      .asyncMap((paymentsSnap) async {
    final eligible = paymentsSnap.docs.fold<double>(
        0,
        (sum, d) =>
            sum + ((d.data()['landlord_received'] as num?)?.toDouble() ?? 0));

    final payoutsSnap = await _db
        .collection('payouts')
        .where('landlord_id', isEqualTo: landlordId)
        .where('status', whereIn: ['processing', 'completed']).get();
    final paid = payoutsSnap.docs.fold<double>(
        0, (sum, d) => sum + ((d.data()['amount'] as num?)?.toDouble() ?? 0));

    return (eligible - paid).clamp(0, double.infinity);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum PayStatus { paid, pendingVerification, refunded, failed, unknown }

PayStatus _parseStatus(String? raw) {
  switch (raw) {
    case 'paid':
      return PayStatus.paid;
    case 'pending_verification':
      return PayStatus.pendingVerification;
    case 'refunded':
      return PayStatus.refunded;
    case 'failed':
      return PayStatus.failed;
    default:
      return PayStatus.unknown;
  }
}

extension PayStatusX on PayStatus {
  String get label => switch (this) {
        PayStatus.paid => 'Paid',
        PayStatus.pendingVerification => 'Pending Verification',
        PayStatus.refunded => 'Refunded',
        PayStatus.failed => 'Failed',
        PayStatus.unknown => 'Unknown',
      };
  Color get color => switch (this) {
        PayStatus.paid => _C.green,
        PayStatus.pendingVerification => _C.amber,
        PayStatus.refunded => _C.violet,
        PayStatus.failed => _C.red,
        PayStatus.unknown => _C.textMuted,
      };
  IconData get icon => switch (this) {
        PayStatus.paid => Icons.check_circle_rounded,
        PayStatus.pendingVerification => Icons.hourglass_top_rounded,
        PayStatus.refunded => Icons.replay_rounded,
        PayStatus.failed => Icons.cancel_rounded,
        PayStatus.unknown => Icons.help_outline_rounded,
      };
}

enum MethodFilter { all, momo, manual }

enum SortOption { newest, amountHigh, amountLow }

extension SortOptionX on SortOption {
  String get label => switch (this) {
        SortOption.newest => 'Newest first',
        SortOption.amountHigh => 'Highest amount',
        SortOption.amountLow => 'Lowest amount',
      };
}

enum QuickRange { all, today, week, month, custom }

extension QuickRangeX on QuickRange {
  String get label => switch (this) {
        QuickRange.all => 'All time',
        QuickRange.today => 'Today',
        QuickRange.week => '7 days',
        QuickRange.month => '30 days',
        QuickRange.custom => 'Custom',
      };
}

DateTimeRange? _rangeForQuick(QuickRange q, DateTimeRange? custom) {
  final now = DateTime.now();
  switch (q) {
    case QuickRange.today:
      return DateTimeRange(
          start: DateTime(now.year, now.month, now.day), end: now);
    case QuickRange.week:
      return DateTimeRange(
          start: now.subtract(const Duration(days: 7)), end: now);
    case QuickRange.month:
      return DateTimeRange(
          start: now.subtract(const Duration(days: 30)), end: now);
    case QuickRange.custom:
      return custom;
    case QuickRange.all:
      return null;
  }
}

enum SettlementState {
  settled,
  pending,
  overdue,
  manualRequired,
  notApplicable,
  unknown,
}

SettlementState _parseSettlement(String? raw) {
  switch (raw) {
    case 'settled':
      return SettlementState.settled;
    case 'pending':
      return SettlementState.pending;
    case 'overdue':
      return SettlementState.overdue;
    case 'manual_required':
      return SettlementState.manualRequired;
    case 'not_applicable':
      return SettlementState.notApplicable;
    default:
      return SettlementState.unknown;
  }
}

extension SettlementStateX on SettlementState {
  String get label => switch (this) {
        SettlementState.settled => 'Settled to you',
        SettlementState.pending => 'Pending settlement (T+1)',
        SettlementState.overdue => 'Settlement overdue',
        SettlementState.manualRequired => 'Manual payout required',
        SettlementState.notApplicable => 'Not applicable',
        SettlementState.unknown => 'Not yet checked',
      };
  Color get color => switch (this) {
        SettlementState.settled => _C.green,
        SettlementState.pending => _C.amber,
        SettlementState.overdue => _C.red,
        SettlementState.manualRequired => _C.violet,
        SettlementState.notApplicable => _C.textMuted,
        SettlementState.unknown => _C.textMuted,
      };
  IconData get icon => switch (this) {
        SettlementState.settled => Icons.bolt_rounded,
        SettlementState.pending => Icons.hourglass_top_rounded,
        SettlementState.overdue => Icons.warning_amber_rounded,
        SettlementState.manualRequired => Icons.pending_actions_rounded,
        SettlementState.notApplicable => Icons.remove_circle_outline_rounded,
        SettlementState.unknown => Icons.help_outline_rounded,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL — mirrors bookings/{id}/payments/{id} exactly (same as admin)
// ─────────────────────────────────────────────────────────────────────────────

class PaymentRecord {
  final String id;
  final String bookingId;
  final String? tenantName;
  final String? tenantEmail;
  final String? hostelName;
  final String? roomNumber;
  final String? landlordId;

  final double amount;
  final String method;
  final String? provider;
  final String reference;
  final PayStatus status;

  final double commissionTaken;
  final double landlordReceived;

  final int paymentNumber;
  final bool isFirstPayment;
  final bool isFinalPayment;
  final String note;
  final String? source;

  final SettlementState settlementState;
  final DateTime? settledAt;
  final DateTime? settlementCheckedAt;

  final double? refundedAmount;
  final DateTime? refundedAt;
  final String? refundReason;

  final DateTime paidAt;

  const PaymentRecord({
    required this.id,
    required this.bookingId,
    this.tenantName,
    this.tenantEmail,
    this.hostelName,
    this.roomNumber,
    this.landlordId,
    required this.amount,
    required this.method,
    this.provider,
    required this.reference,
    required this.status,
    required this.commissionTaken,
    required this.landlordReceived,
    required this.paymentNumber,
    required this.isFirstPayment,
    required this.isFinalPayment,
    required this.note,
    this.source,
    this.settlementState = SettlementState.unknown,
    this.settledAt,
    this.settlementCheckedAt,
    this.refundedAmount,
    this.refundedAt,
    this.refundReason,
    required this.paidAt,
  });

  bool get isSettlementCheckable =>
      status == PayStatus.paid && method != 'manual';

  bool get hasDisplayInfo => tenantName != null && hostelName != null;

  factory PaymentRecord.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final bookingId = doc.reference.parent.parent?.id ?? '';
    final raw = d['status'] as String? ?? 'paid';
    return PaymentRecord(
      id: doc.id,
      bookingId: bookingId,
      tenantName: d['name'] as String?,
      tenantEmail: d['email'] as String?,
      hostelName: d['hostel_name'] as String?,
      roomNumber: d['room_number'] as String?,
      landlordId: d['landlord_id'] as String?,
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      method: d['method'] as String? ?? 'momo',
      provider: d['provider'] as String?,
      reference: d['reference'] as String? ?? doc.id,
      status: _parseStatus(raw),
      commissionTaken: (d['commission_taken'] as num?)?.toDouble() ?? 0,
      landlordReceived: (d['landlord_received'] as num?)?.toDouble() ?? 0,
      paymentNumber: (d['payment_number'] as num?)?.toInt() ?? 1,
      isFirstPayment: d['is_first_payment'] == true,
      isFinalPayment: d['is_final_payment'] == true,
      note: d['note'] as String? ?? '',
      source: d['source'] as String?,
      settlementState: _parseSettlement(d['settlement_status'] as String?),
      settledAt: _parseFlexibleDate(d['settled_at']),
      settlementCheckedAt: _parseFlexibleDate(d['settlement_checked_at']),
      refundedAmount: (d['refunded_amount'] as num?)?.toDouble(),
      refundedAt: _parseFlexibleDate(d['refunded_at']),
      refundReason: d['refund_reason'] as String?,
      paidAt: _parseFlexibleDate(d['paid_at']) ?? DateTime.now(),
    );
  }

  PaymentRecord enrichedWith(Map<String, dynamic> booking) => PaymentRecord(
        id: id,
        bookingId: bookingId,
        tenantName: tenantName ?? booking['name'] as String?,
        tenantEmail: tenantEmail ?? booking['email'] as String?,
        hostelName: hostelName ?? booking['hostel_name'] as String?,
        roomNumber: roomNumber ?? booking['room_number'] as String?,
        landlordId: landlordId ?? booking['landlord_id'] as String?,
        amount: amount,
        method: method,
        provider: provider,
        reference: reference,
        status: status,
        commissionTaken: commissionTaken,
        landlordReceived: landlordReceived,
        paymentNumber: paymentNumber,
        isFirstPayment: isFirstPayment,
        isFinalPayment: isFinalPayment,
        note: note,
        source: source,
        settlementState: settlementState,
        settledAt: settledAt,
        settlementCheckedAt: settlementCheckedAt,
        refundedAmount: refundedAmount,
        refundedAt: refundedAt,
        refundReason: refundReason,
        paidAt: paidAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class LandlordPaymentsScreen extends StatefulWidget {
  const LandlordPaymentsScreen({super.key, required this.landlordId});

  /// The logged-in landlord's own uid. Every query below is hard-scoped to
  /// this value — there is no path in this file that lets a different
  /// landlord's data be requested, but that must ALSO be enforced in
  /// Firestore rules (see notes at the end of this file).
  final String landlordId;

  @override
  State<LandlordPaymentsScreen> createState() => _LandlordPaymentsScreenState();
}

class _LandlordPaymentsScreenState extends State<LandlordPaymentsScreen> {
  PayStatus? _statusFilter;
  MethodFilter _methodFilter = MethodFilter.all;
  SortOption _sortOption = SortOption.newest;
  QuickRange _quickRange = QuickRange.all;
  DateTimeRange? _customRange;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  final Map<String, Map<String, dynamic>> _bookingCache = {};
  final Set<String> _bookingFetchesInFlight = {};

  bool _checkingAny = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchBooking(String bookingId) async {
    if (_bookingCache.containsKey(bookingId)) return _bookingCache[bookingId];
    if (_bookingFetchesInFlight.contains(bookingId)) return null;
    _bookingFetchesInFlight.add(bookingId);
    try {
      final snap = await _db.collection('bookings').doc(bookingId).get();
      if (snap.exists) {
        _bookingCache[bookingId] = snap.data()!;
        if (mounted) setState(() {});
        return snap.data();
      }
    } catch (_) {
      // row just shows placeholders
    } finally {
      _bookingFetchesInFlight.remove(bookingId);
    }
    return null;
  }

  PaymentRecord _resolve(PaymentRecord r) {
    if (r.hasDisplayInfo) return r;
    final cached = _bookingCache[r.bookingId];
    if (cached != null) return r.enrichedWith(cached);
    _fetchBooking(r.bookingId);
    return r;
  }

  Query<Map<String, dynamic>> get _query {
    // Hard filter — this is the one line that makes this "my payments"
    // instead of "all payments". Must be backed by a matching Firestore
    // rule (collectionGroup read on `payments` allowed only where
    // resource.data.landlord_id == request.auth.uid).
    Query<Map<String, dynamic>> q = _db
        .collectionGroup('payments')
        .where('landlord_id', isEqualTo: widget.landlordId)
        .orderBy('paid_at', descending: true);

    if (_statusFilter != null) {
      final raw = switch (_statusFilter!) {
        PayStatus.paid => 'paid',
        PayStatus.pendingVerification => 'pending_verification',
        PayStatus.refunded => 'refunded',
        PayStatus.failed => 'failed',
        PayStatus.unknown => 'paid',
      };
      q = q.where('status', isEqualTo: raw);
    }
    if (_methodFilter == MethodFilter.momo) {
      q = q.where('method', isEqualTo: 'momo');
    } else if (_methodFilter == MethodFilter.manual) {
      q = q.where('method', isEqualTo: 'manual');
    }

    final range = _rangeForQuick(_quickRange, _customRange);
    if (range != null) {
      q = q
          .where('paid_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('paid_at',
              isLessThanOrEqualTo: Timestamp.fromDate(
                  range.end.add(const Duration(minutes: 1))));
    }
    return q.limit(300);
  }

  List<PaymentRecord> _applySearch(List<PaymentRecord> records) {
    if (_searchQuery.trim().isEmpty) return records;
    final q = _searchQuery.toLowerCase();
    return records.where((r) {
      return (r.tenantName ?? '').toLowerCase().contains(q) ||
          r.reference.toLowerCase().contains(q) ||
          (r.hostelName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  List<PaymentRecord> _applySort(List<PaymentRecord> records) {
    final list = [...records];
    switch (_sortOption) {
      case SortOption.newest:
        list.sort((a, b) => b.paidAt.compareTo(a.paidAt));
        break;
      case SortOption.amountHigh:
        list.sort((a, b) => b.landlordReceived.compareTo(a.landlordReceived));
        break;
      case SortOption.amountLow:
        list.sort((a, b) => a.landlordReceived.compareTo(b.landlordReceived));
        break;
    }
    return list;
  }

  List<double> _computeTrend(List<PaymentRecord> records, {int days = 14}) {
    final now = DateTime.now();
    final buckets = List<double>.filled(days, 0);
    for (final r in records) {
      if (r.status != PayStatus.paid) continue;
      final paidDay = DateTime(r.paidAt.year, r.paidAt.month, r.paidAt.day);
      final diff =
          DateTime(now.year, now.month, now.day).difference(paidDay).inDays;
      if (diff >= 0 && diff < days) {
        buckets[days - 1 - diff] += r.landlordReceived;
      }
    }
    return buckets;
  }

  /// Read-only settlement check. Hits the SAME endpoint the admin pane uses,
  /// but the backend must verify the caller's auth token's uid equals the
  /// landlordId on the payment before answering — see notes at bottom.
  Future<void> _checkSettlement(PaymentRecord r) async {
    _showLoadingSnack('Checking with Paystack…');
    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/settlements'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'check',
          'bookingId': r.bookingId,
          'paymentId': r.id,
          'landlordId': widget.landlordId,
        }),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final state = _parseSettlement(data['settlement_status'] as String?);
        ScaffoldMessenger.of(context).showSnackBar(_snack(
          data['message'] as String? ?? state.label,
          isError: state == SettlementState.overdue,
        ));
      } else {
        throw Exception(data['error'] ?? 'Settlement check failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
          _snack('Could not check settlement: $e', isError: true));
    }
  }

  Future<void> _checkAllPending(List<PaymentRecord> records) async {
    final toCheck = records
        .where((r) =>
            r.isSettlementCheckable &&
            (r.settlementState == SettlementState.pending ||
                r.settlementState == SettlementState.unknown))
        .toList();
    if (toCheck.isEmpty) return;
    setState(() => _checkingAny = true);
    _showLoadingSnack('Checking ${toCheck.length} payment(s) with Paystack…');
    for (final r in toCheck) {
      await _checkSettlement(r);
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (mounted) setState(() => _checkingAny = false);
  }

  void _showLoadingSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _C.textDark,
      duration: const Duration(seconds: 6),
      content: Row(children: [
        const SizedBox(
            width: 16,
            height: 16,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  SnackBar _snack(String msg, {required bool isError}) => SnackBar(
        backgroundColor: isError ? _C.red : _C.green,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      );

  void _copyRef(String ref) {
    Clipboard.setData(ClipboardData(text: ref));
    ScaffoldMessenger.of(context)
        .showSnackBar(_snack('Reference copied', isError: false));
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (range != null) {
      setState(() {
        _customRange = range;
        _quickRange = QuickRange.custom;
      });
    }
  }

  void _exportCsv(List<PaymentRecord> records) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Tenant,Hostel,Room,Method,Reference,Amount,YouReceived,PlatformFee,Status,Settlement,PaidAt');
    for (final r in records) {
      buffer.writeln([
        r.tenantName ?? '',
        r.hostelName ?? '',
        r.roomNumber ?? '',
        r.method,
        r.reference,
        r.amount.toStringAsFixed(2),
        r.landlordReceived.toStringAsFixed(2),
        r.commissionTaken.toStringAsFixed(2),
        r.status.label,
        r.settlementState.label,
        _dateFmt.format(r.paidAt),
      ].map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','));
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(_snack(
        '${records.length} rows copied as CSV — paste into Excel/Sheets',
        isError: false));
  }

  void _openDetail(PaymentRecord r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentDetailSheet(
        record: r,
        onCheckSettlement:
            r.isSettlementCheckable ? () => _checkSettlement(r) : null,
        onCopyRef: () => _copyRef(r.reference),
      ),
    );
  }

  void _goToPayoutSetup() {
    // TODO: navigate to Settings → Payout Setup, which kicks off
    // create-subaccount.js on the backend.
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 700;
    final isCompact = width < 1000;

    return Container(
      color: _C.pageBg,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('landlords').doc(widget.landlordId).snapshots(),
        builder: (context, landlordSnap) {
          final hasSubaccount = landlordSnap.data
                  ?.data()?['paystack_subaccount']
                  ?.toString()
                  .isNotEmpty ==
              true;

          return StreamBuilder<double>(
            stream: _availableBalanceStream(widget.landlordId),
            builder: (context, availSnap) {
              final available = availSnap.data ?? 0;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _query.snapshots(),
                builder: (ctx, snap) {
                  final loading =
                      snap.connectionState == ConnectionState.waiting;
                  final all = snap.hasData
                      ? snap.data!.docs
                          .map(PaymentRecord.fromDoc)
                          .map(_resolve)
                          .toList()
                      : <PaymentRecord>[];
                  final filtered = _applySort(_applySearch(all));
                  final stats = _computeStats(all);
                  final trend = _computeTrend(all);

                  return RefreshIndicator(
                    color: _C.green,
                    onRefresh: () async => setState(() {}),
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.all(isNarrow ? 16 : 28),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              _HeroHeader(
                                gross: stats.gross,
                                available: available,
                                trendPoints: trend,
                                hasSubaccount: hasSubaccount,
                                onSetupTap: _goToPayoutSetup,
                              ),
                              const SizedBox(height: 18),
                              _StatGrid(stats: stats, isNarrow: isNarrow),
                              const SizedBox(height: 18),
                              if (hasSubaccount)
                                _PayoutActionCard(
                                  landlordId: widget.landlordId,
                                  available: available,
                                )
                              else
                                _SetupNoticeCard(onSetupTap: _goToPayoutSetup),
                              const SizedBox(height: 18),
                              _PayoutHistoryModern(
                                  landlordId: widget.landlordId),
                              const SizedBox(height: 18),
                              _FilterPanel(
                                statusFilter: _statusFilter,
                                methodFilter: _methodFilter,
                                sortOption: _sortOption,
                                quickRange: _quickRange,
                                customRange: _customRange,
                                searchCtrl: _searchCtrl,
                                onStatusChanged: (v) =>
                                    setState(() => _statusFilter = v),
                                onMethodChanged: (v) =>
                                    setState(() => _methodFilter = v),
                                onSortChanged: (v) =>
                                    setState(() => _sortOption = v),
                                onQuickRangeChanged: (v) {
                                  if (v == QuickRange.custom) {
                                    _pickCustomRange();
                                  } else {
                                    setState(() => _quickRange = v);
                                  }
                                },
                                onSearchChanged: (v) =>
                                    setState(() => _searchQuery = v),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _PillButton(
                                    icon: Icons.sync_rounded,
                                    label: _checkingAny
                                        ? 'Checking…'
                                        : 'Check pending settlements',
                                    color: _C.teal,
                                    loading: _checkingAny,
                                    onTap: _checkingAny
                                        ? null
                                        : () => _checkAllPending(all),
                                  ),
                                  _PillButton(
                                    icon: Icons.download_rounded,
                                    label: 'Export ${filtered.length}',
                                    color: _C.textLight,
                                    outlined: true,
                                    onTap: filtered.isEmpty
                                        ? null
                                        : () => _exportCsv(filtered),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (loading)
                                Column(
                                  children: List.generate(
                                      5, (i) => const _ShimmerBox(height: 64)),
                                )
                              else if (isCompact)
                                _CardList(
                                    records: filtered, onOpen: _openDetail)
                              else
                                _DataTable(
                                    records: filtered, onOpen: _openDetail),
                              const SizedBox(height: 40),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  _StatsData _computeStats(List<PaymentRecord> records) {
    double gross = 0, settled = 0, pending = 0, thisMonth = 0;
    int settledCount = 0, pendingCount = 0;
    final now = DateTime.now();
    for (final r in records) {
      if (r.status != PayStatus.paid) continue;
      gross += r.landlordReceived;
      if (r.paidAt.year == now.year && r.paidAt.month == now.month) {
        thisMonth += r.landlordReceived;
      }
      if (r.settlementState == SettlementState.settled) {
        settled += r.landlordReceived;
        settledCount++;
      } else if (r.settlementState != SettlementState.notApplicable) {
        pending += r.landlordReceived;
        pendingCount++;
      }
    }
    return _StatsData(
      gross: gross,
      settled: settled,
      settledCount: settledCount,
      pending: pending,
      pendingCount: pendingCount,
      thisMonth: thisMonth,
    );
  }
}

class _StatsData {
  final double gross, settled, pending, thisMonth;
  final int settledCount, pendingCount;
  const _StatsData({
    required this.gross,
    required this.settled,
    required this.settledCount,
    required this.pending,
    required this.pendingCount,
    required this.thisMonth,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO HEADER — gradient card, live sparkline, subaccount pill
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.gross,
    required this.available,
    required this.trendPoints,
    required this.hasSubaccount,
    required this.onSetupTap,
  });

  final double gross;
  final double available;
  final List<double> trendPoints;
  final bool hasSubaccount;
  final VoidCallback onSetupTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_C.greenDark, _C.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _C.green.withOpacity(0.28),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total earnings',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmt.format(gross),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SubaccountPill(
                  hasSubaccount: hasSubaccount, onSetupTap: onSetupTap),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(
                points: trendPoints,
                lineColor: Colors.white,
                fillColor: Colors.white.withOpacity(0.16),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('last 14 days',
              style: TextStyle(color: Colors.white38, fontSize: 10.5)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                const Text('Available now',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                const Spacer(),
                Text(
                  _fmt.format(available),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubaccountPill extends StatelessWidget {
  const _SubaccountPill(
      {required this.hasSubaccount, required this.onSetupTap});
  final bool hasSubaccount;
  final VoidCallback onSetupTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSubaccount ? Icons.bolt_rounded : Icons.warning_amber_rounded,
            color: hasSubaccount
                ? const Color(0xFFA7F3D0)
                : const Color(0xFFFDE68A),
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            hasSubaccount ? 'Auto-settling' : 'Set up payout',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    if (hasSubaccount) return pill;
    return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onSetupTap,
        child: pill);
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(
      {required this.points, required this.lineColor, required this.fillColor});
  final List<double> points;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    final maxV = points.reduce((a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1.0 : maxV;
    final stepX =
        points.length > 1 ? size.width / (points.length - 1) : size.width;

    final linePath = Path();
    final fillPath = Path();
    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height - (points[i] / safeMax) * size.height * 0.92;
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
        fillPath,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.points != points;
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT GRID
// ─────────────────────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.isNarrow});
  final _StatsData stats;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        icon: Icons.calendar_month_rounded,
        label: 'This month',
        value: _fmt.format(stats.thisMonth),
        sub: 'earned so far',
        color: _C.blue,
        bg: _C.blueBg,
      ),
      _StatCard(
        icon: Icons.bolt_rounded,
        label: 'Settled',
        value: _fmt.format(stats.settled),
        sub: '${stats.settledCount} payment(s)',
        color: _C.green,
        bg: _C.greenLight,
      ),
      _StatCard(
        icon: Icons.hourglass_top_rounded,
        label: 'Pending settlement',
        value: _fmt.format(stats.pending),
        sub: '${stats.pendingCount} not yet with you',
        color: _C.amber,
        bg: _C.amberBg,
      ),
      _StatCard(
        icon: Icons.account_balance_wallet_rounded,
        label: 'Gross earned',
        value: _fmt.format(stats.gross),
        sub: 'your share, all time',
        color: _C.violet,
        bg: _C.violetBg,
      ),
    ];

    return LayoutBuilder(builder: (ctx, constraints) {
      final columns = isNarrow ? 2 : 4;
      final gap = 12.0;
      final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children:
            cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.bg,
  });
  final IconData icon;
  final String label, value, sub;
  final Color color, bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _C.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(color: _C.textMuted, fontSize: 11)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    color: color, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: _C.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETUP NOTICE (no payout account yet)
// ─────────────────────────────────────────────────────────────────────────────

class _SetupNoticeCard extends StatelessWidget {
  const _SetupNoticeCard({required this.onSetupTap});
  final VoidCallback onSetupTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.amberBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.warning_amber_rounded,
              color: _C.amber, size: 18),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'No payout account set up yet — you\'ll be paid manually until this is added.',
            style: TextStyle(fontSize: 12.5, color: _C.textDark),
          ),
        ),
        const SizedBox(width: 8),
        _PillButton(
          icon: Icons.arrow_forward_rounded,
          label: 'Set up',
          color: _C.amber,
          onTap: onSetupTap,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYOUT ACTION CARD — landlord-initiated payout request
// Hits api/refundPayment.js with action: "payout" (same file the admin
// refund flow uses, dispatched via the "action" field in the body). The
// balance shown here comes from the shared _availableBalanceStream — the
// backend recomputes it independently before ever moving money.
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutActionCard extends StatefulWidget {
  const _PayoutActionCard({required this.landlordId, required this.available});
  final String landlordId;
  final double available;

  @override
  State<_PayoutActionCard> createState() => _PayoutActionCardState();
}

class _PayoutActionCardState extends State<_PayoutActionCard> {
  bool _submitting = false;

  Future<void> _requestPayout() async {
    final available = widget.available;
    final amountCtrl =
        TextEditingController(text: available.toStringAsFixed(2));
    final confirmed = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Request payout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available: ${_fmt.format(available)}',
                style: const TextStyle(color: _C.textLight, fontSize: 12.5)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (GH₵)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _C.green),
            onPressed: () {
              final v = double.tryParse(amountCtrl.text);
              if (v != null && v > 0 && v <= available) Navigator.pop(ctx, v);
            },
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed == null) return;

    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      // Same endpoint as admin refunds — refundPayment.js dispatches on
      // req.body.action, so "payout" routes to handlePayout() there.
      final res = await http.post(
        Uri.parse('$_kBackendUrl/refundPayment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'action': 'payout',
          'landlordId': widget.landlordId,
          'amount': confirmed,
        }),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payout requested — ${data['status'] ?? 'processing'}'),
          backgroundColor: _C.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      } else {
        throw Exception(data['error'] ?? 'Payout request failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: _C.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.available > 0 && !_submitting;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: _C.softShadow,
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _C.greenFaint, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.savings_rounded, color: _C.green, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ready to withdraw',
                  style: TextStyle(color: _C.textMuted, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text(_fmt.format(widget.available),
                  style: const TextStyle(
                      color: _C.textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: canSend ? _requestPayout : null,
          style: FilledButton.styleFrom(
            backgroundColor: _C.green,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 16),
          label: Text(_submitting ? 'Sending…' : 'Request payout'),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYOUT HISTORY
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutHistoryModern extends StatelessWidget {
  const _PayoutHistoryModern({required this.landlordId});
  final String landlordId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('payouts')
          .where('landlord_id', isEqualTo: landlordId)
          .orderBy('initiated_at', descending: true)
          .limit(5)
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: _C.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const [
                Icon(Icons.history_rounded, size: 15, color: _C.textMuted),
                SizedBox(width: 6),
                Text('Recent payouts',
                    style: TextStyle(
                        color: _C.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const Text('No payouts sent to you yet.',
                    style: TextStyle(color: _C.textMuted, fontSize: 12.5))
              else
                ...docs.map((d) {
                  final p = d.data();
                  final status = p['status']?.toString() ?? 'processing';
                  final amount = (p['amount'] as num?)?.toDouble() ?? 0;
                  final ts = p['initiated_at'] as Timestamp?;
                  final color = status == 'completed'
                      ? _C.green
                      : status == 'failed' || status == 'reversed'
                          ? _C.red
                          : _C.amber;
                  final icon = status == 'completed'
                      ? Icons.check_circle_rounded
                      : status == 'failed' || status == 'reversed'
                          ? Icons.cancel_rounded
                          : Icons.hourglass_top_rounded;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            shape: BoxShape.circle),
                        child: Icon(icon, size: 13, color: color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_fmt.format(amount),
                              style: const TextStyle(
                                  color: _C.textDark,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600))),
                      Text(status,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Text(ts != null ? _dayFmt.format(ts.toDate()) : '—',
                          style: const TextStyle(
                              color: _C.textMuted, fontSize: 11)),
                    ]),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER PANEL
// ─────────────────────────────────────────────────────────────────────────────

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.statusFilter,
    required this.methodFilter,
    required this.sortOption,
    required this.quickRange,
    required this.customRange,
    required this.searchCtrl,
    required this.onStatusChanged,
    required this.onMethodChanged,
    required this.onSortChanged,
    required this.onQuickRangeChanged,
    required this.onSearchChanged,
  });

  final PayStatus? statusFilter;
  final MethodFilter methodFilter;
  final SortOption sortOption;
  final QuickRange quickRange;
  final DateTimeRange? customRange;
  final TextEditingController searchCtrl;
  final ValueChanged<PayStatus?> onStatusChanged;
  final ValueChanged<MethodFilter> onMethodChanged;
  final ValueChanged<SortOption> onSortChanged;
  final ValueChanged<QuickRange> onQuickRangeChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _C.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            style: const TextStyle(color: _C.textDark, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by tenant, reference, or hostel…',
              hintStyle: const TextStyle(color: _C.textMuted, fontSize: 13.5),
              prefixIcon:
                  const Icon(Icons.search, color: _C.textMuted, size: 18),
              filled: true,
              fillColor: _C.surfaceAlt,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: QuickRange.values.map((q) {
                final selected = quickRange == q;
                final label = q == QuickRange.custom && customRange != null
                    ? '${_dayFmt.format(customRange!.start)} – ${_dayFmt.format(customRange!.end)}'
                    : q.label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: label,
                    selected: selected,
                    color: _C.teal,
                    icon: q == QuickRange.custom
                        ? Icons.date_range_rounded
                        : null,
                    onTap: () => onQuickRangeChanged(q),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                  label: 'All statuses',
                  selected: statusFilter == null,
                  color: _C.textLight,
                  onTap: () => onStatusChanged(null)),
              ...PayStatus.values.where((s) => s != PayStatus.unknown).map(
                    (s) => _Chip(
                      label: s.label,
                      selected: statusFilter == s,
                      color: s.color,
                      icon: s.icon,
                      onTap: () => onStatusChanged(s),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Dropdown<MethodFilter>(
                value: methodFilter,
                items: const {
                  MethodFilter.all: 'All methods',
                  MethodFilter.momo: 'Mobile Money',
                  MethodFilter.manual: 'Manual',
                },
                onChanged: onMethodChanged,
                icon: Icons.payment_rounded,
              ),
              _Dropdown<SortOption>(
                value: sortOption,
                items: {for (final s in SortOption.values) s: s.label},
                onChanged: onSortChanged,
                icon: Icons.sort_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _C.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: _C.textLight, size: 18),
          style: const TextStyle(color: _C.textDark, fontSize: 13),
          items: items.entries
              .map((e) => DropdownMenuItem<T>(
                    value: e.key,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 14, color: _C.textLight),
                      const SizedBox(width: 6),
                      Text(e.value),
                    ]),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : _C.surfaceAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? color : _C.textLight),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? color : _C.textLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
    this.loading = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool outlined;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: outlined
              ? Colors.transparent
              : color.withOpacity(disabled ? 0.06 : 0.1),
          borderRadius: BorderRadius.circular(20),
          border: outlined ? Border.all(color: _C.border) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(icon, size: 15, color: disabled ? _C.textMuted : color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: disabled ? _C.textMuted : color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DESKTOP TABLE
// ─────────────────────────────────────────────────────────────────────────────

class _DataTable extends StatelessWidget {
  const _DataTable({required this.records, required this.onOpen});
  final List<PaymentRecord> records;
  final ValueChanged<PaymentRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _C.softShadow,
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _C.border))),
          child: Row(children: [
            _th('Tenant', flex: 3),
            _th('Hostel / Room', flex: 3),
            _th('Method', flex: 2),
            _th('You received', flex: 2, align: TextAlign.right),
            _th('Settlement', flex: 3, align: TextAlign.center),
            _th('Status', flex: 2, align: TextAlign.center),
            _th('Date', flex: 3),
          ]),
        ),
        if (records.isEmpty)
          const _EmptyState()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: _C.border),
            itemBuilder: (ctx, i) {
              final r = records[i];
              return InkWell(
                onTap: () => onOpen(r),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Row(children: [
                          _Avatar(name: r.tenantName, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.tenantName ?? '…',
                                    style: const TextStyle(
                                        color: _C.textDark,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                                Text(r.reference,
                                    style: const TextStyle(
                                        color: _C.textMuted,
                                        fontSize: 11,
                                        fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ])),
                    Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.hostelName ?? '…',
                                style: const TextStyle(
                                    color: _C.textDark, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                            Text('Room ${r.roomNumber ?? '—'}',
                                style: const TextStyle(
                                    color: _C.textMuted, fontSize: 11)),
                          ],
                        )),
                    Expanded(flex: 2, child: _MethodBadge(record: r)),
                    Expanded(
                        flex: 2,
                        child: Text(_fmt.format(r.landlordReceived),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: _C.textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w700))),
                    Expanded(
                        flex: 3,
                        child: Center(child: _SettlementBadge(record: r))),
                    Expanded(
                        flex: 2, child: Center(child: _StatusBadge(record: r))),
                    Expanded(
                        flex: 3,
                        child: Text(_dateFmt.format(r.paidAt),
                            style: const TextStyle(
                                color: _C.textLight, fontSize: 11))),
                  ]),
                ),
              );
            },
          ),
      ]),
    );
  }

  Widget _th(String text, {int flex = 1, TextAlign align = TextAlign.left}) =>
      Expanded(
        flex: flex,
        child: Text(text,
            textAlign: align,
            style: const TextStyle(
                color: _C.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE CARD LIST
// ─────────────────────────────────────────────────────────────────────────────

class _CardList extends StatelessWidget {
  const _CardList({required this.records, required this.onOpen});
  final List<PaymentRecord> records;
  final ValueChanged<PaymentRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const _EmptyState();
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: records.length,
      itemBuilder: (ctx, i) {
        final r = records[i];
        return GestureDetector(
          onTap: () => onOpen(r),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _C.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _Avatar(name: r.tenantName, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.tenantName ?? '…',
                            style: const TextStyle(
                                color: _C.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        Text(r.hostelName ?? '…',
                            style: const TextStyle(
                                color: _C.textLight, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(_fmt.format(r.landlordReceived),
                      style: const TextStyle(
                          color: _C.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ]),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(record: r),
                    _MethodBadge(record: r),
                    _SettlementBadge(record: r),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_dateFmt.format(r.paidAt),
                    style: const TextStyle(color: _C.textMuted, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 32});
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor(name ?? '');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: [color, color.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED BADGES
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.record});
  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    final c = record.status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(record.status.icon, size: 11, color: c),
        const SizedBox(width: 4),
        Text(record.status.label,
            style:
                TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.record});
  final PaymentRecord record;

  IconData get _icon => switch (record.method) {
        'momo' => Icons.phone_android_rounded,
        'manual' => Icons.handshake_outlined,
        _ => Icons.payment_rounded,
      };

  String get _label {
    if (record.method == 'manual') return 'Manual';
    final p = record.provider;
    if (p == 'mtn') return 'MTN MoMo';
    if (p == 'vodafone' || p == 'vod') return 'Vodafone Cash';
    return 'Mobile Money';
  }

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, size: 13, color: _C.textLight),
        const SizedBox(width: 4),
        Text(_label, style: const TextStyle(color: _C.textLight, fontSize: 12)),
      ]);
}

/// View-only settlement indicator. Tapping opens the check flow only if
/// the caller passes an onCheck callback — in the transaction list rows we
/// deliberately keep this passive (no onCheck) to avoid a wall of
/// tap-to-refresh chips; the action lives in the detail sheet and the
/// "Check pending settlements" bulk button instead.
class _SettlementBadge extends StatelessWidget {
  const _SettlementBadge({required this.record, this.onCheck});
  final PaymentRecord record;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    if (!record.isSettlementCheckable) return const SizedBox.shrink();
    final state = record.settlementState;
    return InkWell(
      onTap: onCheck,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: state.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(state.icon, size: 11, color: state.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(state.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: state.color)),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHIMMER LOADING SKELETON
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({this.height = 56, this.borderRadius = 16});
  final double height;
  final double borderRadius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        return Container(
          height: widget.height,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _ctrl.value, 0),
              end: Alignment(1 + 2 * _ctrl.value, 0),
              colors: const [_C.surfaceAlt, _C.border, _C.surfaceAlt],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAIL SHEET — with settlement timeline, plus optional "check settlement"
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentDetailSheet extends StatelessWidget {
  const _PaymentDetailSheet({
    required this.record,
    required this.onCheckSettlement,
    required this.onCopyRef,
  });
  final PaymentRecord record;
  final VoidCallback? onCheckSettlement;
  final VoidCallback onCopyRef;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.94,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: _C.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              _Avatar(name: r.tenantName, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.tenantName ?? 'Payment',
                        style: const TextStyle(
                            color: _C.textDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Text('${r.hostelName ?? '—'} · Room ${r.roomNumber ?? '—'}',
                        style:
                            const TextStyle(color: _C.textLight, fontSize: 12)),
                  ],
                ),
              ),
              _StatusBadge(record: r),
            ]),
          ),
          const Divider(height: 1, color: _C.border),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.all(20),
              children: [
                _amountHero(),
                const SizedBox(height: 18),
                _row('Reference', r.reference, copyable: true),
                _row(
                    'Method',
                    r.method == 'manual'
                        ? 'Manual'
                        : (r.provider == 'mtn' ? 'MTN MoMo' : 'Vodafone Cash')),
                _row('Payment #',
                    '${r.paymentNumber}${r.isFirstPayment ? ' · first' : ''}${r.isFinalPayment ? ' · final' : ''}'),
                _row('Paid at', _dateFmt.format(r.paidAt)),
                const SizedBox(height: 10),
                const Divider(color: _C.border),
                const SizedBox(height: 10),
                const Text('Commission breakdown',
                    style: TextStyle(
                        color: _C.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _breakdownCell('Platform fee', r.commissionTaken,
                          _C.teal, _C.tealBg)),
                  Expanded(
                      child: _breakdownCell('You receive', r.landlordReceived,
                          _C.green, _C.greenLight)),
                ]),
                const SizedBox(height: 18),
                const Text('Settlement journey',
                    style: TextStyle(
                        color: _C.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _SettlementTimeline(record: r),
                if (onCheckSettlement != null) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: onCheckSettlement,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: _C.tealBg,
                          borderRadius: BorderRadius.circular(20)),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.refresh_rounded, size: 14, color: _C.teal),
                        SizedBox(width: 5),
                        Text('Check settlement now',
                            style: TextStyle(
                                color: _C.teal,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ],
                if (r.settlementCheckedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                      'Last checked ${_dateFmt.format(r.settlementCheckedAt!)}',
                      style:
                          const TextStyle(color: _C.textMuted, fontSize: 11)),
                ],
                if (r.status == PayStatus.refunded) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _C.redBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _C.red.withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Refunded ${_fmt.format(r.refundedAmount ?? r.amount)}',
                            style: const TextStyle(
                                color: _C.red, fontWeight: FontWeight.w700)),
                        if (r.refundedAt != null)
                          Text(_dateFmt.format(r.refundedAt!),
                              style: const TextStyle(
                                  color: _C.textLight, fontSize: 11)),
                        if (r.refundReason != null &&
                            r.refundReason!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Reason: ${r.refundReason}',
                                style: const TextStyle(
                                    color: _C.textLight, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _amountHero() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [_C.green, _C.greenDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You received',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(_fmt.format(record.landlordReceived),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text('of ${_fmt.format(record.amount)} paid by tenant',
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ],
        ),
      );

  Widget _row(String label, String value, {bool copyable = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: _C.textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _C.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
          if (copyable)
            InkWell(
                onTap: onCopyRef,
                child: const Icon(Icons.copy_rounded,
                    size: 14, color: _C.textMuted)),
        ]),
      );

  Widget _breakdownCell(String label, double value, Color color, Color bg) =>
      Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 11)),
            const SizedBox(height: 4),
            Text(_fmt.format(value),
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

/// Small vertical stepper: Paid → Settlement → (Received / Refunded).
/// Purely a visual read of the record's existing fields — introduces no
/// new state and makes no network calls itself.
class _SettlementTimeline extends StatelessWidget {
  const _SettlementTimeline({required this.record});
  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final isRefunded = r.status == PayStatus.refunded;
    final isSettled = r.settlementState == SettlementState.settled;
    final steps = <_TimelineStep>[
      _TimelineStep(
        label: 'Paid by tenant',
        detail: _dateFmt.format(r.paidAt),
        done: true,
        color: _C.green,
        icon: Icons.check_circle_rounded,
      ),
      _TimelineStep(
        label: isRefunded ? 'Refunded' : r.settlementState.label,
        detail: isRefunded
            ? (r.refundedAt != null ? _dateFmt.format(r.refundedAt!) : '—')
            : (r.settledAt != null
                ? _dateFmt.format(r.settledAt!)
                : (r.settlementCheckedAt != null
                    ? 'checked, not yet settled'
                    : 'not yet checked')),
        done: isRefunded || isSettled,
        color: isRefunded ? _C.red : r.settlementState.color,
        icon: isRefunded ? Icons.replay_rounded : r.settlementState.icon,
      ),
      _TimelineStep(
        label: isRefunded ? 'Tenant refunded' : 'In your account',
        detail: isRefunded
            ? 'money returned'
            : (isSettled ? 'complete' : 'pending'),
        done: isRefunded || isSettled,
        color: isRefunded ? _C.violet : (isSettled ? _C.green : _C.textMuted),
        icon: isRefunded
            ? Icons.undo_rounded
            : Icons.account_balance_wallet_rounded,
      ),
    ];

    return Column(
      children: List.generate(steps.length, (i) {
        final s = steps[i];
        final isLast = i == steps.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: s.done ? s.color.withOpacity(0.15) : _C.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(s.icon,
                        size: 13, color: s.done ? s.color : _C.textMuted),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: s.done ? s.color.withOpacity(0.25) : _C.border,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label,
                          style: TextStyle(
                              color: s.done ? _C.textDark : _C.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      Text(s.detail,
                          style: const TextStyle(
                              color: _C.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.label,
    required this.detail,
    required this.done,
    required this.color,
    required this.icon,
  });
  final String label;
  final String detail;
  final bool done;
  final Color color;
  final IconData icon;
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration:
                  BoxDecoration(color: _C.surfaceAlt, shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_rounded,
                  color: _C.textMuted, size: 34),
            ),
            const SizedBox(height: 14),
            const Text('No payments yet',
                style: TextStyle(
                    color: _C.textLight,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Bookings paid by tenants will show up here',
                style: TextStyle(color: _C.textMuted, fontSize: 12.5)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKEND / RULES NOTES
// ─────────────────────────────────────────────────────────────────────────────
//
// 1. Firestore rules — the collectionGroup query is scoped server-side too,
//    not just client-side (`.where('landlord_id', ...)` is convenience, not
//    security). This is already covered by the existing rules:
//
//    match /{path=**}/payments/{paymentId} {
//      allow list, get: if isAdmin() ||
//        (isLandlord() && resource.data.landlord_id == request.auth.uid);
//    }
//
//    match /payouts/{payoutId} {
//      allow list, get: if isAdmin() ||
//        (isLandlord() && resource.data.landlord_id == request.auth.uid);
//      allow write: if false; // backend Admin SDK only
//    }
//
// 2. "Request payout" — hits api/refundPayment.js with
//    { action: "payout", landlordId, amount } and a Firebase ID token in
//    the Authorization header. The backend independently recomputes the
//    available balance and moves money via Paystack Transfer; nothing in
//    this file can authorize a transfer on its own.
//
// 3. api/settlements.js — the existing `action: 'check'` branch is reused
//    as-is (read-only, no money moves). It should verify the caller's
//    Firebase ID token's uid matches the landlord_id on the payment doc
//    being checked, so one landlord can never probe another landlord's
//    settlement status by guessing bookingId/paymentId pairs.
//
// 4. Routing — wire into landlord_portal.dart:
//      case _Page.payments:
//        return LandlordPaymentsScreen(landlordId: lid);
