// lib/screens/admin/panes/analytics_pane.dart
//
// ═══════════════════════════════════════════════════════════════════════════
//  ANALYTICS & INSIGHTS PANE — RoomzyFind Admin
//
//  A full-system analytics dashboard pulling from bookings, landlords,
//  hostels, rooms, students, and payments. Includes:
//    • KPI grid with animated counters + period-over-period trend badges
//    • Live "Attention Needed" alerts panel (anomaly detection)
//    • Revenue & bookings trend chart (day/week/month granularity)
//    • Booking-status donut chart (hand-drawn, no chart package needed)
//    • Payment-method breakdown
//    • Top Hostels / Top Landlords leaderboards
//    • Occupancy heat-list across all hostels
//    • "Smart Insights" auto-generated summary
//    • Trend-based revenue forecast for next period
//    • Report Center: pick a report type (Bookings / Hostels / Rooms /
//      Landlords / Students / Payments / Full System), an optional date
//      range, and PDF or CSV — generates that specific report from live
//      Firestore data.
//    • Legacy quick PDF/CSV export (current dashboard period) + a
//      "Scheduled Reports" preference
//
//  ── NEW DEPENDENCIES — add to pubspec.yaml if not already present ─────────
//      pdf: ^3.10.8
//      printing: ^5.12.0
//  (share_plus / path_provider are already used elsewhere in this app)
//
//  ── WIRING IT IN ───────────────────────────────────────────────────────────
//  Wherever the admin shell switches on AdminSection (e.g. a body switch in
//  your dashboard scaffold), add:
//      case AdminSection.analytics: return const AnalyticsPane();
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../utils/admin_helpers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME TOKENS — matches the rest of the admin panel
// ─────────────────────────────────────────────────────────────────────────────

const _kGreen = Color(0xFF1B4332);
const _kGreenAccent = Color(0xFF2D6A4F);
const _kGreenLight = Color(0xFF4ADE80);
const _kBg = Color(0xFFF2F4F0);
const _kSurface = Color(0xFFFFFFFF);
const _kSurfaceAlt = Color(0xFFF9FAFB);
const _kBorder = Color(0xFFE5E7EB);
const _kTextDark = Color(0xFF111827);
const _kTextMid = Color(0xFF374151);
const _kTextLight = Color(0xFF6B7280);
const _kTextMuted = Color(0xFF9CA3AF);
const _kBlue = Color(0xFF2563EB);
const _kOrange = Color(0xFFEA580C);
const _kRed = Color(0xFFDC2626);
const _kPurple = Color(0xFF7C3AED);
const _kTeal = Color(0xFF0D9488);

final _fmt = NumberFormat('#,##0.00');
final _fmt0 = NumberFormat('#,##0');

bool _isMobile(BuildContext c) => MediaQuery.of(c).size.width < 640;
bool _isTablet(BuildContext c) {
  final w = MediaQuery.of(c).size.width;
  return w >= 640 && w < 1040;
}

// ─────────────────────────────────────────────────────────────────────────────
// PERIOD MODEL
// ─────────────────────────────────────────────────────────────────────────────

enum _Period { today, week, month, quarter, year, all }

extension _PeriodX on _Period {
  String get label => switch (this) {
        _Period.today => 'Today',
        _Period.week => '7 Days',
        _Period.month => '30 Days',
        _Period.quarter => '90 Days',
        _Period.year => '12 Months',
        _Period.all => 'All Time',
      };

  /// Start of the current window (null = no lower bound).
  DateTime? get start {
    final now = DateTime.now();
    switch (this) {
      case _Period.today:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        return now.subtract(const Duration(days: 7));
      case _Period.month:
        return now.subtract(const Duration(days: 30));
      case _Period.quarter:
        return now.subtract(const Duration(days: 90));
      case _Period.year:
        return now.subtract(const Duration(days: 365));
      case _Period.all:
        return null;
    }
  }

  /// Equal-length window immediately preceding [start], for trend deltas.
  ({DateTime start, DateTime end})? get previousWindow {
    final s = start;
    if (s == null) return null;
    final len = DateTime.now().difference(s);
    return (start: s.subtract(len), end: s);
  }
}

enum _Granularity { day, week, month }

// ─────────────────────────────────────────────────────────────────────────────
// DATA BUNDLE — raw docs pulled live from Firestore
// ─────────────────────────────────────────────────────────────────────────────

class _Bundle {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> bookings;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> landlords;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> hostels;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> rooms;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> students;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> payments;

  const _Bundle({
    required this.bookings,
    required this.landlords,
    required this.hostels,
    required this.rooms,
    required this.students,
    required this.payments,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPUTED STATS
// ─────────────────────────────────────────────────────────────────────────────

class _Stats {
  double revenue = 0;
  double commission = 0;
  double landlordPayout = 0;
  int totalBookings = 0;
  int confirmedBookings = 0;
  int pendingBookings = 0;
  int declinedBookings = 0;
  int fullyPaid = 0;
  int depositOnly = 0;

  final Map<String, double> revenueByHostel = {};
  final Map<String, int> bookingsByHostel = {};
  final Map<String, double> revenueByLandlord = {};
  final Map<String, int> bookingsByLandlord = {};
  final Map<String, int> bookingsBySchool = {};
  final Map<String, double> revenueBySlot = {}; // bucketed by granularity key
  final Map<String, double> revenueByMethod = {};

  double get avgBookingValue =>
      totalBookings == 0 ? 0 : revenue / totalBookings;
  double get confirmRate =>
      totalBookings == 0 ? 0 : confirmedBookings / totalBookings * 100;
}

_Stats _computeStats({
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> bookings,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> payments,
  required DateTime? from,
  required DateTime? to,
  required _Granularity granularity,
}) {
  final s = _Stats();
  final bucketFmt = switch (granularity) {
    _Granularity.day => DateFormat('MMM d'),
    _Granularity.week => DateFormat("'W'w MMM"),
    _Granularity.month => DateFormat('MMM yyyy'),
  };

  // ── Booking counts & booking-level groupings ────────────────────────────
  // Keyed by `booked_at` — this is "how many bookings were CREATED in this
  // window". We deliberately do NOT sum `amount_paid` here: that field is a
  // running cumulative total on the booking doc that gets overwritten on
  // every payment (deposit now, balance later), so filtering it by a date
  // window would double-count or misattribute revenue. Actual money figures
  // come from the immutable `payments` subcollection docs below instead.
  for (final doc in bookings) {
    final d = doc.data();
    final ts = d['booked_at'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    if (dt == null) continue;
    if (from != null && dt.isBefore(from)) continue;
    if (to != null && dt.isAfter(to)) continue;

    final status = (d['status'] ?? 'pending').toString();
    final paymentStatus = (d['payment_status'] ?? 'pending').toString();
    final hostel = (d['hostel_name'] ?? 'Unknown').toString();
    final landlordId = (d['landlord_id'] ?? '').toString();
    final school = (d['school'] ?? 'Unknown').toString();

    s.totalBookings++;
    if (status == 'confirmed') {
      s.confirmedBookings++;
    } else if (status == 'declined' || status == 'cancelled') {
      s.declinedBookings++;
    } else {
      s.pendingBookings++;
    }
    if (paymentStatus == 'fully_paid') s.fullyPaid++;
    if (paymentStatus == 'deposit_paid') s.depositOnly++;

    s.bookingsByHostel[hostel] = (s.bookingsByHostel[hostel] ?? 0) + 1;
    if (landlordId.isNotEmpty) {
      s.bookingsByLandlord[landlordId] =
          (s.bookingsByLandlord[landlordId] ?? 0) + 1;
    }
    s.bookingsBySchool[school] = (s.bookingsBySchool[school] ?? 0) + 1;
  }

  // ── Revenue, commission & money-level groupings ─────────────────────────
  // Keyed by `paid_at` on each individual payment record — this is the
  // correct source of truth for "how much money moved in this window",
  // since each doc represents one real transaction and never changes after
  // it's written. Denormalized fields (hostel_name, landlord_id, etc.) were
  // written onto the payment doc at the time of payment, so no extra joins
  // are needed here.
  for (final doc in payments) {
    final d = doc.data();
    final ts = d['paid_at'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    if (dt == null) continue;
    if (from != null && dt.isBefore(from)) continue;
    if (to != null && dt.isAfter(to)) continue;

    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final commissionTaken = (d['commission_taken'] as num?)?.toDouble() ?? 0;
    final landlordReceived = (d['landlord_received'] as num?)?.toDouble() ??
        (amount - commissionTaken);
    final hostel = (d['hostel_name'] ?? 'Unknown').toString();
    final landlordId = (d['landlord_id'] ?? '').toString();
    final method = (d['method'] ?? 'unknown').toString();
    final provider = (d['provider'] ?? '').toString();

    s.revenue += amount;
    s.commission += commissionTaken;
    s.landlordPayout += landlordReceived;

    s.revenueByHostel[hostel] = (s.revenueByHostel[hostel] ?? 0) + amount;
    if (landlordId.isNotEmpty) {
      s.revenueByLandlord[landlordId] =
          (s.revenueByLandlord[landlordId] ?? 0) + amount;
    }

    final label = method == 'manual'
        ? 'Manual'
        : (provider == 'mtn'
            ? 'MTN MoMo'
            : (provider == 'vodafone' ? 'Vodafone Cash' : 'Mobile Money'));
    s.revenueByMethod[label] = (s.revenueByMethod[label] ?? 0) + amount;

    final key = bucketFmt.format(dt);
    s.revenueBySlot[key] = (s.revenueBySlot[key] ?? 0) + amount;
  }

  return s;
}

double _pctChange(double current, double previous) {
  if (previous == 0) return current == 0 ? 0 : 100;
  return ((current - previous) / previous) * 100;
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PANE
// ─────────────────────────────────────────────────────────────────────────────

class AnalyticsPane extends StatefulWidget {
  const AnalyticsPane({super.key});

  @override
  State<AnalyticsPane> createState() => _AnalyticsPaneState();
}

class _AnalyticsPaneState extends State<AnalyticsPane> {
  _Period _period = _Period.month;
  _Granularity _granularity = _Granularity.day;
  bool _exportingPdf = false;
  bool _exportingCsv = false;

  final _db = FirebaseFirestore.instance;

  Query<Map<String, dynamic>> get _paymentsQuery {
    Query<Map<String, dynamic>> q =
        _db.collectionGroup('payments').orderBy('paid_at', descending: true);
    final start = _period.start;
    if (start != null) {
      q = q.where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    }
    return q.limit(2000);
  }

  void _autoGranularity() {
    setState(() {
      _granularity = switch (_period) {
        _Period.today => _Granularity.day,
        _Period.week => _Granularity.day,
        _Period.month => _Granularity.day,
        _Period.quarter => _Granularity.week,
        _Period.year => _Granularity.month,
        _Period.all => _Granularity.month,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Column(
        children: [
          _Header(
            period: _period,
            onPeriodChanged: (p) {
              setState(() => _period = p);
              _autoGranularity();
            },
            onExportPdf: _exportPdf,
            onExportCsv: _exportCsv,
            onScheduleReports: _openScheduleDialog,
            onOpenReportCenter: _openReportCenter,
            exportingPdf: _exportingPdf,
            exportingCsv: _exportingCsv,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db.collection('bookings').snapshots(),
              builder: (context, bookingsSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _db.collection('landlords').snapshots(),
                  builder: (context, landlordsSnap) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _db.collection('hostels').snapshots(),
                      builder: (context, hostelsSnap) {
                        return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>>(
                          stream: _db.collection('rooms').snapshots(),
                          builder: (context, roomsSnap) {
                            return StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>>(
                              stream: _db
                                  .collection('users')
                                  .where('role', isEqualTo: 'student')
                                  .snapshots(),
                              builder: (context, studentsSnap) {
                                return StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _paymentsQuery.snapshots(),
                                  builder: (context, paymentsSnap) {
                                    final loading = [
                                      bookingsSnap,
                                      landlordsSnap,
                                      hostelsSnap,
                                      roomsSnap,
                                      studentsSnap,
                                    ].any((s) =>
                                        s.connectionState ==
                                            ConnectionState.waiting &&
                                        !s.hasData);

                                    if (loading) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                            color: _kGreenAccent),
                                      );
                                    }

                                    final bundle = _Bundle(
                                      bookings: bookingsSnap.data?.docs ?? [],
                                      landlords: landlordsSnap.data?.docs ?? [],
                                      hostels: hostelsSnap.data?.docs ?? [],
                                      rooms: roomsSnap.data?.docs ?? [],
                                      students: studentsSnap.data?.docs ?? [],
                                      payments: paymentsSnap.data?.docs ?? [],
                                    );

                                    return _AnalyticsBody(
                                      bundle: bundle,
                                      period: _period,
                                      granularity: _granularity,
                                      onGranularityChanged: (g) =>
                                          setState(() => _granularity = g),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── EXPORT: PDF (quick export — current dashboard period) ──────────────
  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      final snap = await _oneShotBundle();
      final stats = _computeStats(
        bookings: snap.bookings,
        payments: snap.payments,
        from: _period.start,
        to: null,
        granularity: _granularity,
      );
      final bytes = await _buildPdfReport(snap, stats, _period);

      if (kIsWeb) {
        await Printing.sharePdf(
            bytes: bytes,
            filename:
                'roomzyfind_analytics_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/roomzyfind_analytics_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'RoomzyFind Analytics Report',
          text: 'Analytics report for ${_period.label}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF export failed: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  // ── EXPORT: CSV (quick export — raw bookings) ───────────────────────────
  Future<void> _exportCsv() async {
    setState(() => _exportingCsv = true);
    try {
      final snap = await _oneShotBundle();
      final csv = _bookingsToCsv(snap.bookings);
      await _deliverCsv(csv, 'roomzyfind_bookings');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('CSV export failed: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _deliverCsv(String csv, String baseName) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('CSV copied to clipboard — paste into Excel/Sheets'),
          backgroundColor: _kGreenAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${baseName}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'RoomzyFind Export',
      );
    }
  }

  Future<_Bundle> _oneShotBundle() async {
    final results = await Future.wait([
      _db.collection('bookings').get(),
      _db.collection('landlords').get(),
      _db.collection('hostels').get(),
      _db.collection('rooms').get(),
      _db.collection('users').where('role', isEqualTo: 'student').get(),
      _paymentsQuery.get(),
    ]);
    return _Bundle(
      bookings: results[0].docs,
      landlords: results[1].docs,
      hostels: results[2].docs,
      rooms: results[3].docs,
      students: results[4].docs,
      payments: results[5].docs,
    );
  }

  /// Full, un-windowed bundle (ignores the dashboard's active period) — used
  /// by the Report Center, which has its own independent date range picker.
  Future<_Bundle> _fullBundle() async {
    final results = await Future.wait([
      _db.collection('bookings').get(),
      _db.collection('landlords').get(),
      _db.collection('hostels').get(),
      _db.collection('rooms').get(),
      _db.collection('users').where('role', isEqualTo: 'student').get(),
      _db.collectionGroup('payments').get(),
    ]);
    return _Bundle(
      bookings: results[0].docs,
      landlords: results[1].docs,
      hostels: results[2].docs,
      rooms: results[3].docs,
      students: results[4].docs,
      payments: results[5].docs,
    );
  }

  void _openScheduleDialog() {
    showDialog(
        context: context, builder: (_) => const _ScheduleReportsDialog());
  }

  void _openReportCenter() {
    showDialog(
      context: context,
      builder: (_) => _ReportCenterDialog(fetchFullBundle: _fullBundle),
    );
  }
}

String _bookingsToCsv(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> bookings) {
  final buf = StringBuffer();
  buf.writeln(
      'Guest,Hostel,Landlord ID,School,Status,Payment Status,Amount,Amount Paid,Commission,Booked At');
  for (final doc in bookings) {
    final d = doc.data();
    final ts = d['booked_at'];
    final dateStr = ts is Timestamp
        ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate())
        : '';
    buf.writeln([
      d['name'] ?? '',
      d['hostel_name'] ?? '',
      d['landlord_id'] ?? '',
      d['school'] ?? '',
      d['status'] ?? '',
      d['payment_status'] ?? '',
      (d['amount'] ?? 0).toString(),
      (d['amount_paid'] ?? 0).toString(),
      (d['commission_collected'] ?? 0).toString(),
      dateStr,
    ].map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','));
  }
  return buf.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final _Period period;
  final ValueChanged<_Period> onPeriodChanged;
  final VoidCallback onExportPdf, onExportCsv, onScheduleReports;
  final VoidCallback onOpenReportCenter;
  final bool exportingPdf, exportingCsv;

  const _Header({
    required this.period,
    required this.onPeriodChanged,
    required this.onExportPdf,
    required this.onExportCsv,
    required this.onScheduleReports,
    required this.onOpenReportCenter,
    required this.exportingPdf,
    required this.exportingCsv,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Container(
      color: _kGreen,
      padding: EdgeInsets.fromLTRB(mobile ? 14 : 24, 16, mobile ? 10 : 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.insights_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Analytics & Insights',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: mobile ? 16 : 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3)),
                    Text('Full-system performance · live',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 11.5)),
                  ],
                ),
              ),
              const _LivePulseDot(),
              const SizedBox(width: 6),
              if (!mobile)
                const Text('Live',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              _ReportsMenu(
                onExportPdf: onExportPdf,
                onExportCsv: onExportCsv,
                onScheduleReports: onScheduleReports,
                onOpenReportCenter: onOpenReportCenter,
                exportingPdf: exportingPdf,
                exportingCsv: exportingCsv,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _Period.values.map((p) {
                final selected = p == period;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onPeriodChanged(p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white
                            : Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected ? _kGreen : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();
  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
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
        opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
        child: Container(
          width: 8,
          height: 8,
          decoration:
              const BoxDecoration(color: _kGreenLight, shape: BoxShape.circle),
        ),
      );
}

class _ReportsMenu extends StatelessWidget {
  final VoidCallback onExportPdf, onExportCsv, onScheduleReports;
  final VoidCallback onOpenReportCenter;
  final bool exportingPdf, exportingCsv;
  const _ReportsMenu({
    required this.onExportPdf,
    required this.onExportCsv,
    required this.onScheduleReports,
    required this.onOpenReportCenter,
    required this.exportingPdf,
    required this.exportingCsv,
  });

  @override
  Widget build(BuildContext context) {
    final busy = exportingPdf || exportingCsv;
    return PopupMenuButton<String>(
      enabled: !busy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      onSelected: (v) {
        if (v == 'pdf') onExportPdf();
        if (v == 'csv') onExportCsv();
        if (v == 'schedule') onScheduleReports();
        if (v == 'report_center') onOpenReportCenter();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'report_center',
          child: Row(children: [
            Icon(Icons.dashboard_customize_rounded, size: 16, color: _kBlue),
            SizedBox(width: 10),
            Text('Generate custom report…',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'pdf',
          child: Row(children: [
            Icon(Icons.picture_as_pdf_rounded, size: 16, color: _kRed),
            SizedBox(width: 10),
            Text('Quick PDF (current period)', style: TextStyle(fontSize: 13)),
          ]),
        ),
        const PopupMenuItem(
          value: 'csv',
          child: Row(children: [
            Icon(Icons.table_chart_rounded, size: 16, color: _kGreenAccent),
            SizedBox(width: 10),
            Text('Quick CSV (bookings)', style: TextStyle(fontSize: 13)),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'schedule',
          child: Row(children: [
            Icon(Icons.schedule_send_rounded, size: 16, color: _kPurple),
            SizedBox(width: 10),
            Text('Scheduled reports…', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: _kGreen))
            else
              const Icon(Icons.download_rounded, size: 16, color: _kGreen),
            const SizedBox(width: 6),
            Text(
              busy ? 'Exporting…' : 'Reports',
              style: const TextStyle(
                  color: _kGreen, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.expand_more_rounded, size: 16, color: _kGreen),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BODY
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyticsBody extends StatelessWidget {
  final _Bundle bundle;
  final _Period period;
  final _Granularity granularity;
  final ValueChanged<_Granularity> onGranularityChanged;

  const _AnalyticsBody({
    required this.bundle,
    required this.period,
    required this.granularity,
    required this.onGranularityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final tablet = _isTablet(context);

    final current = _computeStats(
      bookings: bundle.bookings,
      payments: bundle.payments,
      from: period.start,
      to: null,
      granularity: granularity,
    );

    final prevWindow = period.previousWindow;
    final previous = prevWindow == null
        ? null
        : _computeStats(
            bookings: bundle.bookings,
            payments: const [],
            from: prevWindow.start,
            to: prevWindow.end,
            granularity: granularity,
          );

    // Occupancy across all rooms.
    // Room docs only carry `hostel_id` (see hostel_detail_screen.dart's rooms
    // query), not a denormalized hostel_name, so we join against the
    // hostels bundle in-memory rather than assuming a field that isn't there.
    final hostelNameById = {
      for (final h in bundle.hostels)
        h.id: (h.data()['hostel_name'] ?? 'Unknown').toString()
    };
    int totalCapacity = 0, totalBooked = 0;
    final Map<String, ({int booked, int capacity})> occByHostel = {};
    for (final doc in bundle.rooms) {
      final d = doc.data();
      final cap = (d['capacity'] as num?)?.toInt() ?? 0;
      final booked = (d['booked'] as num?)?.toInt() ?? 0;
      totalCapacity += cap;
      totalBooked += booked;
      final hostelId = (d['hostel_id'] ?? '').toString();
      final hostel = hostelNameById[hostelId] ?? 'Unknown';
      final prior = occByHostel[hostel] ?? (booked: 0, capacity: 0);
      occByHostel[hostel] =
          (booked: prior.booked + booked, capacity: prior.capacity + cap);
    }
    final occupancyRate =
        totalCapacity == 0 ? 0.0 : (totalBooked / totalCapacity) * 100;

    // Forecast: growth-rate extrapolation from bucketed revenue series
    final series = current.revenueBySlot.values.toList();
    double forecastNext = current.revenue;
    if (series.length >= 4) {
      final half = series.length ~/ 2;
      final firstHalf = series.sublist(0, half).fold(0.0, (a, b) => a + b);
      final secondHalf = series.sublist(half).fold(0.0, (a, b) => a + b);
      final growth =
          firstHalf == 0 ? 0.0 : (secondHalf - firstHalf) / firstHalf;
      forecastNext = current.revenue * (1 + growth.clamp(-0.5, 1.5));
    }

    // ── Attention Needed — live anomaly / alert detection ───────────────
    final alerts = <_Alert>[];

    final now = DateTime.now();
    final staleThreshold = now.subtract(const Duration(days: 3));
    int stalePending = 0;
    for (final doc in bundle.bookings) {
      final d = doc.data();
      final status = (d['status'] ?? 'pending').toString();
      final ts = d['booked_at'];
      final dt = ts is Timestamp ? ts.toDate() : null;
      if (status == 'pending' && dt != null && dt.isBefore(staleThreshold)) {
        stalePending++;
      }
    }
    if (stalePending > 0) {
      alerts.add(_Alert(
        icon: Icons.hourglass_bottom_rounded,
        color: _kOrange,
        title:
            '$stalePending booking${stalePending == 1 ? '' : 's'} stuck pending 3+ days',
        subtitle:
            'Follow up with guests or landlords to confirm or release these slots.',
      ));
    }

    int unfundedLandlords = 0;
    for (final id in current.revenueByLandlord.keys) {
      final doc = bundle.landlords.where((l) => l.id == id).firstOrNull;
      final hasSubaccount =
          (doc?.data()['paystack_subaccount']?.toString().isNotEmpty ?? false);
      if (!hasSubaccount) unfundedLandlords++;
    }
    if (unfundedLandlords > 0) {
      alerts.add(_Alert(
        icon: Icons.account_balance_rounded,
        color: _kPurple,
        title:
            '$unfundedLandlords landlord${unfundedLandlords == 1 ? '' : 's'} earning without auto-payout set up',
        subtitle:
            'These payouts are being handled manually — consider onboarding them to Paystack subaccounts.',
      ));
    }

    final soldOut = occByHostel.entries
        .where((e) =>
            e.value.capacity > 0 && e.value.booked / e.value.capacity >= 0.95)
        .length;
    if (soldOut > 0) {
      alerts.add(_Alert(
        icon: Icons.local_fire_department_rounded,
        color: _kRed,
        title: '$soldOut hostel${soldOut == 1 ? '' : 's'} near full capacity',
        subtitle:
            'Demand is high — a good moment to onboard more rooms in that area.',
      ));
    }

    final emptyHostels = occByHostel.entries
        .where((e) => e.value.capacity > 0 && e.value.booked == 0)
        .length;
    if (emptyHostels > 0) {
      alerts.add(_Alert(
        icon: Icons.storefront_rounded,
        color: _kBlue,
        title:
            '$emptyHostels hostel${emptyHostels == 1 ? '' : 's'} with zero bookings',
        subtitle:
            'These listings may need better photos, pricing, or featured placement.',
      ));
    }

    if (previous != null) {
      final change = _pctChange(current.revenue, previous.revenue);
      if (change <= -15) {
        alerts.add(_Alert(
          icon: Icons.trending_down_rounded,
          color: _kRed,
          title:
              'Revenue down ${change.abs().toStringAsFixed(0)}% vs the previous period',
          subtitle:
              'Check for payment failures, listing visibility, or seasonal drop-off.',
        ));
      }
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(mobile ? 14 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alerts.isNotEmpty) ...[
            _AlertsPanel(alerts: alerts),
            SizedBox(height: mobile ? 16 : 22),
          ],
          _SmartInsights(
            current: current,
            previous: previous,
            occupancyRate: occupancyRate,
            landlords: bundle.landlords,
          ),
          SizedBox(height: mobile ? 16 : 22),
          _SectionHead(icon: Icons.speed_rounded, title: 'Key Metrics'),
          const SizedBox(height: 12),
          _KpiGrid(
            mobile: mobile,
            tablet: tablet,
            items: [
              _Kpi(
                icon: Icons.payments_rounded,
                label: 'Revenue Collected',
                value: 'GHS ${_fmt.format(current.revenue)}',
                color: _kGreenAccent,
                delta: previous == null
                    ? null
                    : _pctChange(current.revenue, previous.revenue),
              ),
              _Kpi(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Platform Commission',
                value: 'GHS ${_fmt.format(current.commission)}',
                color: _kTeal,
                delta: previous == null
                    ? null
                    : _pctChange(current.commission, previous.commission),
              ),
              _Kpi(
                icon: Icons.receipt_long_rounded,
                label: 'Total Bookings',
                value: _fmt0.format(current.totalBookings),
                color: _kBlue,
                delta: previous == null
                    ? null
                    : _pctChange(current.totalBookings.toDouble(),
                        previous.totalBookings.toDouble()),
              ),
              _Kpi(
                icon: Icons.check_circle_rounded,
                label: 'Confirmation Rate',
                value: '${current.confirmRate.toStringAsFixed(1)}%',
                color: _kGreen,
                delta: previous == null
                    ? null
                    : current.confirmRate - previous.confirmRate,
              ),
              _Kpi(
                icon: Icons.school_rounded,
                label: 'Registered Students',
                value: _fmt0.format(bundle.students.length),
                color: _kPurple,
                delta: null,
              ),
              _Kpi(
                icon: Icons.home_work_rounded,
                label: 'Active Landlords',
                value: _fmt0.format(bundle.landlords.length),
                color: _kOrange,
                delta: null,
              ),
              _Kpi(
                icon: Icons.pie_chart_rounded,
                label: 'Occupancy Rate',
                value: '${occupancyRate.toStringAsFixed(1)}%',
                color: _kRed,
                delta: null,
              ),
              _Kpi(
                icon: Icons.calculate_rounded,
                label: 'Avg Booking Value',
                value: 'GHS ${_fmt.format(current.avgBookingValue)}',
                color: const Color(0xFF0EA5E9),
                delta: null,
              ),
            ],
          ),
          SizedBox(height: mobile ? 20 : 28),
          Row(children: [
            Expanded(
                child: _SectionHead(
                    icon: Icons.show_chart_rounded, title: 'Revenue Trend')),
            _GranularityToggle(
                value: granularity, onChanged: onGranularityChanged),
          ]),
          const SizedBox(height: 12),
          _TrendChart(data: current.revenueBySlot),
          SizedBox(height: mobile ? 20 : 28),
          mobile
              ? Column(children: [
                  _BookingStatusCard(stats: current),
                  const SizedBox(height: 14),
                  _PaymentMethodCard(stats: current),
                ])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _BookingStatusCard(stats: current)),
                    const SizedBox(width: 14),
                    Expanded(child: _PaymentMethodCard(stats: current)),
                  ],
                ),
          SizedBox(height: mobile ? 20 : 28),
          _SectionHead(
              icon: Icons.emoji_events_rounded,
              title: 'Top Performing Hostels'),
          const SizedBox(height: 12),
          _TopList(
            entries: (current.revenueByHostel.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(5)
                .toList(),
            counts: current.bookingsByHostel,
            icon: Icons.apartment_rounded,
            accent: _kGreenAccent,
          ),
          SizedBox(height: mobile ? 20 : 28),
          _SectionHead(
              icon: Icons.groups_rounded, title: 'Landlord Leaderboard'),
          const SizedBox(height: 12),
          _LandlordLeaderboard(
            revenueByLandlord: current.revenueByLandlord,
            bookingsByLandlord: current.bookingsByLandlord,
            landlordDocs: bundle.landlords,
          ),
          SizedBox(height: mobile ? 20 : 28),
          _SectionHead(
              icon: Icons.local_fire_department_rounded,
              title: 'Occupancy by Hostel'),
          const SizedBox(height: 12),
          _OccupancyList(occByHostel: occByHostel),
          SizedBox(height: mobile ? 20 : 28),
          _ForecastCard(current: current.revenue, forecast: forecastNext),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ─────────────────────────────────────────────────────────────────────────────
// ATTENTION NEEDED — live alerts / anomaly panel
// ─────────────────────────────────────────────────────────────────────────────

class _Alert {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _Alert({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
}

class _AlertsPanel extends StatelessWidget {
  final List<_Alert> alerts;
  const _AlertsPanel({required this.alerts});

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(mobile ? 12 : 16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
        boxShadow: [
          BoxShadow(
              color: _kRed.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: _kRed, size: 16),
            ),
            const SizedBox(width: 10),
            Text('Attention Needed · ${alerts.length}',
                style: const TextStyle(
                    color: _kTextDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          ...alerts.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: a.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(a.icon, size: 13, color: a.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _kTextDark)),
                          const SizedBox(height: 2),
                          Text(a.subtitle,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _kTextLight,
                                  height: 1.3)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMART INSIGHTS
// ─────────────────────────────────────────────────────────────────────────────

class _SmartInsights extends StatelessWidget {
  final _Stats current;
  final _Stats? previous;
  final double occupancyRate;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> landlords;

  const _SmartInsights({
    required this.current,
    required this.previous,
    required this.occupancyRate,
    required this.landlords,
  });

  List<String> _build() {
    final insights = <String>[];

    if (previous != null) {
      final change = _pctChange(current.revenue, previous!.revenue);
      if (change.abs() >= 1) {
        insights.add(change >= 0
            ? 'Revenue is up ${change.toStringAsFixed(1)}% versus the previous period.'
            : 'Revenue is down ${change.abs().toStringAsFixed(1)}% versus the previous period — worth a closer look.');
      }
    }

    if (current.revenueByHostel.isNotEmpty) {
      final top = current.revenueByHostel.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      insights.add(
          '${top.key} is your top-earning hostel this period (GHS ${_fmt.format(top.value)}).');
    }

    if (current.totalBookings > 0) {
      insights.add(
          '${current.confirmRate.toStringAsFixed(0)}% of bookings this period were confirmed.');
    }

    insights.add(occupancyRate >= 75
        ? 'Overall occupancy is strong at ${occupancyRate.toStringAsFixed(0)}%.'
        : occupancyRate >= 40
            ? 'Overall occupancy is moderate at ${occupancyRate.toStringAsFixed(0)}% — there is room to fill more slots.'
            : 'Overall occupancy is low at ${occupancyRate.toStringAsFixed(0)}%. Consider promoting under-booked hostels.');

    if (current.revenueByMethod.isNotEmpty) {
      final top = current.revenueByMethod.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      insights.add('${top.key} is the most-used payment method this period.');
    }

    return insights;
  }

  @override
  Widget build(BuildContext context) {
    final insights = _build();
    if (insights.isEmpty) return const SizedBox.shrink();
    final mobile = _isMobile(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(mobile ? 14 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kGreen, _kGreenAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _kGreen.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Smart Insights',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          ...insights.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.circle, size: 5, color: Colors.white70),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              height: 1.4)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HEAD
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHead extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHead({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: _kGreenAccent),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: _kTextDark)),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: _kBorder, height: 1)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI GRID + ANIMATED CARD
// ─────────────────────────────────────────────────────────────────────────────

class _Kpi {
  final IconData icon;
  final String label, value;
  final Color color;
  final double? delta; // percentage-point or percent change; null = no trend
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.delta,
  });
}

class _KpiGrid extends StatelessWidget {
  final bool mobile, tablet;
  final List<_Kpi> items;
  const _KpiGrid(
      {required this.mobile, required this.tablet, required this.items});

  @override
  Widget build(BuildContext context) {
    final cols = mobile ? 2 : (tablet ? 3 : 4);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: mobile ? 1.35 : 1.55,
      ),
      itemBuilder: (_, i) => _KpiCard(item: items[i]),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final _Kpi item;
  const _KpiCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final positive = (item.delta ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, size: 15, color: item.color),
            ),
            const Spacer(),
            if (item.delta != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (positive ? _kGreenAccent : _kRed).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      positive
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 10,
                      color: positive ? _kGreenAccent : _kRed),
                  const SizedBox(width: 2),
                  Text('${item.delta!.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: positive ? _kGreenAccent : _kRed)),
                ]),
              ),
          ]),
          const SizedBox(height: 8),
          _CountUpText(value: item.value),
          const SizedBox(height: 2),
          Text(item.label,
              style: const TextStyle(fontSize: 10.5, color: _kTextLight),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Lightweight "count up" effect purely on rebuild — animates opacity/scale
/// so new KPI values feel alive without needing to parse/animate numerics
/// embedded inside formatted strings (currency, %, etc).
class _CountUpText extends StatelessWidget {
  final String value;
  const _CountUpText({required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
          scale: scale, alignment: Alignment.centerLeft, child: child),
      child: Text(
        value,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: _kTextDark),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRANULARITY TOGGLE
// ─────────────────────────────────────────────────────────────────────────────

class _GranularityToggle extends StatelessWidget {
  final _Granularity value;
  final ValueChanged<_Granularity> onChanged;
  const _GranularityToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kSurfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _Granularity.values.map((g) {
          final selected = g == value;
          return GestureDetector(
            onTap: () => onChanged(g),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _kGreenAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                g.name[0].toUpperCase() + g.name.substring(1),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : _kTextLight),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TREND CHART (hand-drawn bars)
// ─────────────────────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final Map<String, double> data;
  const _TrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    if (data.isEmpty) {
      return _EmptyBox(message: 'No revenue recorded for this period yet');
    }
    final entries = data.entries.toList();
    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final showLabels = entries.length <= 20;

    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: mobile ? 130 : 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: entries.map((e) {
                final frac = maxVal == 0 ? 0.0 : e.value / maxVal;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: 'GHS ${_fmt.format(e.value)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            height: (mobile ? 100 : 140) * frac + 3,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  _kGreenAccent,
                                  _kGreenAccent.withOpacity(0.55),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (showLabels) ...[
            const SizedBox(height: 8),
            Row(
              children: entries
                  .map((e) => Expanded(
                        child: Text(
                          e.key,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 8.5, color: _kTextMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOOKING STATUS — hand-drawn donut
// ─────────────────────────────────────────────────────────────────────────────

class _BookingStatusCard extends StatelessWidget {
  final _Stats stats;
  const _BookingStatusCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.totalBookings;
    final segments = <(String, int, Color)>[
      ('Confirmed', stats.confirmedBookings, _kGreenAccent),
      ('Pending', stats.pendingBookings, _kOrange),
      ('Declined', stats.declinedBookings, _kRed),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Booking Status',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark)),
          const SizedBox(height: 14),
          if (total == 0)
            const _EmptyBox(message: 'No bookings in this period')
          else
            Row(children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CustomPaint(
                  painter: _DonutPainter(segments: segments, total: total),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$total',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _kTextDark)),
                        const Text('total',
                            style: TextStyle(fontSize: 10, color: _kTextMuted)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: segments.map((s) {
                    final pct = total == 0 ? 0 : (s.$2 / total * 100);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                              color: s.$3, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(s.$1,
                                style: const TextStyle(
                                    fontSize: 12, color: _kTextMid))),
                        Text('${s.$2}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _kTextDark)),
                        const SizedBox(width: 6),
                        Text('(${pct.toStringAsFixed(0)}%)',
                            style: const TextStyle(
                                fontSize: 10, color: _kTextMuted)),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<(String, int, Color)> segments;
  final int total;
  _DonutPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const strokeWidth = 14.0;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final bg = Paint()
      ..color = _kBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bg);

    double startAngle = -math.pi / 2;
    for (final seg in segments) {
      if (seg.$2 == 0 || total == 0) continue;
      final sweep = (seg.$2 / total) * 2 * math.pi;
      final paint = Paint()
        ..color = seg.$3
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.total != total;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT METHOD BREAKDOWN
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentMethodCard extends StatelessWidget {
  final _Stats stats;
  const _PaymentMethodCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final entries = stats.revenueByMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (a, b) => a + b.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Methods',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark)),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            const _EmptyBox(message: 'No verified payments in this period')
          else
            ...entries.map((e) {
              final frac = total == 0 ? 0.0 : e.value / total;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(e.key,
                              style: const TextStyle(
                                  fontSize: 12, color: _kTextMid))),
                      Text('GHS ${_fmt.format(e.value)}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _kTextDark)),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 7,
                        backgroundColor: _kBorder,
                        valueColor: const AlwaysStoppedAnimation(_kGreenAccent),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP HOSTELS LIST
// ─────────────────────────────────────────────────────────────────────────────

class _TopList extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final Map<String, int> counts;
  final IconData icon;
  final Color accent;
  const _TopList(
      {required this.entries,
      required this.counts,
      required this.icon,
      required this.accent});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyBox(message: 'No data for this period');
    }
    final maxVal = entries.first.value;
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: entries.asMap().entries.map((e) {
          final rank = e.key + 1;
          final entry = e.value;
          final frac = maxVal == 0 ? 0.0 : entry.value / maxVal;
          final isLast = rank == entries.length;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(
                      bottom: BorderSide(color: _kBorder, width: 0.6)),
            ),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank == 1 ? const Color(0xFFFEF3C7) : _kSurfaceAlt,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: rank == 1 ? const Color(0xFFF59E0B) : _kBorder),
                ),
                child: Text('$rank',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color:
                            rank == 1 ? const Color(0xFF92400E) : _kTextMid)),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _kTextDark),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 5,
                        backgroundColor: _kBorder,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('GHS ${_fmt.format(entry.value)}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: _kTextDark)),
                  Text('${counts[entry.key] ?? 0} bookings',
                      style: const TextStyle(fontSize: 10, color: _kTextMuted)),
                ],
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDLORD LEADERBOARD
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordLeaderboard extends StatelessWidget {
  final Map<String, double> revenueByLandlord;
  final Map<String, int> bookingsByLandlord;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> landlordDocs;

  const _LandlordLeaderboard({
    required this.revenueByLandlord,
    required this.bookingsByLandlord,
    required this.landlordDocs,
  });

  @override
  Widget build(BuildContext context) {
    final nameOf = {
      for (final d in landlordDocs)
        d.id: (d.data()['full_name'] ?? '—').toString()
    };
    final subaccountOf = {
      for (final d in landlordDocs)
        d.id: (d.data()['paystack_subaccount']?.toString().isNotEmpty == true)
    };

    final sorted = revenueByLandlord.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();

    if (top.isEmpty) {
      return const _EmptyBox(message: 'No landlord activity in this period');
    }

    final mobile = _isMobile(context);
    return LayoutBuilder(builder: (context, c) {
      final cols = mobile ? 1 : (c.maxWidth < 900 ? 2 : 3);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: top.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: mobile ? 2.6 : 2.2,
        ),
        itemBuilder: (_, i) {
          final e = top[i];
          final name = nameOf[e.key] ?? 'Unknown Landlord';
          final hasPayout = subaccountOf[e.key] ?? false;
          final bookings = bookingsByLandlord[e.key] ?? 0;
          final initials = name.trim().isNotEmpty
              ? name
                  .trim()
                  .split(' ')
                  .take(2)
                  .map((w) => w[0])
                  .join()
                  .toUpperCase()
              : '?';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorder),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kGreenAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(initials,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _kGreenAccent)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _kTextDark),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('GHS ${_fmt.format(e.value)} · $bookings bookings',
                        style:
                            const TextStyle(fontSize: 10.5, color: _kTextLight),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(
                          hasPayout
                              ? Icons.bolt_rounded
                              : Icons.pending_actions_rounded,
                          size: 10,
                          color: hasPayout ? _kGreenAccent : _kOrange),
                      const SizedBox(width: 3),
                      Text(hasPayout ? 'Auto-payout' : 'Manual payout',
                          style: TextStyle(
                              fontSize: 9,
                              color: hasPayout ? _kGreenAccent : _kOrange)),
                    ]),
                  ],
                ),
              ),
            ]),
          );
        },
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OCCUPANCY LIST
// ─────────────────────────────────────────────────────────────────────────────

class _OccupancyList extends StatelessWidget {
  final Map<String, ({int booked, int capacity})> occByHostel;
  const _OccupancyList({required this.occByHostel});

  @override
  Widget build(BuildContext context) {
    final entries = occByHostel.entries
        .where((e) => e.value.capacity > 0)
        .toList()
      ..sort((a, b) => (b.value.booked / b.value.capacity)
          .compareTo(a.value.booked / a.value.capacity));

    if (entries.isEmpty) {
      return const _EmptyBox(message: 'No room data available');
    }

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: entries.take(8).map((e) {
          final rate = e.value.booked / e.value.capacity;
          final color = rate >= 0.85
              ? _kRed
              : rate >= 0.5
                  ? _kOrange
                  : _kGreenAccent;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              SizedBox(
                width: 130,
                child: Text(e.key,
                    style: const TextStyle(fontSize: 12, color: _kTextMid),
                    overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rate.clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: _kBorder,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 78,
                child: Text(
                  '${e.value.booked}/${e.value.capacity} (${(rate * 100).toStringAsFixed(0)}%)',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORECAST CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ForecastCard extends StatelessWidget {
  final double current;
  final double forecast;
  const _ForecastCard({required this.current, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final growth = current == 0 ? 0.0 : ((forecast - current) / current) * 100;
    return Container(
      padding: EdgeInsets.all(mobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.trending_up_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Projected Next Period Revenue',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('GHS ${_fmt.format(forecast)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}% vs current period · trend-based estimate',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY BOX
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyBox extends StatelessWidget {
  final String message;
  const _EmptyBox({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(message,
              style: const TextStyle(fontSize: 12, color: _kTextMuted)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCHEDULE REPORTS DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleReportsDialog extends StatefulWidget {
  const _ScheduleReportsDialog();
  @override
  State<_ScheduleReportsDialog> createState() => _ScheduleReportsDialogState();
}

class _ScheduleReportsDialogState extends State<_ScheduleReportsDialog> {
  final _emailCtrl = TextEditingController();
  String _frequency = 'weekly';
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('reports')
          .get();
      final d = doc.data();
      if (d != null) {
        _emailCtrl.text = d['email']?.toString() ?? '';
        _frequency = d['frequency']?.toString() ?? 'weekly';
        _enabled = d['enabled'] == true;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('reports')
          .set({
        'enabled': _enabled,
        'email': _emailCtrl.text.trim(),
        'frequency': _frequency,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: _kRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(
                    child: CircularProgressIndicator(color: _kGreenAccent)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: _kPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.schedule_send_rounded,
                          color: _kPurple, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Scheduled Reports',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Text(
                        'Automatically email a PDF analytics summary.',
                        style: TextStyle(fontSize: 12, color: _kTextLight),
                      ),
                    ),
                    Switch(
                      value: _enabled,
                      activeColor: _kGreenAccent,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Recipient email',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['daily', 'weekly', 'monthly'].map((f) {
                      final selected = f == _frequency;
                      return ChoiceChip(
                        label: Text(f[0].toUpperCase() + f.substring(1)),
                        selected: selected,
                        selectedColor: _kGreenAccent.withOpacity(0.15),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected ? _kGreenAccent : _kTextMid,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setState(() => _frequency = f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded,
                          size: 14, color: _kOrange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This saves your preference. Actually sending the email requires a scheduled backend job reading this setting.',
                          style: TextStyle(fontSize: 10.5, color: _kOrange),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreenAccent),
                        child: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save',
                                style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ]),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REPORT CENTER — pick a type, a date range, a format, generate
// ─────────────────────────────────────────────────────────────────────────────

enum _ReportType {
  fullSystem,
  bookings,
  hostels,
  rooms,
  landlords,
  students,
  payments,
}

extension _ReportTypeX on _ReportType {
  String get label => switch (this) {
        _ReportType.fullSystem => 'Full System',
        _ReportType.bookings => 'Bookings',
        _ReportType.hostels => 'Hostels',
        _ReportType.rooms => 'Rooms',
        _ReportType.landlords => 'Landlords',
        _ReportType.students => 'Students',
        _ReportType.payments => 'Payments',
      };

  IconData get icon => switch (this) {
        _ReportType.fullSystem => Icons.dashboard_customize_rounded,
        _ReportType.bookings => Icons.receipt_long_rounded,
        _ReportType.hostels => Icons.apartment_rounded,
        _ReportType.rooms => Icons.meeting_room_rounded,
        _ReportType.landlords => Icons.groups_rounded,
        _ReportType.students => Icons.school_rounded,
        _ReportType.payments => Icons.payments_rounded,
      };

  /// Whether a date range filter is meaningful for this report — bookings
  /// and payments are dated events; hostels/rooms/landlords/students are
  /// point-in-time entity snapshots, so a date range doesn't apply to them.
  bool get supportsDateRange =>
      this == _ReportType.bookings ||
      this == _ReportType.payments ||
      this == _ReportType.fullSystem;
}

class _ReportCenterDialog extends StatefulWidget {
  final Future<_Bundle> Function() fetchFullBundle;
  const _ReportCenterDialog({required this.fetchFullBundle});

  @override
  State<_ReportCenterDialog> createState() => _ReportCenterDialogState();
}

class _ReportCenterDialogState extends State<_ReportCenterDialog> {
  _ReportType _type = _ReportType.fullSystem;
  DateTimeRange? _range;
  bool _asPdf = true;
  bool _generating = false;

  bool _loadingFilters = true;
  _Bundle? _cachedBundle;
  List<String> _hostelOptions = [];
  List<String> _statusOptions = [];
  String? _hostelFilter;
  final Set<String> _statusFilter = {};

  @override
  void initState() {
    super.initState();
    _loadFilterOptions();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final bundle = await widget.fetchFullBundle();
      final hostels = bundle.hostels
          .map((h) => (h.data()['hostel_name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      final statuses = bundle.bookings
          .map((b) => (b.data()['status'] ?? 'pending').toString())
          .toSet()
          .toList()
        ..sort();
      if (mounted) {
        setState(() {
          _cachedBundle = bundle;
          _hostelOptions = hostels;
          _statusOptions = statuses;
          _loadingFilters = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFilters = false);
    }
  }

  /// A given fetch is a full, live snapshot — reuse it if it's fresh enough
  /// (under 2 minutes old) rather than re-querying every collection again
  /// right after the filter picker already did so.
  Future<_Bundle> _bundleForGenerate() async {
    if (_cachedBundle != null) return _cachedBundle!;
    return widget.fetchFullBundle();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final bundle = await _bundleForGenerate();
      final effectiveRange = _type.supportsDateRange ? _range : null;
      final effectiveStatus =
          _type == _ReportType.bookings || _type == _ReportType.fullSystem
              ? _statusFilter
              : const <String>{};

      if (_asPdf) {
        final bytes = await _buildTypedPdfReport(_type, bundle, effectiveRange,
            hostelFilter: _hostelFilter, statusFilter: effectiveStatus);
        final fname =
            'roomzyfind_${_type.name}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
        if (kIsWeb) {
          await Printing.sharePdf(bytes: bytes, filename: fname);
        } else {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/$fname');
          await file.writeAsBytes(bytes);
          await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/pdf')],
            subject: 'RoomzyFind ${_type.label} Report',
          );
        }
      } else {
        final csv = _buildTypedCsv(_type, bundle, effectiveRange,
            hostelFilter: _hostelFilter, statusFilter: effectiveStatus);
        if (kIsWeb) {
          await Clipboard.setData(ClipboardData(text: csv));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('CSV copied to clipboard — paste into Excel/Sheets'),
              backgroundColor: _kGreenAccent,
              behavior: SnackBarBehavior.floating,
            ));
          }
        } else {
          final dir = await getTemporaryDirectory();
          final file = File(
              '${dir.path}/roomzyfind_${_type.name}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv');
          await file.writeAsString(csv);
          await Share.shareXFiles(
            [XFile(file.path, mimeType: 'text/csv')],
            subject: 'RoomzyFind ${_type.label} Export',
          );
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Report generation failed: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _kBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.dashboard_customize_rounded,
                      color: _kBlue, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Report Center',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ]),
              const SizedBox(height: 4),
              const Text(
                'Pick a report type, an optional date range, and a format.',
                style: TextStyle(fontSize: 12, color: _kTextLight),
              ),
              const SizedBox(height: 16),
              const Text('Report type',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kTextMid)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ReportType.values.map((t) {
                  final selected = t == _type;
                  return GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? _kGreenAccent.withOpacity(0.12)
                            : _kSurfaceAlt,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected ? _kGreenAccent : _kBorder),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(t.icon,
                            size: 14,
                            color: selected ? _kGreenAccent : _kTextLight),
                        const SizedBox(width: 6),
                        Text(t.label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: selected ? _kGreenAccent : _kTextMid)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Date range',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kTextMid)),
              const SizedBox(height: 8),
              Opacity(
                opacity: _type.supportsDateRange ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !_type.supportsDateRange,
                  child: InkWell(
                    onTap: _pickRange,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: _kSurfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_month_rounded,
                            size: 15, color: _kTextLight),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _range == null
                                ? 'All time'
                                : '${dateFmt.format(_range!.start)} — ${dateFmt.format(_range!.end)}',
                            style: const TextStyle(
                                fontSize: 12.5, color: _kTextDark),
                          ),
                        ),
                        if (_range != null)
                          GestureDetector(
                            onTap: () => setState(() => _range = null),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: _kTextMuted),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
              if (!_type.supportsDateRange)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Date range applies to bookings, payments, and full-system reports only — this report type is a live snapshot.',
                    style: TextStyle(fontSize: 10.5, color: _kTextMuted),
                  ),
                ),
              const SizedBox(height: 16),
              const Text('Filters (optional)',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kTextMid)),
              const SizedBox(height: 8),
              if (_loadingFilters)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kGreenAccent),
                  ),
                )
              else ...[
                DropdownButtonFormField<String?>(
                  value: _hostelFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Hostel',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All hostels')),
                    ..._hostelOptions.map((h) =>
                        DropdownMenuItem<String?>(value: h, child: Text(h))),
                  ],
                  onChanged: (v) => setState(() => _hostelFilter = v),
                ),
                if (_type == _ReportType.bookings ||
                    _type == _ReportType.fullSystem) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _statusOptions.map((s) {
                      final selected = _statusFilter.contains(s);
                      return FilterChip(
                        label: Text(s, style: const TextStyle(fontSize: 11.5)),
                        selected: selected,
                        selectedColor: _kGreenAccent.withOpacity(0.15),
                        checkmarkColor: _kGreenAccent,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _statusFilter.add(s);
                          } else {
                            _statusFilter.remove(s);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  if (_statusOptions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _statusFilter.isEmpty
                            ? 'No status selected = include all statuses'
                            : 'Only ${_statusFilter.join(', ')} bookings will be included',
                        style:
                            const TextStyle(fontSize: 10, color: _kTextMuted),
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 16),
              const Text('Format',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kTextMid)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _FormatChip(
                    label: 'PDF',
                    icon: Icons.picture_as_pdf_rounded,
                    selected: _asPdf,
                    onTap: () => setState(() => _asPdf = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FormatChip(
                    label: 'CSV',
                    icon: Icons.table_chart_rounded,
                    selected: !_asPdf,
                    onTap: () => setState(() => _asPdf = false),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _generating ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Generate ${_type.label} report',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _FormatChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _kGreenAccent.withOpacity(0.12) : _kSurfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _kGreenAccent : _kBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? _kGreenAccent : _kTextLight),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? _kGreenAccent : _kTextMid)),
          ],
        ),
      ),
    );
  }
}

// ── Filtering helpers ───────────────────────────────────────────────────────

// ── Filtering helpers ───────────────────────────────────────────────────────

List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterByDate(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String field,
  DateTimeRange? range,
) {
  if (range == null) return docs;
  return docs.where((doc) {
    final ts = doc.data()[field];
    final dt = ts is Timestamp ? ts.toDate() : null;
    if (dt == null) return false;
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }).toList();
}

List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyBookingFilters(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
  String? hostelFilter,
  Set<String> statusFilter = const {},
}) {
  return docs.where((doc) {
    final d = doc.data();
    if (hostelFilter != null &&
        (d['hostel_name'] ?? '').toString() != hostelFilter) {
      return false;
    }
    if (statusFilter.isNotEmpty &&
        !statusFilter.contains((d['status'] ?? 'pending').toString())) {
      return false;
    }
    return true;
  }).toList();
}
// ── Typed CSV builder ───────────────────────────────────────────────────────

String _buildTypedCsv(
  _ReportType type,
  _Bundle bundle,
  DateTimeRange? range, {
  String? hostelFilter,
  Set<String> statusFilter = const {},
}) {
  final buf = StringBuffer();

  void writeBookingsCsv() {
    final rows = _applyBookingFilters(
      _filterByDate(bundle.bookings, 'booked_at', range),
      hostelFilter: hostelFilter,
      statusFilter: statusFilter,
    );
    buf.writeln(
        'Guest,Hostel,Landlord ID,School,Status,Payment Status,Amount,Amount Paid,Balance Due,Commission,Booked At');

    double totalAmount = 0, totalPaid = 0, totalBalance = 0;
    for (final doc in rows) {
      final d = doc.data();
      final ts = d['booked_at'];
      final dateStr = ts is Timestamp
          ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate())
          : '';
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final paid = (d['amount_paid'] as num?)?.toDouble() ?? 0;
      final balance = (amount - paid) < 0 ? 0.0 : (amount - paid);
      totalAmount += amount;
      totalPaid += paid;
      totalBalance += balance;

      buf.writeln([
        d['name'] ?? '',
        d['hostel_name'] ?? '',
        d['landlord_id'] ?? '',
        d['school'] ?? '',
        d['status'] ?? '',
        d['payment_status'] ?? '',
        amount.toString(),
        paid.toString(),
        balance.toString(),
        (d['commission_collected'] ?? 0).toString(),
        dateStr,
      ].map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','));
    }
    buf.writeln([
      'TOTAL',
      '',
      '',
      '',
      '',
      '',
      totalAmount.toString(),
      totalPaid.toString(),
      totalBalance.toString(),
      '',
      '',
    ].map((v) => '"$v"').join(','));
  }

  void writePaymentsCsv() {
    var rows = _filterByDate(bundle.payments, 'paid_at', range);
    if (hostelFilter != null) {
      rows = rows
          .where(
              (d) => (d.data()['hostel_name'] ?? '').toString() == hostelFilter)
          .toList();
    }
    buf.writeln(
        'Hostel,Landlord ID,Amount,Commission Taken,Landlord Received,Method,Provider,Paid At');
    double total = 0;
    for (final doc in rows) {
      final d = doc.data();
      final ts = d['paid_at'];
      final dateStr = ts is Timestamp
          ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate())
          : '';
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      total += amount;
      buf.writeln([
        d['hostel_name'] ?? '',
        d['landlord_id'] ?? '',
        amount.toString(),
        (d['commission_taken'] ?? 0).toString(),
        (d['landlord_received'] ?? 0).toString(),
        d['method'] ?? '',
        d['provider'] ?? '',
        dateStr,
      ].map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','));
    }
    buf.writeln(['TOTAL', '', total.toString(), '', '', '', '', '']
        .map((v) => '"$v"')
        .join(','));
  }

  switch (type) {
    case _ReportType.bookings:
      writeBookingsCsv();
      break;
    case _ReportType.payments:
      writePaymentsCsv();
      break;
    case _ReportType.fullSystem:
      writeBookingsCsv();
      buf.writeln();
      writePaymentsCsv();
      break;
    // hostels / rooms / landlords / students cases stay exactly as they are
    default:
      break;
  }

  return buf.toString();
}

// ── Typed PDF builder ───────────────────────────────────────────────────────

Future<Uint8List> _buildTypedPdfReport(
  _ReportType type,
  _Bundle bundle,
  DateTimeRange? range, {
  String? hostelFilter,
  Set<String> statusFilter = const {},
}) async {
  final doc = pw.Document();
  final green = PdfColor.fromInt(0xFF1B4332);
  final greenAccent = PdfColor.fromInt(0xFF2D6A4F);
  final grey = PdfColor.fromInt(0xFF6B7280);
  final headerFill = PdfColor.fromInt(0xFFF0FAF3);
  final borderColor = PdfColor.fromInt(0xFFE5E7EB);
  final dateFmt = DateFormat('d MMM yyyy');

  final rangeLabel = range == null
      ? 'All time'
      : '${dateFmt.format(range.start)} — ${dateFmt.format(range.end)}';

  pw.Widget tableFrom(List<String> headers, List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: borderColor),
      columnWidths: {
        for (var i = 0; i < headers.length; i++) i: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerFill),
          children: headers
              .map((h) => _pdfCell(h, bold: true))
              .toList(growable: false),
        ),
        ...rows.map(
            (r) => pw.TableRow(children: r.map((c) => _pdfCell(c)).toList())),
      ],
    );
  }

  final sections = <pw.Widget>[];

  void addSectionTitle(String title) {
    sections.add(pw.SizedBox(height: 16));
    sections.add(pw.Text(title,
        style: pw.TextStyle(
            fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)));
    sections.add(pw.SizedBox(height: 8));
  }

  if (type == _ReportType.bookings || type == _ReportType.fullSystem) {
    final rows = _applyBookingFilters(
      _filterByDate(bundle.bookings, 'booked_at', range),
      hostelFilter: hostelFilter,
      statusFilter: statusFilter,
    );
    final totalAmount = rows.fold<double>(
        0, (a, d) => a + ((d.data()['amount'] as num?)?.toDouble() ?? 0));
    final totalPaid = rows.fold<double>(
        0, (a, d) => a + ((d.data()['amount_paid'] as num?)?.toDouble() ?? 0));
    addSectionTitle(
        'Bookings (${rows.length}) · GHS ${_fmt.format(totalPaid)} collected of GHS ${_fmt.format(totalAmount)}');
    if (rows.isEmpty) {
      sections.add(pw.Text('No bookings in this range.',
          style: pw.TextStyle(fontSize: 10, color: grey)));
    } else {
      sections.add(tableFrom(
        [
          'Guest',
          'Hostel',
          'Status',
          'Payment',
          'Amount',
          'Paid',
          'Balance',
          'Date'
        ],
        rows.take(200).map((doc) {
          final d = doc.data();
          final ts = d['booked_at'];
          final dateStr =
              ts is Timestamp ? DateFormat('d MMM yy').format(ts.toDate()) : '';
          final amount = (d['amount'] as num?)?.toDouble() ?? 0;
          final paid = (d['amount_paid'] as num?)?.toDouble() ?? 0;
          final balance = (amount - paid) < 0 ? 0.0 : (amount - paid);
          return [
            (d['name'] ?? '—').toString(),
            (d['hostel_name'] ?? '—').toString(),
            (d['status'] ?? '—').toString(),
            (d['payment_status'] ?? '—').toString(),
            'GHS ${_fmt.format(amount)}',
            'GHS ${_fmt.format(paid)}',
            'GHS ${_fmt.format(balance)}',
            dateStr,
          ];
        }).toList(),
      ));
      if (rows.length > 200) {
        sections.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('Showing first 200 of ${rows.length} rows.',
              style: pw.TextStyle(fontSize: 8, color: grey)),
        ));
      }
    }
  }

  if (type == _ReportType.payments || type == _ReportType.fullSystem) {
    var rows = _filterByDate(bundle.payments, 'paid_at', range);
    if (hostelFilter != null) {
      rows = rows
          .where(
              (d) => (d.data()['hostel_name'] ?? '').toString() == hostelFilter)
          .toList();
    }
    final totalAmount = rows.fold<double>(
        0, (a, d) => a + ((d.data()['amount'] as num?)?.toDouble() ?? 0));
    addSectionTitle(
        'Payments (${rows.length}) · Total GHS ${_fmt.format(totalAmount)}');
    if (rows.isEmpty) {
      sections.add(pw.Text('No payments in this range.',
          style: pw.TextStyle(fontSize: 10, color: grey)));
    } else {
      sections.add(tableFrom(
        ['Hostel', 'Amount', 'Commission', 'Method', 'Date'],
        rows.take(200).map((doc) {
          final d = doc.data();
          final ts = d['paid_at'];
          final dateStr =
              ts is Timestamp ? DateFormat('d MMM yy').format(ts.toDate()) : '';
          return [
            (d['hostel_name'] ?? '—').toString(),
            'GHS ${_fmt.format((d['amount'] as num?)?.toDouble() ?? 0)}',
            'GHS ${_fmt.format((d['commission_taken'] as num?)?.toDouble() ?? 0)}',
            (d['method'] ?? '—').toString(),
            dateStr,
          ];
        }).toList(),
      ));
    }
  }

  if (type == _ReportType.hostels || type == _ReportType.fullSystem) {
    final roomsByHostel = <String, List<Map<String, dynamic>>>{};
    for (final r in bundle.rooms) {
      final hid = (r.data()['hostel_id'] ?? '').toString();
      roomsByHostel.putIfAbsent(hid, () => []).add(r.data());
    }
    addSectionTitle('Hostels (${bundle.hostels.length})');
    sections.add(tableFrom(
      ['Hostel', 'Rooms', 'Capacity', 'Booked', 'Occupancy'],
      bundle.hostels.map((h) {
        final d = h.data();
        final rooms = roomsByHostel[h.id] ?? [];
        final cap = rooms.fold<int>(
            0, (a, r) => a + ((r['capacity'] as num?)?.toInt() ?? 0));
        final booked = rooms.fold<int>(
            0, (a, r) => a + ((r['booked'] as num?)?.toInt() ?? 0));
        final rate = cap == 0 ? 0.0 : booked / cap * 100;
        return [
          (d['hostel_name'] ?? '—').toString(),
          '${rooms.length}',
          '$cap',
          '$booked',
          '${rate.toStringAsFixed(0)}%',
        ];
      }).toList(),
    ));
  }

  if (type == _ReportType.rooms || type == _ReportType.fullSystem) {
    final hostelNameById = {
      for (final h in bundle.hostels)
        h.id: (h.data()['hostel_name'] ?? 'Unknown').toString()
    };
    addSectionTitle('Rooms (${bundle.rooms.length})');
    sections.add(tableFrom(
      ['Room ID', 'Hostel', 'Capacity', 'Booked', 'Available'],
      bundle.rooms.take(200).map((doc) {
        final d = doc.data();
        final cap = (d['capacity'] as num?)?.toInt() ?? 0;
        final booked = (d['booked'] as num?)?.toInt() ?? 0;
        final hostel =
            hostelNameById[(d['hostel_id'] ?? '').toString()] ?? 'Unknown';
        return [doc.id, hostel, '$cap', '$booked', '${cap - booked}'];
      }).toList(),
    ));
  }

  if (type == _ReportType.landlords || type == _ReportType.fullSystem) {
    final tmpStats = _computeStats(
      bookings: bundle.bookings,
      payments: bundle.payments,
      from: null,
      to: null,
      granularity: _Granularity.month,
    );
    addSectionTitle('Landlords (${bundle.landlords.length})');
    sections.add(tableFrom(
      ['Landlord', 'Auto-Payout', 'Bookings', 'Revenue'],
      bundle.landlords.map((doc) {
        final d = doc.data();
        final hasSub =
            (d['paystack_subaccount']?.toString().isNotEmpty ?? false);
        return [
          (d['full_name'] ?? '—').toString(),
          hasSub ? 'Yes' : 'No',
          '${tmpStats.bookingsByLandlord[doc.id] ?? 0}',
          'GHS ${_fmt.format(tmpStats.revenueByLandlord[doc.id] ?? 0)}',
        ];
      }).toList(),
    ));
  }

  if (type == _ReportType.students || type == _ReportType.fullSystem) {
    addSectionTitle('Students (${bundle.students.length})');
    sections.add(tableFrom(
      ['Name', 'Email', 'School'],
      bundle.students.take(200).map((doc) {
        final d = doc.data();
        return [
          (d['full_name'] ?? d['name'] ?? '—').toString(),
          (d['email'] ?? '—').toString(),
          (d['school'] ?? '—').toString(),
        ];
      }).toList(),
    ));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('RoomzyFind — ${type.label} Report',
                  style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: green)),
              pw.Text(DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()),
                  style: pw.TextStyle(fontSize: 9, color: grey)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('Range: $rangeLabel',
              style: pw.TextStyle(fontSize: 10, color: grey)),
          pw.Divider(color: greenAccent, thickness: 1.2),
          pw.SizedBox(height: 4),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: grey)),
      ),
      build: (context) => sections,
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// LEGACY PDF REPORT BUILDER (quick export — current dashboard period)
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildPdfReport(
    _Bundle bundle, _Stats stats, _Period period) async {
  final doc = pw.Document();
  final green = PdfColor.fromInt(0xFF1B4332);
  final greenAccent = PdfColor.fromInt(0xFF2D6A4F);
  final grey = PdfColor.fromInt(0xFF6B7280);

  final topHostels = (stats.revenueByHostel.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(10)
      .toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('RoomzyFind — Analytics Report',
                  style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: green)),
              pw.Text(DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()),
                  style: pw.TextStyle(fontSize: 9, color: grey)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('Period: ${period.label}',
              style: pw.TextStyle(fontSize: 10, color: grey)),
          pw.Divider(color: greenAccent, thickness: 1.2),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: grey)),
      ),
      build: (context) => [
        pw.Text('Key Metrics',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE5E7EB)),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(1.4),
          },
          children: [
            _pdfRow('Revenue Collected', 'GHS ${_fmt.format(stats.revenue)}',
                greenAccent,
                header: true),
            _pdfRow('Platform Commission',
                'GHS ${_fmt.format(stats.commission)}', grey),
            _pdfRow('Landlord Payouts',
                'GHS ${_fmt.format(stats.landlordPayout)}', grey),
            _pdfRow('Total Bookings', '${stats.totalBookings}', grey),
            _pdfRow('Confirmed Bookings', '${stats.confirmedBookings}', grey),
            _pdfRow('Pending Bookings', '${stats.pendingBookings}', grey),
            _pdfRow('Declined Bookings', '${stats.declinedBookings}', grey),
            _pdfRow('Confirmation Rate',
                '${stats.confirmRate.toStringAsFixed(1)}%', grey),
            _pdfRow('Average Booking Value',
                'GHS ${_fmt.format(stats.avgBookingValue)}', grey),
            _pdfRow('Registered Students', '${bundle.students.length}', grey),
            _pdfRow('Active Landlords', '${bundle.landlords.length}', grey),
            _pdfRow('Total Hostels', '${bundle.hostels.length}', grey),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text('Top Performing Hostels',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)),
        pw.SizedBox(height: 8),
        if (topHostels.isEmpty)
          pw.Text('No hostel revenue recorded for this period.',
              style: pw.TextStyle(fontSize: 10, color: grey))
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE5E7EB)),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.4),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0FAF3)),
                children: [
                  _pdfCell('#', bold: true),
                  _pdfCell('Hostel', bold: true),
                  _pdfCell('Revenue', bold: true),
                  _pdfCell('Bookings', bold: true),
                ],
              ),
              ...topHostels.asMap().entries.map((e) => pw.TableRow(children: [
                    _pdfCell('${e.key + 1}'),
                    _pdfCell(e.value.key),
                    _pdfCell('GHS ${_fmt.format(e.value.value)}'),
                    _pdfCell('${stats.bookingsByHostel[e.value.key] ?? 0}'),
                  ])),
            ],
          ),
        pw.SizedBox(height: 20),
        pw.Text('Payment Method Breakdown',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)),
        pw.SizedBox(height: 8),
        if (stats.revenueByMethod.isEmpty)
          pw.Text('No verified payments recorded for this period.',
              style: pw.TextStyle(fontSize: 10, color: grey))
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE5E7EB)),
            children: [
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0FAF3)),
                children: [
                  _pdfCell('Method', bold: true),
                  _pdfCell('Amount', bold: true),
                ],
              ),
              ...stats.revenueByMethod.entries
                  .map((e) => pw.TableRow(children: [
                        _pdfCell(e.key),
                        _pdfCell('GHS ${_fmt.format(e.value)}'),
                      ])),
            ],
          ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Generated automatically by RoomzyFind Admin Analytics.',
          style: pw.TextStyle(fontSize: 8, color: grey),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.TableRow _pdfRow(String label, String value, PdfColor valueColor,
    {bool header = false}) {
  return pw.TableRow(
    decoration:
        header ? pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0FAF3)) : null,
    children: [
      _pdfCell(label, bold: header),
      pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(value,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: valueColor)),
      ),
    ],
  );
}

pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
