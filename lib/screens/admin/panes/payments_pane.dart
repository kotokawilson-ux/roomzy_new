// lib/screens/admin/panes/payments_pane.dart
// ─────────────────────────────────────────────────────────────────────────────
// RoomzyFind — Admin Payments Pane v2
// Rebuilt to match the REAL payment schema written by:
//   • hostel_detail_screen.dart  → _onPaymentSuccess / _confirmManualPayment
//   • processSuccessfulPayment.js (Paystack webhook)
//
// New in this version:
//   • Correct data model (payments live in bookings/{id}/payments/{id})
//   • "Verify with Paystack" — calls /api/verify-payment for the live gateway
//     status instead of trusting whatever Firestore says
//   • Settlement tracking — distinguishes landlords who are auto-settled via
//     Paystack subaccount split vs. landlords who need a manual payout
//   • "Initiate Payout" — triggers a real Paystack Transfer to a landlord
//     (via /api/initiatePayout) and records it in a `payouts` collection
//   • "Refund" — triggers a real Paystack refund (via /api/refundPayment),
//     which also unwinds the booking's amount_paid/balance/slot server-side
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────────────────────────────────────

const _bg = Color(0xFF0F1117);
const _surface = Color(0xFF1A1D27);
const _surfaceAlt = Color(0xFF20232F);
const _border = Color(0xFF2A2D3A);
const _accent = Color(0xFF6C63FF);
const _accentLow = Color(0x266C63FF);
const _success = Color(0xFF22C55E);
const _successLow = Color(0x2622C55E);
const _warning = Color(0xFFF59E0B);
const _warningLow = Color(0x26F59E0B);
const _danger = Color(0xFFEF4444);
const _dangerLow = Color(0x26EF4444);
const _teal = Color(0xFF14B8A6);
const _tealLow = Color(0x2614B8A6);
const _textPrimary = Color(0xFFECEDF2);
const _textSecondary = Color(0xFF8B8FA8);
const _textMuted = Color(0xFF555870);

const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';

final _db = FirebaseFirestore.instance;
final _fmt = NumberFormat.currency(symbol: 'GH₵ ', decimalDigits: 2);
final _dateFmt = DateFormat('MMM d, yyyy · HH:mm');

/// Some settlement fields were briefly written as ISO strings by a backend
/// bug instead of Firestore Timestamps. This tolerates both formats so a
/// single malformed doc can't crash the whole payments stream.
DateTime? _parseFlexibleDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}
// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

/// Mirrors the `status` field actually written on a payment doc:
/// 'paid' | 'pending_verification' | 'refunded' | 'failed'
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
        PayStatus.paid => _success,
        PayStatus.pendingVerification => _warning,
        PayStatus.refunded => _accent,
        PayStatus.failed => _danger,
        PayStatus.unknown => _textMuted,
      };
  IconData get icon => switch (this) {
        PayStatus.paid => Icons.check_circle_rounded,
        PayStatus.pendingVerification => Icons.hourglass_top_rounded,
        PayStatus.refunded => Icons.replay_rounded,
        PayStatus.failed => Icons.cancel_rounded,
        PayStatus.unknown => Icons.help_outline_rounded,
      };
}

enum MethodFilter { all, momo, manual, webhook }

/// Whether the money Paystack collected has actually landed with the
/// landlord yet. Written by /api/checkSettlement and /api/syncSettlements,
/// which read Paystack's real Settlements API — this is NOT inferred from
/// whether the landlord merely *has* a subaccount configured.
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
        SettlementState.settled => 'Settled to landlord',
        SettlementState.pending => 'Pending settlement (T+1)',
        SettlementState.overdue => 'Settlement overdue',
        SettlementState.manualRequired => 'Manual payout required',
        SettlementState.notApplicable => 'Not applicable',
        SettlementState.unknown => 'Not yet checked',
      };
  Color get color => switch (this) {
        SettlementState.settled => _success,
        SettlementState.pending => _warning,
        SettlementState.overdue => _danger,
        SettlementState.manualRequired => _accent,
        SettlementState.notApplicable => _textMuted,
        SettlementState.unknown => _textMuted,
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
// DATA MODEL — mirrors bookings/{id}/payments/{id} exactly
// ─────────────────────────────────────────────────────────────────────────────

class PaymentRecord {
  final String id; // payment doc id
  final String bookingId; // parent booking doc id

  // ── Denormalized display fields (present on payments written after the
  // schema patch below; enriched lazily for older docs — see _enrich) ──
  final String? tenantName;
  final String? tenantEmail;
  final String? hostelName;
  final String? roomNumber;
  final String? landlordId;

  // ── Core payment fields ─────────────────────────────────────────────────
  final double amount;
  final String method; // 'momo' | 'manual'
  final String? provider; // 'mtn' | 'vodafone' | 'manual'
  final String gateway; // ← add this: 'paystack' | 'moolre' | 'manual'

  final String reference;
  final PayStatus status;
  final String rawStatus;

  // ── Commission breakdown ────────────────────────────────────────────────
  final double commissionTaken;
  final double landlordReceived;
  final double? commissionRateUsed;

  // ── Position in the booking's payment sequence ─────────────────────────
  final int paymentNumber;
  final bool isFirstPayment;
  final bool isFinalPayment;
  final String note;
  final String? source; // 'webhook' when confirmed server-side

  // ── Gateway verification (written back by the "Verify" action) ─────────
  final DateTime? verifiedAt;
  final String? gatewayStatus;

  // ── Settlement tracking — has the money actually reached the landlord? ──
  // Written by /api/checkSettlement (on-demand) and /api/syncSettlements
  // (bulk), both of which read Paystack's real Settlements API.
  final SettlementState settlementState;
  final DateTime? settledAt;
  final String? settlementId;
  final DateTime? settlementCheckedAt;

  // ── Refund state ─────────────────────────────────────────────────────────
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
    required this.gateway, // ← add this
    required this.reference,
    required this.status,
    required this.rawStatus,
    required this.commissionTaken,
    required this.landlordReceived,
    this.commissionRateUsed,
    required this.paymentNumber,
    required this.isFirstPayment,
    required this.isFinalPayment,
    required this.note,
    this.source,
    this.verifiedAt,
    this.gatewayStatus,
    this.settlementState = SettlementState.unknown,
    this.settledAt,
    this.settlementId,
    this.settlementCheckedAt,
    this.refundedAmount,
    this.refundedAt,
    this.refundReason,
    required this.paidAt,
  });

  bool get isRefundable =>
      status == PayStatus.paid &&
      method != 'manual' &&
      gateway == 'paystack' &&
      refundedAmount == null;

  /// Whether it's meaningful to offer a "Check Settlement" action at all —
  /// manual payments and refunded/failed payments never settle via Paystack.
  bool get isSettlementCheckable =>
      status == PayStatus.paid && method != 'manual' && gateway == 'paystack';

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
      gateway: d['gateway'] as String? ?? 'paystack', // ← add this
      reference: d['reference'] as String? ?? doc.id,
      status: _parseStatus(raw),
      rawStatus: raw,
      commissionTaken: (d['commission_taken'] as num?)?.toDouble() ?? 0,
      landlordReceived: (d['landlord_received'] as num?)?.toDouble() ?? 0,
      commissionRateUsed: (d['commission_rate_used'] as num?)?.toDouble(),
      paymentNumber: (d['payment_number'] as num?)?.toInt() ?? 1,
      isFirstPayment: d['is_first_payment'] == true,
      isFinalPayment: d['is_final_payment'] == true,
      note: d['note'] as String? ?? '',
      source: d['source'] as String?,
      verifiedAt: _parseFlexibleDate(d['verified_at']),
      gatewayStatus: d['gateway_status'] as String?,
      settlementState: _parseSettlement(d['settlement_status'] as String?),
      settledAt: _parseFlexibleDate(d['settled_at']),
      settlementId: d['settlement_id']?.toString(),
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
        gateway: gateway, // ← add this
        reference: reference,
        status: status,
        rawStatus: rawStatus,
        commissionTaken: commissionTaken,
        landlordReceived: landlordReceived,
        commissionRateUsed: commissionRateUsed,
        paymentNumber: paymentNumber,
        isFirstPayment: isFirstPayment,
        isFinalPayment: isFinalPayment,
        note: note,
        source: source,
        verifiedAt: verifiedAt,
        gatewayStatus: gatewayStatus,
        settlementState: settlementState,
        settledAt: settledAt,
        settlementId: settlementId,
        settlementCheckedAt: settlementCheckedAt,
        refundedAmount: refundedAmount,
        refundedAt: refundedAt,
        refundReason: refundReason,
        paidAt: paidAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PANE
// ─────────────────────────────────────────────────────────────────────────────

class PaymentsPane extends StatefulWidget {
  const PaymentsPane({super.key});
  @override
  State<PaymentsPane> createState() => _PaymentsPaneState();
}

class _PaymentsPaneState extends State<PaymentsPane>
    with TickerProviderStateMixin {
  late final TabController _tabs;

  // filters
  PayStatus? _statusFilter;
  MethodFilter _methodFilter = MethodFilter.all;
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  final _searchCtrl = TextEditingController();

  // enrichment cache: bookingId -> booking data
  final Map<String, Map<String, dynamic>> _bookingCache = {};
  final Set<String> _bookingFetchesInFlight = {};

  bool _syncingSettlements = false;
  bool _autoSync = false;
  Timer? _autoSyncTimer;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  void _toggleAutoSync(bool value) {
    setState(() => _autoSync = value);
    _autoSyncTimer?.cancel();
    if (value) {
      _autoSyncTimer = Timer.periodic(
          const Duration(minutes: 3), (_) => _syncAllSettlements());
      _syncAllSettlements();
    }
  }

  // ── enrichment for payment docs missing denormalized display fields ──────
  // ── enrichment for payment docs missing denormalized display fields ──────
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
      // ignore — row will just show placeholders
    } finally {
      _bookingFetchesInFlight.remove(bookingId);
    }
    return null;
  }

  /// Backfills denormalized fields (landlord_id, name, hostel_name, etc.)
  /// onto the actual Firestore payment doc the first time we discover them
  /// missing. Without this, the payment doc stays permanently broken for
  /// anything that reads it directly — the Landlord Payouts aggregation
  /// query (collectionGroup('payments').where('landlord_id', ...)) and the
  /// backend's /api/settlements "check" action both do exactly that.
  Future<void> _backfillPaymentDoc(
      PaymentRecord r, Map<String, dynamic> booking) async {
    final updates = <String, dynamic>{};
    if (r.landlordId == null && booking['landlord_id'] != null) {
      updates['landlord_id'] = booking['landlord_id'];
    }
    if (r.tenantName == null && booking['name'] != null) {
      updates['name'] = booking['name'];
    }
    if (r.tenantEmail == null && booking['email'] != null) {
      updates['email'] = booking['email'];
    }
    if (r.hostelName == null && booking['hostel_name'] != null) {
      updates['hostel_name'] = booking['hostel_name'];
    }
    if (r.roomNumber == null && booking['room_number'] != null) {
      updates['room_number'] = booking['room_number'];
    }
    if (updates.isEmpty) return;

    try {
      await _db
          .collection('bookings')
          .doc(r.bookingId)
          .collection('payments')
          .doc(r.id)
          .update(updates);
    } catch (e) {
      debugPrint('⚠️ Failed to backfill payment ${r.id}: $e');
    }
  }

  PaymentRecord _resolve(PaymentRecord r) {
    if (r.hasDisplayInfo && r.landlordId != null) return r;
    final cached = _bookingCache[r.bookingId];
    if (cached != null) {
      _backfillPaymentDoc(r, cached); // fire-and-forget, self-heals Firestore
      return r.enrichedWith(cached);
    }
    // fire-and-forget fetch; row rebuilds once cached
    _fetchBooking(r.bookingId);
    return r;
  }

  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> q =
        _db.collectionGroup('payments').orderBy('paid_at', descending: true);
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
    } else if (_methodFilter == MethodFilter.webhook) {
      q = q.where('source', isEqualTo: 'webhook');
    }
    if (_dateRange != null) {
      q = q
          .where('paid_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRange!.start))
          .where('paid_at',
              isLessThanOrEqualTo: Timestamp.fromDate(
                  _dateRange!.end.add(const Duration(days: 1))));
    }
    return q.limit(300);
  }

  List<PaymentRecord> _applySearch(List<PaymentRecord> records) {
    if (_searchQuery.trim().isEmpty) return records;
    final q = _searchQuery.toLowerCase();
    return records.where((r) {
      return (r.tenantName ?? '').toLowerCase().contains(q) ||
          (r.tenantEmail ?? '').toLowerCase().contains(q) ||
          r.reference.toLowerCase().contains(q) ||
          (r.hostelName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _verifyWithPaystack(PaymentRecord r) async {
    _showLoadingSnack('Checking Paystack for ${r.reference}…');
    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/verify-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reference': r.reference}),
      );
      final data = jsonDecode(res.body);
      final gatewayStatus =
          (data['status'] ?? data['data']?['status'] ?? 'unknown').toString();

      await _db
          .collection('bookings')
          .doc(r.bookingId)
          .collection('payments')
          .doc(r.id)
          .update({
        'gateway_status': gatewayStatus,
        'verified_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final matches = gatewayStatus == 'success' && r.status == PayStatus.paid;
      ScaffoldMessenger.of(context).showSnackBar(_snack(
        matches
            ? 'Confirmed — Paystack shows this payment as successful.'
            : 'Paystack reports status: "$gatewayStatus". Firestore may be out of sync.',
        isError: !matches,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context)
          .showSnackBar(_snack('Verification failed: $e', isError: true));
    }
  }

  /// On-demand settlement check for ONE payment — hits /api/checkSettlement,
  /// which queries Paystack's real Settlements API rather than guessing from
  /// whether the landlord has a subaccount configured.
  Future<void> _checkSettlement(PaymentRecord r) async {
    _showLoadingSnack('Checking settlement status with Paystack…');
    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/settlements'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'check',
          'bookingId': r.bookingId,
          'paymentId': r.id,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(_snack('Settlement check failed: $e', isError: true));
    }
  }

  /// Bulk sync — walks every landlord's real Paystack settlement history via
  /// /api/syncSettlements and marks all newly-settled payments in one pass.
  /// Far more efficient than checking payments one at a time.
  Future<void> _syncAllSettlements() async {
    if (_syncingSettlements) return;
    setState(() => _syncingSettlements = true);
    _showLoadingSnack('Syncing settlements across all landlords…');
    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/settlements'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'sync'}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final settled = data['settledCount'] ?? 0;
        final checked = data['landlordsChecked'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(_snack(
          'Checked $checked landlords · $settled payment(s) newly marked settled.',
          isError: false,
        ));
      } else {
        throw Exception(data['error'] ?? 'Sync failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context)
          .showSnackBar(_snack('Settlement sync failed: $e', isError: true));
    } finally {
      if (mounted) setState(() => _syncingSettlements = false);
    }
  }

  Future<void> _initiateRefund(PaymentRecord r) async {
    final result = await showDialog<_RefundResult>(
      context: context,
      builder: (_) => _RefundDialog(record: r),
    );
    if (result == null) return;

    _showLoadingSnack('Processing refund…');
    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/refundPayment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': r.bookingId,
          'paymentId': r.id,
          'reference': r.reference,
          'amount': result.amount,
          'reason': result.reason,
        }),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snack(
              'Refund of ${_fmt.format(result.amount)} initiated for ${r.tenantName ?? 'guest'}.',
              isError: false),
        );
      } else {
        final data = jsonDecode(res.body);
        throw Exception(data['error'] ?? 'Refund failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context)
          .showSnackBar(_snack('Refund failed: $e', isError: true));
    }
  }

  void _showLoadingSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _surfaceAlt,
      duration: const Duration(seconds: 8),
      content: Row(children: [
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
        const SizedBox(width: 12),
        Expanded(child: Text(msg, style: const TextStyle(color: _textPrimary))),
      ]),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  SnackBar _snack(String msg, {required bool isError}) => SnackBar(
        backgroundColor: isError ? _danger : _success,
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: now,
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: Colors.white,
            surface: _surface,
            onSurface: _textPrimary,
          ),
          dialogBackgroundColor: _surfaceAlt,
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  void _openDetail(PaymentRecord r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentDetailSheet(
        record: r,
        onVerify: () => _verifyWithPaystack(r),
        onRefund: () => _initiateRefund(r),
        onCheckSettlement: () => _checkSettlement(r),
        onCopyRef: () => _copyRef(r.reference),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final W = MediaQuery.of(context).size.width;
    final isNarrow = W < 700;
    final isCompact = W < 1100;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: _bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              isNarrow: isNarrow,
              onSyncSettlements: _syncAllSettlements,
              syncing: _syncingSettlements,
              autoSync: _autoSync,
              onAutoSyncChanged: _toggleAutoSync,
            ),
            Container(
              color: _surface,
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: _accent,
                unselectedLabelColor: _textSecondary,
                indicatorColor: _accent,
                dividerColor: _border,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(
                      icon: Icon(Icons.receipt_long_rounded, size: 16),
                      text: 'Transactions'),
                  Tab(
                      icon: Icon(Icons.send_to_mobile_rounded, size: 16),
                      text: 'Landlord Payouts'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _TransactionsTab(
                    isNarrow: isNarrow,
                    isCompact: isCompact,
                    query: _query,
                    statusFilter: _statusFilter,
                    methodFilter: _methodFilter,
                    dateRange: _dateRange,
                    searchCtrl: _searchCtrl,
                    resolve: _resolve,
                    applySearch: _applySearch,
                    onStatusChanged: (v) => setState(() => _statusFilter = v),
                    onMethodChanged: (v) => setState(() => _methodFilter = v),
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    onPickDate: _pickDateRange,
                    onClearDate: () => setState(() => _dateRange = null),
                    onOpenDetail: _openDetail,
                    onVerify: _verifyWithPaystack,
                    onRefund: _initiateRefund,
                    onCheckSettlement: _checkSettlement,
                    onCopyRef: _copyRef,
                  ),
                  const _LandlordPayoutsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundResult {
  final double amount;
  final String? reason;
  const _RefundResult(this.amount, this.reason);
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isNarrow;
  final VoidCallback onSyncSettlements;
  final bool syncing;
  final bool autoSync;
  final ValueChanged<bool> onAutoSyncChanged;
  const _TopBar({
    required this.isNarrow,
    required this.onSyncSettlements,
    required this.syncing,
    required this.autoSync,
    required this.onAutoSyncChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 28, vertical: 18),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          if (!isNarrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payments',
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: isNarrow ? 16 : 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                const Text(
                    'Live · Multi-gateway · Settlement tracked for Paystack',
                    style: TextStyle(color: _textSecondary, fontSize: 12)),
              ],
            )
          else
            Text('Payments',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3)),
          const Spacer(),
          Tooltip(
            message:
                'Pull real settlement data from Paystack for every landlord',
            child: OutlinedButton.icon(
              onPressed: syncing ? null : onSyncSettlements,
              icon: syncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _teal))
                  : const Icon(Icons.sync_rounded, size: 16),
              label: Text(
                  isNarrow ? '' : (syncing ? 'Syncing…' : 'Sync Settlements')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 10 : 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Auto-sync settlements every 3 minutes',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: autoSync,
                onChanged: onAutoSyncChanged,
                activeColor: _teal,
              ),
              if (!isNarrow)
                const Text('Auto',
                    style: TextStyle(color: _textSecondary, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 4),
          _LiveDot(),
          const SizedBox(width: 8),
          if (!isNarrow)
            const Text('Live',
                style: TextStyle(
                    color: _success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: _success, shape: BoxShape.circle)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSACTIONS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionsTab extends StatefulWidget {
  final bool isNarrow, isCompact;
  final Query<Map<String, dynamic>> query;
  final PayStatus? statusFilter;
  final MethodFilter methodFilter;
  final DateTimeRange? dateRange;
  final TextEditingController searchCtrl;
  final PaymentRecord Function(PaymentRecord) resolve;
  final List<PaymentRecord> Function(List<PaymentRecord>) applySearch;
  final ValueChanged<PayStatus?> onStatusChanged;
  final ValueChanged<MethodFilter> onMethodChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickDate, onClearDate;
  final ValueChanged<PaymentRecord> onOpenDetail;
  final ValueChanged<PaymentRecord> onVerify;
  final ValueChanged<PaymentRecord> onRefund;
  final ValueChanged<PaymentRecord> onCheckSettlement;
  final ValueChanged<String> onCopyRef;

  const _TransactionsTab({
    required this.isNarrow,
    required this.isCompact,
    required this.query,
    required this.statusFilter,
    required this.methodFilter,
    required this.dateRange,
    required this.searchCtrl,
    required this.resolve,
    required this.applySearch,
    required this.onStatusChanged,
    required this.onMethodChanged,
    required this.onSearchChanged,
    required this.onPickDate,
    required this.onClearDate,
    required this.onOpenDetail,
    required this.onVerify,
    required this.onRefund,
    required this.onCheckSettlement,
    required this.onCopyRef,
  });

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  final Set<String> _selectedIds = {};
  List<PaymentRecord> _lastRecords = [];
  bool _bulkBusy = false;

  void _toggle(String id) => setState(() {
        if (_selectedIds.contains(id)) {
          _selectedIds.remove(id);
        } else {
          _selectedIds.add(id);
        }
      });

  void _clearSelection() => setState(() => _selectedIds.clear());

  List<PaymentRecord> get _selectedRecords =>
      _lastRecords.where((r) => _selectedIds.contains(r.id)).toList();

  Future<void> _bulkCheckSettlement() async {
    setState(() => _bulkBusy = true);
    for (final r in _selectedRecords) {
      if (r.isSettlementCheckable) widget.onCheckSettlement(r);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (mounted) {
      setState(() => _bulkBusy = false);
      _clearSelection();
    }
  }

  Future<void> _bulkVerify() async {
    setState(() => _bulkBusy = true);
    for (final r in _selectedRecords) {
      widget.onVerify(r);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (mounted) {
      setState(() => _bulkBusy = false);
      _clearSelection();
    }
  }

  void _exportCsv(List<PaymentRecord> records) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Tenant,Email,Hostel,Room,Method,Reference,Amount,Status,Settlement,Commission,LandlordReceived,PaidAt');
    for (final r in records) {
      buffer.writeln([
        r.tenantName ?? '',
        r.tenantEmail ?? '',
        r.hostelName ?? '',
        r.roomNumber ?? '',
        r.method,
        r.reference,
        r.amount.toStringAsFixed(2),
        r.status.label,
        r.settlementState.label,
        r.commissionTaken.toStringAsFixed(2),
        r.landlordReceived.toStringAsFixed(2),
        _dateFmt.format(r.paidAt),
      ].map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','));
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '${records.length} rows copied as CSV — paste into Excel/Sheets'),
      backgroundColor: _success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.query.snapshots(),
      builder: (ctx, snap) {
        final all = snap.hasData
            ? snap.data!.docs
                .map(PaymentRecord.fromDoc)
                .map(widget.resolve)
                .toList()
            : <PaymentRecord>[];
        final filtered = widget.applySearch(all);
        _lastRecords = filtered;
        final stats = _computeStats(all);

        return Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: widget.isNarrow ? 16 : 28, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatRow(stats: stats, isNarrow: widget.isNarrow),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                      child: _FilterBar(
                        statusFilter: widget.statusFilter,
                        methodFilter: widget.methodFilter,
                        dateRange: widget.dateRange,
                        searchCtrl: widget.searchCtrl,
                        onStatusChanged: widget.onStatusChanged,
                        onMethodChanged: widget.onMethodChanged,
                        onSearchChanged: widget.onSearchChanged,
                        onPickDate: widget.onPickDate,
                        onClearDate: widget.onClearDate,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed:
                          filtered.isEmpty ? null : () => _exportCsv(filtered),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text('Export ${filtered.length} rows as CSV'),
                      style: TextButton.styleFrom(foregroundColor: _teal),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (snap.connectionState == ConnectionState.waiting)
                    _shimmer()
                  else if (widget.isCompact)
                    _CardList(
                      records: filtered,
                      selectedIds: _selectedIds,
                      onToggleSelect: _toggle,
                      onOpen: widget.onOpenDetail,
                      onVerify: widget.onVerify,
                      onRefund: widget.onRefund,
                      onCheckSettlement: widget.onCheckSettlement,
                      onCopyRef: widget.onCopyRef,
                    )
                  else
                    _DataTable(
                      records: filtered,
                      selectedIds: _selectedIds,
                      onToggleSelect: _toggle,
                      onOpen: widget.onOpenDetail,
                      onVerify: widget.onVerify,
                      onRefund: widget.onRefund,
                      onCheckSettlement: widget.onCheckSettlement,
                      onCopyRef: widget.onCopyRef,
                    ),
                  const SizedBox(height: 90),
                ],
              ),
            ),
            if (_selectedIds.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Material(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _accent),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(children: [
                      Text('${_selectedIds.length} selected',
                          style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      const Spacer(),
                      if (_bulkBusy)
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _accent))
                      else ...[
                        TextButton.icon(
                          onPressed: _bulkCheckSettlement,
                          icon: const Icon(Icons.sync_rounded,
                              size: 16, color: _teal),
                          label: const Text('Check Settlement',
                              style: TextStyle(color: _teal)),
                        ),
                        TextButton.icon(
                          onPressed: _bulkVerify,
                          icon: const Icon(Icons.verified_rounded,
                              size: 16, color: _accent),
                          label: const Text('Verify',
                              style: TextStyle(color: _accent)),
                        ),
                        IconButton(
                          onPressed: _clearSelection,
                          icon: const Icon(Icons.close_rounded,
                              color: _textSecondary, size: 18),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _shimmer() => Column(
        children: List.generate(
            6,
            (i) => Container(
                  height: 60,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                )),
      );

  _StatsData _computeStats(List<PaymentRecord> records) {
    double total = 0, paid = 0, pending = 0, refunded = 0, commission = 0;
    double awaitingSettlement = 0;
    int pCount = 0, wCount = 0, rCount = 0, sCount = 0;
    for (final r in records) {
      total += r.amount;
      commission += r.commissionTaken;
      switch (r.status) {
        case PayStatus.paid:
          paid += r.amount;
          pCount++;
          break;
        case PayStatus.pendingVerification:
          pending += r.amount;
          wCount++;
          break;
        case PayStatus.refunded:
          refunded += r.refundedAmount ?? r.amount;
          rCount++;
          break;
        default:
          break;
      }
      if (r.status == PayStatus.paid &&
          (r.settlementState == SettlementState.pending ||
              r.settlementState == SettlementState.overdue ||
              r.settlementState == SettlementState.unknown)) {
        awaitingSettlement += r.landlordReceived;
        sCount++;
      }
    }
    return _StatsData(
      total: total,
      totalCount: records.length,
      paid: paid,
      paidCount: pCount,
      pending: pending,
      pendingCount: wCount,
      refunded: refunded,
      refundedCount: rCount,
      commission: commission,
      awaitingSettlement: awaitingSettlement,
      awaitingSettlementCount: sCount,
    );
  }
}

class _StatsData {
  final double total, paid, pending, refunded, commission, awaitingSettlement;
  final int totalCount,
      paidCount,
      pendingCount,
      refundedCount,
      awaitingSettlementCount;
  const _StatsData({
    required this.total,
    required this.totalCount,
    required this.paid,
    required this.paidCount,
    required this.pending,
    required this.pendingCount,
    required this.refunded,
    required this.refundedCount,
    required this.commission,
    required this.awaitingSettlement,
    required this.awaitingSettlementCount,
  });
}

class _StatRow extends StatelessWidget {
  final _StatsData stats;
  final bool isNarrow;
  const _StatRow({required this.stats, required this.isNarrow});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        icon: Icons.payments_rounded,
        label: 'Total Volume',
        value: _fmt.format(stats.total),
        sub: '${stats.totalCount} transactions',
        color: _accent,
      ),
      _StatCard(
        icon: Icons.check_circle_rounded,
        label: 'Confirmed Paid',
        value: _fmt.format(stats.paid),
        sub: '${stats.paidCount} payments',
        color: _success,
      ),
      _StatCard(
        icon: Icons.hourglass_top_rounded,
        label: 'Pending Verification',
        value: _fmt.format(stats.pending),
        sub: '${stats.pendingCount} awaiting',
        color: _warning,
      ),
      _StatCard(
        icon: Icons.account_balance_rounded,
        label: 'Platform Commission',
        value: _fmt.format(stats.commission),
        sub: 'earned this view',
        color: _teal,
      ),
      _StatCard(
        icon: Icons.hourglass_bottom_rounded,
        label: 'Awaiting Settlement',
        value: _fmt.format(stats.awaitingSettlement),
        sub: '${stats.awaitingSettlementCount} not yet with landlord',
        color: _warning,
      ),
      _StatCard(
        icon: Icons.replay_rounded,
        label: 'Refunded',
        value: _fmt.format(stats.refunded),
        sub: '${stats.refundedCount} refunds',
        color: _danger,
      ),
    ];

    if (isNarrow) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: cards,
      );
    }
    return Row(
      children: cards
          .map((c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: c,
                ),
              ))
          .toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value, sub;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Flexible(
                child: Text(label,
                    style: const TextStyle(color: _textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: MediaQuery.of(context).size.width < 700 ? 14 : 16,
                  fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
          Text(sub, style: const TextStyle(color: _textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER BAR
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final PayStatus? statusFilter;
  final MethodFilter methodFilter;
  final DateTimeRange? dateRange;
  final TextEditingController searchCtrl;
  final ValueChanged<PayStatus?> onStatusChanged;
  final ValueChanged<MethodFilter> onMethodChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickDate, onClearDate;

  const _FilterBar({
    required this.statusFilter,
    required this.methodFilter,
    required this.dateRange,
    required this.searchCtrl,
    required this.onStatusChanged,
    required this.onMethodChanged,
    required this.onSearchChanged,
    required this.onPickDate,
    required this.onClearDate,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            style: const TextStyle(color: _textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by tenant, reference, or hostel…',
              hintStyle: const TextStyle(color: _textMuted, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: _textMuted, size: 18),
              filled: true,
              fillColor: _surfaceAlt,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                  label: 'All',
                  selected: statusFilter == null,
                  color: _textSecondary,
                  onTap: () => onStatusChanged(null)),
              ...PayStatus.values.where((s) => s != PayStatus.unknown).map(
                    (s) => _Chip(
                      label: s.label,
                      selected: statusFilter == s,
                      color: s.color,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 36,
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<MethodFilter>(
                    value: methodFilter,
                    dropdownColor: _surfaceAlt,
                    style: const TextStyle(color: _textPrimary, fontSize: 13),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _textSecondary, size: 18),
                    items: const [
                      DropdownMenuItem(
                          value: MethodFilter.all, child: Text('All methods')),
                      DropdownMenuItem(
                          value: MethodFilter.momo,
                          child: Text('Mobile Money')),
                      DropdownMenuItem(
                          value: MethodFilter.manual, child: Text('Manual')),
                      DropdownMenuItem(
                          value: MethodFilter.webhook,
                          child: Text('Webhook-confirmed')),
                    ],
                    onChanged: (v) {
                      if (v != null) onMethodChanged(v);
                    },
                  ),
                ),
              ),
              InkWell(
                onTap: onPickDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: dateRange != null ? _accentLow : _surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: dateRange != null ? _accent : _border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.date_range_rounded,
                        color: _textSecondary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      dateRange != null
                          ? '${fmt.format(dateRange!.start)} – ${fmt.format(dateRange!.end)}'
                          : 'Date range',
                      style: TextStyle(
                        color: dateRange != null ? _accent : _textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (dateRange != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onClearDate,
                        child: const Icon(Icons.close_rounded,
                            color: _textSecondary, size: 14),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : _surfaceAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : _border),
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? color : _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DESKTOP DATA TABLE
// ─────────────────────────────────────────────────────────────────────────────

class _DataTable extends StatelessWidget {
  final List<PaymentRecord> records;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<PaymentRecord> onOpen,
      onVerify,
      onRefund,
      onCheckSettlement;
  final ValueChanged<String> onCopyRef;

  const _DataTable({
    required this.records,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onOpen,
    required this.onVerify,
    required this.onRefund,
    required this.onCheckSettlement,
    required this.onCopyRef,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(children: [
            const SizedBox(width: 24), // checkbox column spacer
            _th('Tenant', flex: 3),
            _th('Hostel / Room', flex: 3),
            _th('Method', flex: 2),
            _th('Reference', flex: 3),
            _th('Amount', flex: 2, align: TextAlign.right),
            _th('Settlement', flex: 3, align: TextAlign.center),
            _th('Status', flex: 2, align: TextAlign.center),
            _th('Date', flex: 3),
            _th('', flex: 2),
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
                const Divider(height: 1, color: _border),
            itemBuilder: (ctx, i) {
              final r = records[i];
              return InkWell(
                onTap: () => onOpen(r),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    SizedBox(
                      width: 24,
                      child: Checkbox(
                        value: selectedIds.contains(r.id),
                        onChanged: (_) => onToggleSelect(r.id),
                        activeColor: _accent,
                        side: const BorderSide(color: _border),
                      ),
                    ),
                    Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.tenantName ?? '…',
                                style: const TextStyle(
                                    color: _textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                            Text(r.tenantEmail ?? '',
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11),
                                overflow: TextOverflow.ellipsis),
                          ],
                        )),
                    Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.hostelName ?? '…',
                                style: const TextStyle(
                                    color: _textPrimary, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                            Text('Room ${r.roomNumber ?? '—'}',
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11)),
                          ],
                        )),
                    Expanded(
                      flex: 2,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _MethodBadge(record: r),
                          _GatewayBadge(record: r),
                        ],
                      ),
                    ),
                    Expanded(
                        flex: 3,
                        child: Row(children: [
                          Flexible(
                              child: Text(r.reference,
                                  style: const TextStyle(
                                      color: _textSecondary,
                                      fontSize: 12,
                                      fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => onCopyRef(r.reference),
                            borderRadius: BorderRadius.circular(4),
                            child: const Icon(Icons.copy_rounded,
                                color: _textMuted, size: 14),
                          ),
                        ])),
                    Expanded(
                        flex: 2,
                        child: Text(_fmt.format(r.amount),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700))),
                    Expanded(
                        flex: 3,
                        child: Center(
                            child: _SettlementBadge(
                                record: r,
                                onCheck: () => onCheckSettlement(r)))),
                    Expanded(
                        flex: 2, child: Center(child: _StatusBadge(record: r))),
                    Expanded(
                        flex: 3,
                        child: Text(_dateFmt.format(r.paidAt),
                            style: const TextStyle(
                                color: _textSecondary, fontSize: 11))),
                    Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Tooltip(
                              message: r.gateway == 'moolre'
                                  ? 'Verify with Moolre'
                                  : 'Verify with Paystack',
                              child: InkWell(
                                onTap: () => onVerify(r),
                                borderRadius: BorderRadius.circular(6),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.verified_rounded,
                                      color: _teal, size: 16),
                                ),
                              ),
                            ),
                            if (r.isRefundable)
                              Tooltip(
                                message: 'Refund',
                                child: InkWell(
                                  onTap: () => onRefund(r),
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.replay_rounded,
                                        color: _danger, size: 16),
                                  ),
                                ),
                              ),
                          ],
                        )),
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
        child: Text(
          text,
          textAlign: align,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE CARD LIST
// ─────────────────────────────────────────────────────────────────────────────

class _CardList extends StatelessWidget {
  final List<PaymentRecord> records;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<PaymentRecord> onOpen,
      onVerify,
      onRefund,
      onCheckSettlement;
  final ValueChanged<String> onCopyRef;

  const _CardList({
    required this.records,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onOpen,
    required this.onVerify,
    required this.onRefund,
    required this.onCheckSettlement,
    required this.onCopyRef,
  });
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
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Checkbox(
                    value: selectedIds.contains(r.id),
                    onChanged: (_) => onToggleSelect(r.id),
                    activeColor: _accent,
                    side: const BorderSide(color: _border),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(r.tenantName ?? '…',
                        style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ),
                  Text(_fmt.format(r.amount),
                      style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ]),
                const SizedBox(height: 4),
                Text(r.hostelName ?? '…',
                    style:
                        const TextStyle(color: _textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(record: r),
                    _MethodBadge(record: r),
                    _GatewayBadge(record: r),
                    _SettlementBadge(
                        record: r, onCheck: () => onCheckSettlement(r)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  IconButton(
                    onPressed: () => onVerify(r),
                    icon: const Icon(Icons.verified_rounded,
                        size: 16, color: _teal),
                    tooltip: 'Verify',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  if (r.isRefundable) ...[
                    const SizedBox(width: 14),
                    IconButton(
                      onPressed: () => onRefund(r),
                      icon: const Icon(Icons.replay_rounded,
                          size: 16, color: _danger),
                      tooltip: 'Refund',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                  const Spacer(),
                  Row(children: [
                    Flexible(
                        child: Text(r.reference,
                            style: const TextStyle(
                                color: _textMuted,
                                fontSize: 11,
                                fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onCopyRef(r.reference),
                      child: const Icon(Icons.copy_rounded,
                          color: _textMuted, size: 13),
                    ),
                  ]),
                ]),
                const SizedBox(height: 6),
                Text(_dateFmt.format(r.paidAt),
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED BADGES
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final PaymentRecord record;
  const _StatusBadge({required this.record});

  @override
  Widget build(BuildContext context) {
    final c = record.status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.35)),
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

/// Shows which payment gateway actually processed this transaction —
/// distinct from `_MethodBadge`, which shows the mobile network (MTN/Vodafone)
/// or 'Manual'. Hidden for manual payments since no gateway was involved.
class _GatewayBadge extends StatelessWidget {
  final PaymentRecord record;
  const _GatewayBadge({required this.record});

  @override
  Widget build(BuildContext context) {
    if (record.gateway == 'manual') return const SizedBox.shrink();
    final isMoolre = record.gateway == 'moolre';
    final color = isMoolre ? _warning : _accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        isMoolre ? 'Moolre' : 'Paystack',
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  final PaymentRecord record;
  const _MethodBadge({required this.record});

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
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: _textSecondary),
          const SizedBox(width: 4),
          Flexible(
              child: Text(_label,
                  style: const TextStyle(color: _textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
          if (record.source == 'webhook') ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Confirmed server-side by Paystack webhook',
              child: Icon(Icons.cloud_done_rounded, size: 12, color: _teal),
            ),
          ],
        ],
      );
}

/// Shows whether a payment's money has actually landed with the landlord —
/// distinct from `_StatusBadge`, which only reflects the *student's* charge.
///
/// Reads `record.settlementState`, which is written by /api/checkSettlement
/// and /api/syncSettlements from Paystack's real Settlements API — this is
/// NOT a guess based on whether the landlord merely has a subaccount.
class _SettlementBadge extends StatelessWidget {
  final PaymentRecord record;
  final VoidCallback onCheck;
  const _SettlementBadge({required this.record, required this.onCheck});

  @override
  Widget build(BuildContext context) {
    if (!record.isSettlementCheckable) return const SizedBox.shrink();

    final state = record.settlementState;
    final showCheckAction = state == SettlementState.unknown ||
        state == SettlementState.pending ||
        state == SettlementState.overdue;

    return InkWell(
      onTap: showCheckAction ? onCheck : null,
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: state == SettlementState.settled && record.settledAt != null
            ? 'Settled ${_dateFmt.format(record.settledAt!)}'
            : showCheckAction
                ? 'Tap to check with Paystack'
                : state.label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: state.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: state.color.withOpacity(0.3)),
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
            if (showCheckAction) ...[
              const SizedBox(width: 3),
              Icon(Icons.refresh_rounded, size: 10, color: state.color),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT DETAIL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentDetailSheet extends StatelessWidget {
  final PaymentRecord record;
  final VoidCallback onVerify, onRefund, onCheckSettlement, onCopyRef;
  const _PaymentDetailSheet({
    required this.record,
    required this.onVerify,
    required this.onRefund,
    required this.onCheckSettlement,
    required this.onCopyRef,
  });

  @override
  Widget build(BuildContext context) {
    final r = record;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.tenantName ?? 'Payment ${r.id}',
                        style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Text('${r.hostelName ?? '—'} · Room ${r.roomNumber ?? '—'}',
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              _StatusBadge(record: r),
            ]),
          ),
          const Divider(height: 1, color: _border),
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
                _row(
                    'Gateway',
                    r.gateway == 'moolre'
                        ? 'Moolre'
                        : r.gateway == 'manual'
                            ? 'Manual'
                            : 'Paystack'), // ← add this
                _row(
                    'Payment #',
                    '${r.paymentNumber}'
                        '${r.isFirstPayment ? ' · first' : ''}'
                        '${r.isFinalPayment ? ' · final' : ''}'),
                _row('Confirmed by',
                    r.source == 'webhook' ? 'Paystack webhook' : 'Client app'),
                _row('Paid at', _dateFmt.format(r.paidAt)),
                if (r.verifiedAt != null)
                  _row('Last verified', _dateFmt.format(r.verifiedAt!)),
                if (r.gatewayStatus != null)
                  _row('Gateway status', r.gatewayStatus!),
                const SizedBox(height: 8),
                const Divider(color: _border),
                const SizedBox(height: 8),
                Text('Commission breakdown',
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _breakdownCell(
                        'Platform kept', r.commissionTaken, _teal),
                  ),
                  Expanded(
                    child: _breakdownCell(
                        'Landlord receives', r.landlordReceived, _accent),
                  ),
                ]),
                const SizedBox(height: 14),
                Text('Settlement',
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(children: [
                  _SettlementBadge(record: r, onCheck: onCheckSettlement),
                  if (r.isSettlementCheckable) ...[
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: onCheckSettlement,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, size: 13, color: _teal),
                          SizedBox(width: 3),
                          Text('Check now',
                              style: TextStyle(
                                  color: _teal,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ]),
                if (r.settlementCheckedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                      'Last checked ${_dateFmt.format(r.settlementCheckedAt!)}',
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
                ],
                if (r.status == PayStatus.refunded) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _dangerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _danger.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Refunded ${_fmt.format(r.refundedAmount ?? r.amount)}',
                            style: const TextStyle(
                                color: _danger, fontWeight: FontWeight.w700)),
                        if (r.refundedAt != null)
                          Text(_dateFmt.format(r.refundedAt!),
                              style: const TextStyle(
                                  color: _textSecondary, fontSize: 11)),
                        if (r.refundReason != null &&
                            r.refundReason!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Reason: ${r.refundReason}',
                                style: const TextStyle(
                                    color: _textSecondary, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ],
                if (r.note.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Note',
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(r.note,
                      style:
                          const TextStyle(color: _textSecondary, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onVerify,
                      icon: const Icon(Icons.verified_rounded, size: 16),
                      label: Text(record.gateway == 'moolre'
                          ? 'Verify with Moolre'
                          : 'Verify with Paystack'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _teal,
                        side: const BorderSide(color: _teal),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (r.isRefundable) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onRefund,
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Refund'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _danger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 20),
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
              colors: [_accent, Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Amount',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(_fmt.format(record.amount),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _row(String label, String value, {bool copyable = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
          if (copyable)
            InkWell(
              onTap: onCopyRef,
              child:
                  const Icon(Icons.copy_rounded, size: 14, color: _textMuted),
            ),
        ]),
      );

  Widget _breakdownCell(String label, double value, Color color) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
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

// ─────────────────────────────────────────────────────────────────────────────
// REFUND DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _RefundDialog extends StatefulWidget {
  final PaymentRecord record;
  const _RefundDialog({required this.record});

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final TextEditingController _amountCtrl;
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.record.amount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Dialog(
      backgroundColor: _surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _danger.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.replay_rounded, color: _danger, size: 28),
          ),
          const SizedBox(height: 16),
          const Text('Confirm Refund',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Refund ${r.tenantName ?? 'this guest'} via Paystack — ref ${r.reference}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Refund amount (GHS)',
              labelStyle: const TextStyle(color: _textMuted),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _danger)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            maxLines: 2,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Reason (optional)',
              labelStyle: const TextStyle(color: _textMuted),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _danger)),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textSecondary,
                  side: const BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  final amt = double.tryParse(_amountCtrl.text.trim());
                  if (amt == null || amt <= 0 || amt > r.amount) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Enter a valid amount up to ${_fmt.format(r.amount)}'),
                      backgroundColor: _danger,
                    ));
                    return;
                  }
                  Navigator.pop(
                      context,
                      _RefundResult(
                          amt,
                          _reasonCtrl.text.trim().isEmpty
                              ? null
                              : _reasonCtrl.text.trim()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Refund',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDLORD PAYOUTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordPayoutsTab extends StatelessWidget {
  const _LandlordPayoutsTab();

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 700;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('landlords').orderBy('full_name').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
              message: 'No landlords registered yet',
              icon: Icons.people_outline_rounded);
        }
        return ListView.builder(
          padding: EdgeInsets.all(isNarrow ? 14 : 24),
          itemCount: docs.length,
          itemBuilder: (ctx, i) => _LandlordPayoutCard(doc: docs[i]),
        );
      },
    );
  }
}

class _LandlordPayoutCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _LandlordPayoutCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final name = d['full_name']?.toString() ?? '—';
    final hasSubaccount =
        d['paystack_subaccount']?.toString().isNotEmpty == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(color: _accentLow, shape: BoxShape.circle),
              child: Center(
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: _accent, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Row(children: [
                    Icon(
                        hasSubaccount
                            ? Icons.bolt_rounded
                            : Icons.pending_actions_rounded,
                        size: 12,
                        color: hasSubaccount ? _success : _warning),
                    const SizedBox(width: 4),
                    Text(
                        hasSubaccount
                            ? 'Auto-settled via Paystack subaccount'
                            : 'No subaccount — needs manual payouts',
                        style: TextStyle(
                            fontSize: 11,
                            color: hasSubaccount ? _success : _warning)),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          // ── Aggregate this landlord's earnings from their payments ──────
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collectionGroup('payments')
                .where('landlord_id', isEqualTo: doc.id)
                .where('status', isEqualTo: 'paid')
                .snapshots(),
            builder: (ctx, paySnap) {
              double grossEarned = 0;
              double settledAmount = 0;
              double pendingSettlement = 0;
              for (final p in paySnap.data?.docs ?? []) {
                final d = p.data();
                final received =
                    (d['landlord_received'] as num?)?.toDouble() ?? 0;
                grossEarned += received;
                if (d['settlement_status'] == 'settled') {
                  settledAmount += received;
                } else {
                  pendingSettlement += received;
                }
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db
                    .collection('payouts')
                    .where('landlord_id', isEqualTo: doc.id)
                    .where('status', isEqualTo: 'completed')
                    .snapshots(),
                builder: (ctx2, payoutSnap) {
                  double totalPaidOut = 0;
                  for (final p in payoutSnap.data?.docs ?? []) {
                    totalPaidOut +=
                        (p.data()['amount'] as num?)?.toDouble() ?? 0;
                  }
                  // Subaccount landlords: only Paystack-settled money can be
                  // paid out (it isn't in the platform's balance until then).
                  // Manual-payout landlords have no subaccount step at all —
                  // the platform already holds the full amount the moment the
                  // payment is confirmed paid, so gross earned is payable.
                  final available = (hasSubaccount
                          ? settledAmount - totalPaidOut
                          : grossEarned - totalPaidOut)
                      .clamp(0, double.infinity)
                      .toDouble();

                  return Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: _miniStat(
                                'Gross earned', grossEarned, _accent)),
                        Expanded(
                            child: _miniStat('Settled', settledAmount, _teal)),
                        Expanded(
                            child: _miniStat(
                                'Pending', pendingSettlement, _warning)),
                        Expanded(
                            child:
                                _miniStat('Paid out', totalPaidOut, _success)),
                      ]),
                      const SizedBox(height: 8),
                      if (pendingSettlement > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${_fmt.format(pendingSettlement)} not yet settled by Paystack — excluded from payout amount.',
                            style:
                                const TextStyle(color: _warning, fontSize: 10),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: available > 0
                              ? () => _openPayoutDialog(
                                  context, doc.id, name, available)
                              : null,
                          icon: Icon(Icons.send_rounded,
                              size: 16,
                              color: available > 0 ? _accent : _textMuted),
                          label: Text(available > 0
                              ? 'Pay out ${_fmt.format(available)}${hasSubaccount ? ' (settled only)' : ''}'
                              : 'Nothing settled to pay out yet'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            disabledForegroundColor: _textMuted,
                            side: BorderSide(
                                color: available > 0 ? _accent : _border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (hasSubaccount)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'This landlord auto-settles via Paystack split — use this button only for one-off manual top-ups or corrections.',
                            style: const TextStyle(
                                color: _textMuted, fontSize: 10),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          _PayoutHistory(landlordId: doc.id),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(_fmt.format(value),
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      );

  Future<void> _openPayoutDialog(BuildContext context, String landlordId,
      String name, double outstanding) async {
    final confirmed = await showDialog<_PayoutResult>(
      context: context,
      builder: (_) =>
          _PayoutDialog(landlordName: name, suggestedAmount: outstanding),
    );
    if (confirmed == null) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _surfaceAlt,
      content: Row(children: const [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
        SizedBox(width: 12),
        Text('Initiating payout via Paystack…',
            style: TextStyle(color: _textPrimary)),
      ]),
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));

    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/payouts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'initiate',
          'landlordId': landlordId,
          'amount': confirmed.amount,
          'note': confirmed.note,
        }),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final status = data['status'] as String?;
        final payoutId = data['payoutId'] as String?;

        if (status == 'otp' && payoutId != null) {
          // Paystack account has transfer OTP enabled — the code goes to
          // whoever owns the Paystack account (not the landlord), since
          // it authorizes money leaving your balance.
          final otp = await _promptForTransferOtp(context);
          if (otp == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Payout to $name is saved but pending OTP confirmation. Retry it from the Payouts list when ready.'),
              backgroundColor: _warning,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
            ));
            return;
          }
          await _finalizeTransferOtp(
              context, payoutId, otp, name, confirmed.amount);
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Payout of ${_fmt.format(confirmed.amount)} to $name initiated.'),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      } else {
        final data = jsonDecode(res.body);
        throw Exception(data['error'] ?? 'Payout failed');
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payout failed: $e'),
        backgroundColor: _danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  Future<String?> _promptForTransferOtp(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Transfer',
            style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Paystack account requires OTP for transfers. Enter the code sent '
              'to the phone/email on your Paystack account (not the landlord\'s).',
              style:
                  TextStyle(color: _textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: _textPrimary),
              decoration: InputDecoration(
                labelText: 'OTP',
                labelStyle: const TextStyle(color: _textSecondary),
                filled: true,
                fillColor: _surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _accent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child:
                const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizeTransferOtp(BuildContext context, String payoutId,
      String otp, String name, double amount) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _surfaceAlt,
      content: Row(children: const [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
        SizedBox(width: 12),
        Text('Confirming transfer…', style: TextStyle(color: _textPrimary)),
      ]),
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/payouts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'action': 'finalize', 'payoutId': payoutId, 'otp': otp}),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final data = jsonDecode(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payout of ${_fmt.format(amount)} to $name confirmed.'),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      } else {
        throw Exception(data['error'] ?? 'OTP confirmation failed');
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('OTP confirmation failed: $e'),
        backgroundColor: _danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }
}

class _PayoutHistory extends StatelessWidget {
  final String landlordId;
  const _PayoutHistory({required this.landlordId});

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
        if (docs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(color: _border),
              const SizedBox(height: 8),
              const Text('Recent payouts',
                  style: TextStyle(
                      color: _textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...docs.map((d) {
                final p = d.data();
                final status = p['status']?.toString() ?? 'processing';
                final amount = (p['amount'] as num?)?.toDouble() ?? 0;
                final ts = p['initiated_at'] as Timestamp?;
                final color = status == 'completed'
                    ? _success
                    : status == 'failed'
                        ? _danger
                        : _warning;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(Icons.circle, size: 6, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_fmt.format(amount),
                            style: const TextStyle(
                                color: _textSecondary, fontSize: 12))),
                    Text(status,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Text(
                        ts != null
                            ? DateFormat('MMM d').format(ts.toDate())
                            : '—',
                        style:
                            const TextStyle(color: _textMuted, fontSize: 11)),
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

class _PayoutResult {
  final double amount;
  final String? note;
  const _PayoutResult(this.amount, this.note);
}

class _PayoutDialog extends StatefulWidget {
  final String landlordName;
  final double suggestedAmount;
  const _PayoutDialog(
      {required this.landlordName, required this.suggestedAmount});

  @override
  State<_PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends State<_PayoutDialog> {
  late final TextEditingController _amountCtrl;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.suggestedAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration:
                BoxDecoration(color: _accentLow, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: _accent, size: 26),
          ),
          const SizedBox(height: 16),
          Text('Pay out ${widget.landlordName}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'This sends a real Paystack Transfer to the landlord\'s registered MoMo / bank account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Amount (GHS)',
              labelStyle: const TextStyle(color: _textMuted),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _accent)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              labelStyle: const TextStyle(color: _textMuted),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _accent)),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textSecondary,
                  side: const BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  final amt = double.tryParse(_amountCtrl.text.trim());
                  if (amt == null || amt <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter a valid amount'),
                      backgroundColor: _danger,
                    ));
                    return;
                  }
                  Navigator.pop(
                      context,
                      _PayoutResult(
                          amt,
                          _noteCtrl.text.trim().isEmpty
                              ? null
                              : _noteCtrl.text.trim()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Send Payout',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyState({
    this.message = 'No payments found',
    this.icon = Icons.receipt_long_rounded,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
            child: Column(children: [
          Icon(icon, color: _textMuted, size: 48),
          const SizedBox(height: 12),
          Text(message,
              style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Try adjusting your filters',
              style: TextStyle(color: _textMuted, fontSize: 13)),
        ])),
      );
}
