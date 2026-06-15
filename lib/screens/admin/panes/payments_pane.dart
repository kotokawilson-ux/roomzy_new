// lib/screens/admin/panes/payments_pane.dart
// ─────────────────────────────────────────────────────────────────────────────
// RoomzyFind — Admin Payments Pane (Advanced, Real-time, Responsive)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS & THEME
// ─────────────────────────────────────────────────────────────────────────────

const _bg = Color(0xFF0F1117);
const _surface = Color(0xFF1A1D27);
const _surfaceAlt = Color(0xFF20232F);
const _border = Color(0xFF2A2D3A);
const _accent = Color(0xFF6C63FF);
const _accentLow = Color(0x266C63FF);
const _success = Color(0xFF22C55E);
const _warning = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);
const _textPrimary = Color(0xFFECEDF2);
const _textSecondary = Color(0xFF8B8FA8);
const _textMuted = Color(0xFF555870);

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum PaymentStatus { all, pending, completed, failed, refunded }

enum PaymentMethod { all, mobileMoney, card, bankTransfer }

extension PaymentStatusLabel on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.all => 'All',
        PaymentStatus.pending => 'Pending',
        PaymentStatus.completed => 'Completed',
        PaymentStatus.failed => 'Failed',
        PaymentStatus.refunded => 'Refunded',
      };

  Color get color => switch (this) {
        PaymentStatus.all => _textSecondary,
        PaymentStatus.pending => _warning,
        PaymentStatus.completed => _success,
        PaymentStatus.failed => _danger,
        PaymentStatus.refunded => _accent,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

class PaymentRecord {
  final String id;
  final String tenantName;
  final String tenantEmail;
  final String hostelName;
  final String roomNumber;
  final double amount;
  final String currency;
  final PaymentStatus status;
  final String method;
  final String reference;
  final DateTime createdAt;
  final String? failureReason;

  const PaymentRecord({
    required this.id,
    required this.tenantName,
    required this.tenantEmail,
    required this.hostelName,
    required this.roomNumber,
    required this.amount,
    required this.currency,
    required this.status,
    required this.method,
    required this.reference,
    required this.createdAt,
    this.failureReason,
  });

  factory PaymentRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final raw = d['status'] as String? ?? 'pending';
    final status = PaymentStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => PaymentStatus.pending,
    );
    return PaymentRecord(
      id: doc.id,
      tenantName: d['tenantName'] as String? ?? 'Unknown',
      tenantEmail: d['tenantEmail'] as String? ?? '',
      hostelName: d['hostelName'] as String? ?? '—',
      roomNumber: d['roomNumber'] as String? ?? '—',
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'GHS',
      status: status,
      method: d['method'] as String? ?? 'Unknown',
      reference: d['reference'] as String? ?? doc.id,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      failureReason: d['failureReason'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PANE WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class PaymentsPane extends StatefulWidget {
  const PaymentsPane({super.key});

  @override
  State<PaymentsPane> createState() => _PaymentsPaneState();
}

class _PaymentsPaneState extends State<PaymentsPane>
    with TickerProviderStateMixin {
  // ── state ──
  PaymentStatus _statusFilter = PaymentStatus.all;
  PaymentMethod _methodFilter = PaymentMethod.all;
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  bool _loading = false;
  String? _selectedId;

  // ── animation ──
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── firestore ──
  final _db = FirebaseFirestore.instance;
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ─── query builder ───
  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> q =
        _db.collection('payments').orderBy('createdAt', descending: true);

    if (_statusFilter != PaymentStatus.all) {
      q = q.where('status', isEqualTo: _statusFilter.name);
    }
    if (_methodFilter != PaymentMethod.all) {
      q = q.where('method', isEqualTo: _methodFilter.name);
    }
    if (_dateRange != null) {
      q = q
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRange!.start))
          .where('createdAt',
              isLessThanOrEqualTo: Timestamp.fromDate(
                  _dateRange!.end.add(const Duration(days: 1))));
    }
    return q.limit(200);
  }

  List<PaymentRecord> _applySearch(List<PaymentRecord> records) {
    if (_searchQuery.isEmpty) return records;
    final q = _searchQuery.toLowerCase();
    return records
        .where(
          (r) =>
              r.tenantName.toLowerCase().contains(q) ||
              r.tenantEmail.toLowerCase().contains(q) ||
              r.reference.toLowerCase().contains(q) ||
              r.hostelName.toLowerCase().contains(q),
        )
        .toList();
  }

  // ─── refund action ───
  Future<void> _initiateRefund(PaymentRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _RefundDialog(record: record),
    );
    if (confirmed != true) return;
    try {
      await _db.collection('payments').doc(record.id).update({
        'status': 'refunded',
        'refundedAt': FieldValue.serverTimestamp(),
        'refundedBy': 'admin',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snack('Refund initiated for ${record.tenantName}', isError: false),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snack('Refund failed: $e', isError: true),
        );
      }
    }
  }

  SnackBar _snack(String msg, {required bool isError}) => SnackBar(
        backgroundColor: isError ? _danger : _success,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      );

  // ─── date picker ───
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: now,
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
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

  // ─── copy reference ───
  void _copyRef(String ref) {
    Clipboard.setData(ClipboardData(text: ref));
    ScaffoldMessenger.of(context).showSnackBar(
      _snack('Reference copied', isError: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final W = MediaQuery.of(context).size.width;
    final isNarrow = W < 700;
    final isCompact = W < 1100;

    return FadeTransition(
      opacity: _fadeAnim,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query.snapshots(),
        builder: (ctx, snap) {
          final records = snap.hasData
              ? snap.data!.docs.map(PaymentRecord.fromFirestore).toList()
              : <PaymentRecord>[];
          final filtered = _applySearch(records);
          final stats = _computeStats(records);

          return Container(
            color: _bg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(isNarrow: isNarrow),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isNarrow ? 16 : 28,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── stat cards ──
                        _StatRow(stats: stats, isNarrow: isNarrow),
                        const SizedBox(height: 24),

                        // ── filter bar ──
                        _FilterBar(
                          statusFilter: _statusFilter,
                          methodFilter: _methodFilter,
                          dateRange: _dateRange,
                          searchCtrl: _searchCtrl,
                          isNarrow: isNarrow,
                          onStatusChanged: (v) =>
                              setState(() => _statusFilter = v),
                          onMethodChanged: (v) =>
                              setState(() => _methodFilter = v),
                          onSearchChanged: (v) =>
                              setState(() => _searchQuery = v),
                          onPickDate: _pickDateRange,
                          onClearDate: () => setState(() => _dateRange = null),
                        ),
                        const SizedBox(height: 20),

                        // ── table or cards ──
                        snap.connectionState == ConnectionState.waiting
                            ? _shimmer()
                            : isCompact
                                ? _CardList(
                                    records: filtered,
                                    selectedId: _selectedId,
                                    onSelect: (id) =>
                                        setState(() => _selectedId = id),
                                    onCopyRef: _copyRef,
                                    onRefund: _initiateRefund,
                                  )
                                : _DataTable(
                                    records: filtered,
                                    selectedId: _selectedId,
                                    onSelect: (id) =>
                                        setState(() => _selectedId = id),
                                    onCopyRef: _copyRef,
                                    onRefund: _initiateRefund,
                                  ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
    double total = 0, completed = 0, pending = 0, failed = 0, refunded = 0;
    int cCount = 0, pCount = 0, fCount = 0, rCount = 0;
    for (final r in records) {
      total += r.amount;
      switch (r.status) {
        case PaymentStatus.completed:
          completed += r.amount;
          cCount++;
          break;
        case PaymentStatus.pending:
          pending += r.amount;
          pCount++;
          break;
        case PaymentStatus.failed:
          failed += r.amount;
          fCount++;
          break;
        case PaymentStatus.refunded:
          refunded += r.amount;
          rCount++;
          break;
        default:
          break;
      }
    }
    return _StatsData(
      total: total,
      totalCount: records.length,
      completed: completed,
      completedCount: cCount,
      pending: pending,
      pendingCount: pCount,
      failed: failed,
      failedCount: fCount,
      refunded: refunded,
      refundedCount: rCount,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isNarrow;
  const _TopBar({required this.isNarrow});

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payments',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: isNarrow ? 16 : 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3)),
              const Text('Live transaction overview',
                  style: TextStyle(color: _textSecondary, fontSize: 12)),
            ],
          ),
          const Spacer(),
          _LiveDot(),
          const SizedBox(width: 8),
          const Text('Live',
              style: TextStyle(
                  color: _success, fontSize: 12, fontWeight: FontWeight.w600)),
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
// STATS
// ─────────────────────────────────────────────────────────────────────────────

class _StatsData {
  final double total, completed, pending, failed, refunded;
  final int totalCount,
      completedCount,
      pendingCount,
      failedCount,
      refundedCount;
  const _StatsData({
    required this.total,
    required this.totalCount,
    required this.completed,
    required this.completedCount,
    required this.pending,
    required this.pendingCount,
    required this.failed,
    required this.failedCount,
    required this.refunded,
    required this.refundedCount,
  });
}

class _StatRow extends StatelessWidget {
  final _StatsData stats;
  final bool isNarrow;
  const _StatRow({required this.stats, required this.isNarrow});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'GH₵ ', decimalDigits: 2);
    final cards = [
      _StatCard(
        icon: Icons.payments_rounded,
        label: 'Total Volume',
        value: fmt.format(stats.total),
        sub: '${stats.totalCount} transactions',
        color: _accent,
      ),
      _StatCard(
        icon: Icons.check_circle_rounded,
        label: 'Completed',
        value: fmt.format(stats.completed),
        sub: '${stats.completedCount} payments',
        color: _success,
      ),
      _StatCard(
        icon: Icons.hourglass_top_rounded,
        label: 'Pending',
        value: fmt.format(stats.pending),
        sub: '${stats.pendingCount} awaiting',
        color: _warning,
      ),
      _StatCard(
        icon: Icons.cancel_rounded,
        label: 'Failed',
        value: fmt.format(stats.failed),
        sub: '${stats.failedCount} transactions',
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
                  fontSize: MediaQuery.of(context).size.width < 700 ? 14 : 17,
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
  final PaymentStatus statusFilter;
  final PaymentMethod methodFilter;
  final DateTimeRange? dateRange;
  final TextEditingController searchCtrl;
  final bool isNarrow;
  final ValueChanged<PaymentStatus> onStatusChanged;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickDate, onClearDate;

  const _FilterBar({
    required this.statusFilter,
    required this.methodFilter,
    required this.dateRange,
    required this.searchCtrl,
    required this.isNarrow,
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
          // Search
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

          // Status chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...PaymentStatus.values.map((s) => _Chip(
                    label: s.label,
                    selected: statusFilter == s,
                    color: s.color,
                    onTap: () => onStatusChanged(s),
                  )),
            ],
          ),
          const SizedBox(height: 10),

          // Method + Date row
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              // Method dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 36,
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PaymentMethod>(
                    value: methodFilter,
                    dropdownColor: _surfaceAlt,
                    style: const TextStyle(color: _textPrimary, fontSize: 13),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _textSecondary, size: 18),
                    items: PaymentMethod.values
                        .map(
                          (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m.name
                                  .replaceAllMapped(RegExp(r'([A-Z])'),
                                      (x) => ' ${x.group(0)}')
                                  .trim()
                                  .capitalizeFirst())),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onMethodChanged(v);
                    },
                  ),
                ),
              ),

              // Date range button
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
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCopyRef;
  final ValueChanged<PaymentRecord> onRefund;

  const _DataTable({
    required this.records,
    required this.selectedId,
    required this.onSelect,
    required this.onCopyRef,
    required this.onRefund,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'GH₵ ', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d, yyyy · HH:mm');

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        // ── header row ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(children: [
            _th('Tenant', flex: 3),
            _th('Hostel / Room', flex: 3),
            _th('Method', flex: 2),
            _th('Reference', flex: 3),
            _th('Amount', flex: 2, align: TextAlign.right),
            _th('Status', flex: 2, align: TextAlign.center),
            _th('Date', flex: 3),
            _th('', flex: 1),
          ]),
        ),

        // ── rows ──
        if (records.isEmpty)
          _EmptyState()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: _border),
            itemBuilder: (ctx, i) {
              final r = records[i];
              final sel = r.id == selectedId;
              return InkWell(
                onTap: () => onSelect(r.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  color: sel ? _accentLow : Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    // Tenant
                    Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.tenantName,
                                style: const TextStyle(
                                    color: _textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                            Text(r.tenantEmail,
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11),
                                overflow: TextOverflow.ellipsis),
                          ],
                        )),
                    // Hostel
                    Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.hostelName,
                                style: const TextStyle(
                                    color: _textPrimary, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                            Text('Room ${r.roomNumber}',
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11)),
                          ],
                        )),
                    // Method
                    Expanded(flex: 2, child: _MethodBadge(method: r.method)),
                    // Reference
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
                    // Amount
                    Expanded(
                        flex: 2,
                        child: Text(fmt.format(r.amount),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700))),
                    // Status
                    Expanded(
                        flex: 2,
                        child: Center(child: _StatusBadge(status: r.status))),
                    // Date
                    Expanded(
                        flex: 3,
                        child: Text(dateFmt.format(r.createdAt),
                            style: const TextStyle(
                                color: _textSecondary, fontSize: 11))),
                    // Actions
                    Expanded(
                        flex: 1,
                        child: r.status == PaymentStatus.completed
                            ? Tooltip(
                                message: 'Refund',
                                child: InkWell(
                                  onTap: () => onRefund(r),
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.replay_rounded,
                                        color: _textMuted, size: 16),
                                  ),
                                ),
                              )
                            : const SizedBox()),
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
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCopyRef;
  final ValueChanged<PaymentRecord> onRefund;

  const _CardList({
    required this.records,
    required this.selectedId,
    required this.onSelect,
    required this.onCopyRef,
    required this.onRefund,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return _EmptyState();
    final fmt = NumberFormat.currency(symbol: 'GH₵ ', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d, yyyy · HH:mm');

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: records.length,
      itemBuilder: (ctx, i) {
        final r = records[i];
        final sel = r.id == selectedId;
        return GestureDetector(
          onTap: () => onSelect(r.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? _accentLow : _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? _accent : _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(r.tenantName,
                        style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ),
                  Text(fmt.format(r.amount),
                      style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ]),
                const SizedBox(height: 4),
                Text(r.hostelName,
                    style:
                        const TextStyle(color: _textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: [
                  _StatusBadge(status: r.status),
                  const SizedBox(width: 8),
                  _MethodBadge(method: r.method),
                  const Spacer(),
                  if (r.status == PaymentStatus.completed)
                    TextButton.icon(
                      onPressed: () => onRefund(r),
                      icon: const Icon(Icons.replay_rounded, size: 14),
                      label:
                          const Text('Refund', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: _textSecondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: Row(children: [
                    Text(r.reference,
                        style: const TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                            fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onCopyRef(r.reference),
                      child: const Icon(Icons.copy_rounded,
                          color: _textMuted, size: 13),
                    ),
                  ])),
                  Text(dateFmt.format(r.createdAt),
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED BADGE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final PaymentStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Text(status.label,
          style:
              TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  final String method;
  const _MethodBadge({required this.method});

  IconData get _icon => switch (method.toLowerCase()) {
        String m when m.contains('mobile') => Icons.phone_android_rounded,
        String m when m.contains('card') => Icons.credit_card_rounded,
        String m when m.contains('bank') => Icons.account_balance_rounded,
        _ => Icons.payment_rounded,
      };

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: _textSecondary),
          const SizedBox(width: 4),
          Flexible(
              child: Text(method,
                  style: const TextStyle(color: _textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// REFUND DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _RefundDialog extends StatelessWidget {
  final PaymentRecord record;
  const _RefundDialog({required this.record});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'GH₵ ', decimalDigits: 2);
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
            'Refund ${fmt.format(record.amount)} to ${record.tenantName}?',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text('Ref: ${record.reference}',
              style: const TextStyle(color: _textMuted, fontSize: 12)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
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
                onPressed: () => Navigator.pop(context, true),
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
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
            child: Column(children: [
          const Icon(Icons.receipt_long_rounded, color: _textMuted, size: 48),
          const SizedBox(height: 12),
          const Text('No payments found',
              style: TextStyle(
                  color: _textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Try adjusting your filters',
              style: TextStyle(color: _textMuted, fontSize: 13)),
        ])),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EXTENSION HELPERS
// ─────────────────────────────────────────────────────────────────────────────

extension _StringExt on String {
  String capitalizeFirst() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
