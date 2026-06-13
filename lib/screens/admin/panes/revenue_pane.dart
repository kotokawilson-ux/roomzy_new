// lib/screens/admin/panes/revenue_pane.dart
// ─────────────────────────────────────────────────────────────────────────────
// RoomzyFind — Revenue & Platform Settings Pane
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

// ── Colour tokens (matching admin_theme.dart) ─────────────────────────────
const _kGreen = Color(0xFF1B4332);
const _kGreenAccent = Color(0xFF2D6A4F);
const _kCream = Color(0xFFF5F5F0);
const _kSurface = Color(0xFFFFFFFF);
const _kBorder = Color(0xFFE5E7EB);
const _kTextDark = Color(0xFF1F2937);
const _kTextLight = Color(0xFF6B7280);
const _kTextMuted = Color(0xFF9CA3AF);

const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';

final _db = FirebaseFirestore.instance;
final _fmt = NumberFormat('#,##0.00');

// ─────────────────────────────────────────────────────────────────────────────
// REVENUE PANE
// ─────────────────────────────────────────────────────────────────────────────

class RevenuePane extends StatefulWidget {
  const RevenuePane({super.key});

  @override
  State<RevenuePane> createState() => _RevenuePaneState();
}

class _RevenuePaneState extends State<RevenuePane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _period = 'all'; // 'today' | 'week' | 'month' | 'all'

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        _PageHeader(
          period: _period,
          onPeriodChanged: (p) => setState(() => _period = p),
        ),

        // ── Tab bar ──────────────────────────────────────────────────────────
        Container(
          color: _kSurface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: _kGreenAccent,
            unselectedLabelColor: _kTextLight,
            indicatorColor: _kGreenAccent,
            indicatorWeight: 2,
            dividerColor: _kBorder,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(
                icon: Icon(Icons.bar_chart_rounded, size: 16),
                text: 'Overview',
              ),
              Tab(
                icon: Icon(Icons.people_alt_outlined, size: 16),
                text: 'Per Landlord',
              ),
              Tab(
                icon: Icon(Icons.tune_rounded, size: 16),
                text: 'Commission Settings',
              ),
            ],
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(period: _period, isWide: isWide),
              _LandlordRevenueTab(period: _period),
              const _CommissionSettingsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.period, required this.onPeriodChanged});
  final String period;
  final void Function(String) onPeriodChanged;

  static const _periods = [
    ('today', 'Today'),
    ('week', 'This Week'),
    ('month', 'This Month'),
    ('all', 'All Time'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          // Icon + title
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kGreenAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.show_chart_rounded,
                color: _kGreenAccent, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Revenue',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _kTextDark)),
                Text('Commission earnings & platform analytics',
                    style: TextStyle(fontSize: 12, color: _kTextLight)),
              ],
            ),
          ),
          // Period filter
          Wrap(
            spacing: 6,
            children: _periods.map((p) {
              final selected = period == p.$1;
              return GestureDetector(
                onTap: () => onPeriodChanged(p.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? _kGreenAccent
                        : _kGreenAccent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? _kGreenAccent
                          : _kGreenAccent.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    p.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _kGreenAccent,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERVIEW TAB
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.period, required this.isWide});
  final String period;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('bookings')
          .where('status', isEqualTo: 'confirmed')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _kGreenAccent));
        }

        final docs = snap.data?.docs ?? [];
        final filtered = _filterByPeriod(docs, period);

        // Compute stats
        double totalPaid = 0;
        double totalCommission = 0;
        double totalLandlordPayout = 0;
        int totalBookings = filtered.length;
        int fullyPaid = 0;
        int depositOnly = 0;

        final Map<String, double> monthlyCommission = {};

        for (final doc in filtered) {
          final d = doc.data();
          final amountPaid = (d['amount_paid'] as num?)?.toDouble() ?? 0;
          final commission = (d['commission_collected'] as num?)?.toDouble() ??
              (amountPaid * 0.05);
          totalPaid += amountPaid;
          totalCommission += commission;
          totalLandlordPayout += amountPaid - commission;

          if (d['payment_status'] == 'fully_paid') fullyPaid++;
          if (d['payment_status'] == 'deposit_paid') depositOnly++;

          // Monthly breakdown
          final paidAt = d['paid_at'];
          if (paidAt is Timestamp) {
            final month = DateFormat('MMM yyyy').format(paidAt.toDate());
            monthlyCommission[month] =
                (monthlyCommission[month] ?? 0) + commission;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stat chips ───────────────────────────────────────────────
              isWide
                  ? Row(children: [
                      Expanded(
                          child: _StatCard(
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'Platform Revenue',
                        value: 'GHS ${_fmt.format(totalCommission)}',
                        sub: 'Commission earned',
                        color: _kGreenAccent,
                      )),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _StatCard(
                        icon: Icons.receipt_long_rounded,
                        label: 'Total Processed',
                        value: 'GHS ${_fmt.format(totalPaid)}',
                        sub: 'Student payments',
                        color: const Color(0xFF2563EB),
                      )),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _StatCard(
                        icon: Icons.send_rounded,
                        label: 'Landlord Payouts',
                        value: 'GHS ${_fmt.format(totalLandlordPayout)}',
                        sub: 'After commission deduction',
                        color: const Color(0xFF7C3AED),
                      )),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _StatCard(
                        icon: Icons.calendar_month_rounded,
                        label: 'Bookings',
                        value: '$totalBookings',
                        sub: '$fullyPaid full · $depositOnly deposit',
                        color: const Color(0xFFEA580C),
                      )),
                    ])
                  : Column(children: [
                      _StatCard(
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'Platform Revenue',
                        value: 'GHS ${_fmt.format(totalCommission)}',
                        sub: 'Commission earned',
                        color: _kGreenAccent,
                      ),
                      const SizedBox(height: 12),
                      _StatCard(
                        icon: Icons.receipt_long_rounded,
                        label: 'Total Processed',
                        value: 'GHS ${_fmt.format(totalPaid)}',
                        sub: 'Student payments',
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 12),
                      _StatCard(
                        icon: Icons.send_rounded,
                        label: 'Landlord Payouts',
                        value: 'GHS ${_fmt.format(totalLandlordPayout)}',
                        sub: '95% of payments',
                        color: const Color(0xFF7C3AED),
                      ),
                      const SizedBox(height: 12),
                      _StatCard(
                        icon: Icons.calendar_month_rounded,
                        label: 'Bookings',
                        value: '$totalBookings',
                        sub: '$fullyPaid full · $depositOnly deposit',
                        color: const Color(0xFFEA580C),
                      ),
                    ]),

              const SizedBox(height: 24),

              // ── Split visual ─────────────────────────────────────────────
              _SplitVisual(
                  totalPaid: totalPaid,
                  commission: totalCommission,
                  landlordPayout: totalLandlordPayout),

              const SizedBox(height: 24),

              // ── Monthly breakdown ────────────────────────────────────────
              if (monthlyCommission.isNotEmpty) ...[
                _SectionHead(
                    icon: Icons.bar_chart_rounded,
                    title: 'Monthly Commission Breakdown'),
                const SizedBox(height: 12),
                _MonthlyChart(data: monthlyCommission),
                const SizedBox(height: 24),
              ],

              // ── Recent confirmed bookings ────────────────────────────────
              _SectionHead(
                  icon: Icons.history_rounded, title: 'Recent Transactions'),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                _EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'No confirmed bookings for this period')
              else
                _TransactionsTable(docs: filtered.take(20).toList()),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PER-LANDLORD TAB
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordRevenueTab extends StatelessWidget {
  const _LandlordRevenueTab({required this.period});
  final String period;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('bookings')
          .where('status', isEqualTo: 'confirmed')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _kGreenAccent));
        }

        final docs = _filterByPeriod(snap.data?.docs ?? [], period);

        // Group by landlord
        final Map<String, _LandlordRevData> landlords = {};
        for (final doc in docs) {
          final d = doc.data();
          final landlordId = d['landlord_id']?.toString() ?? '';
          if (landlordId.isEmpty) continue;
          final amountPaid = (d['amount_paid'] as num?)?.toDouble() ?? 0;
          final commission = (d['commission_collected'] as num?)?.toDouble() ??
              (amountPaid * 0.05);

          landlords.putIfAbsent(
              landlordId,
              () => _LandlordRevData(
                    landlordId: landlordId,
                    name: d['landlord_id']?.toString() ?? '—',
                  ));
          landlords[landlordId]!.totalPaid += amountPaid;
          landlords[landlordId]!.commission += commission;
          landlords[landlordId]!.bookings++;
        }

        final sorted = landlords.values.toList()
          ..sort((a, b) => b.totalPaid.compareTo(a.totalPaid));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHead(
                  icon: Icons.people_alt_rounded, title: 'Revenue by Landlord'),
              const SizedBox(height: 12),
              if (sorted.isEmpty)
                _EmptyState(
                    icon: Icons.people_outline,
                    message: 'No data for this period')
              else
                ...sorted.map((l) => _LandlordRevenueCard(data: l)),
            ],
          ),
        );
      },
    );
  }
}

class _LandlordRevData {
  final String landlordId;
  String name;
  double totalPaid = 0;
  double commission = 0;
  int bookings = 0;

  _LandlordRevData({required this.landlordId, required this.name});

  double get landlordPayout => totalPaid - commission;
}

class _LandlordRevenueCard extends StatelessWidget {
  const _LandlordRevenueCard({required this.data});
  final _LandlordRevData data;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _db.collection('landlords').doc(data.landlordId).get(),
      builder: (context, snap) {
        final landlordName =
            snap.data?.data()?['full_name']?.toString() ?? data.name;
        final hasSubaccount =
            snap.data?.data()?['paystack_subaccount']?.toString().isNotEmpty ==
                true;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            children: [
              Row(children: [
                // Avatar
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _kGreenAccent.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      landlordName.isNotEmpty
                          ? landlordName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _kGreenAccent),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(landlordName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _kTextDark)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Text(
                            '${data.bookings} booking${data.bookings != 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: _kTextLight)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: hasSubaccount
                                ? _kGreenAccent.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            hasSubaccount ? 'Payout Active' : 'No Payout Setup',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: hasSubaccount
                                    ? _kGreenAccent
                                    : Colors.orange),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                // Total
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('GHS ${_fmt.format(data.totalPaid)}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _kTextDark)),
                  const Text('total collected',
                      style: TextStyle(fontSize: 10, color: _kTextMuted)),
                ]),
              ]),
              const SizedBox(height: 14),
              // Progress bar row
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Landlord gets',
                              style: const TextStyle(
                                  fontSize: 11, color: _kTextLight)),
                          Text('GHS ${_fmt.format(data.landlordPayout)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _kTextDark)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: data.totalPaid > 0
                              ? data.landlordPayout / data.totalPaid
                              : 0,
                          minHeight: 6,
                          backgroundColor: _kBorder,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF2563EB)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Commission',
                      style: TextStyle(fontSize: 11, color: _kTextLight)),
                  Text('GHS ${_fmt.format(data.commission)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kGreenAccent)),
                ]),
              ]),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMISSION SETTINGS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _CommissionSettingsTab extends StatefulWidget {
  const _CommissionSettingsTab();

  @override
  State<_CommissionSettingsTab> createState() => _CommissionSettingsTabState();
}

class _CommissionSettingsTabState extends State<_CommissionSettingsTab> {
  final _globalCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  double _currentGlobal = 5.0;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await _db.collection('settings').doc('platform').get();
      final val =
          (doc.data()?['commission_percent'] as num?)?.toDouble() ?? 5.0;
      setState(() {
        _currentGlobal = val;
        _globalCtrl.text = val.toStringAsFixed(0);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveGlobal() async {
    final val = double.tryParse(_globalCtrl.text.trim());
    if (val == null || val < 0 || val > 50) {
      setState(() => _error = 'Enter a valid percentage between 0 and 50.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    try {
      await _db.collection('settings').doc('platform').set({
        'commission_percent': val,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _currentGlobal = val;
        _success =
            'Global commission updated to ${val.toStringAsFixed(0)}%. New bookings will use this rate.';
      });
    } catch (e) {
      setState(() => _error = 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _globalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _kGreenAccent));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Global commission ────────────────────────────────────────────
          _SectionHead(
              icon: Icons.percent_rounded, title: 'Global Commission Rate'),
          const SizedBox(height: 4),
          const Text(
            'This is the default commission RoomzyFind takes from every payment. It applies to all landlords unless overridden individually.',
            style: TextStyle(fontSize: 12, color: _kTextLight, height: 1.5),
          ),
          const SizedBox(height: 16),

          // Current rate display
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kGreen, _kGreenAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current Rate',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${_currentGlobal.toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Student pays GHS 1000 → Landlord gets GHS ${(1000 * (1 - _currentGlobal / 100)).toStringAsFixed(0)} · RoomzyFind keeps GHS ${(1000 * _currentGlobal / 100).toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 11),
                      ),
                    ]),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.percent_rounded,
                    color: Colors.white, size: 30),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Edit rate
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Update Commission Rate',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _globalCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}$'))
                      ],
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _kTextDark),
                      decoration: InputDecoration(
                        suffixText: '%',
                        suffixStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _kTextLight),
                        hintText: '5',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _kBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: _kGreenAccent, width: 1.5)),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveGlobal,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded,
                              size: 16, color: Colors.white),
                      label: Text(
                        _saving ? 'Saving…' : 'Save Rate',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreenAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _AlertBanner(
                      message: _error!,
                      color: Colors.red,
                      icon: Icons.error_outline),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 10),
                  _AlertBanner(
                      message: _success!,
                      color: _kGreenAccent,
                      icon: Icons.check_circle_outline),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Per-landlord overrides ───────────────────────────────────────
          _SectionHead(
              icon: Icons.people_alt_rounded,
              title: 'Per-Landlord Commission Overrides'),
          const SizedBox(height: 4),
          const Text(
            'Set a custom commission rate for a specific landlord. Leave blank to use the global rate.',
            style: TextStyle(fontSize: 12, color: _kTextLight, height: 1.5),
          ),
          const SizedBox(height: 16),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                _db.collection('landlords').orderBy('full_name').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: _kGreenAccent));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const _EmptyState(
                    icon: Icons.people_outline,
                    message: 'No landlords registered yet');
              }
              return Column(
                children: docs
                    .map((doc) => _LandlordCommissionRow(
                          doc: doc,
                          globalRate: _currentGlobal,
                        ))
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // ── Info note ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFFEA580C)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Changing the commission rate updates future bookings only. Existing confirmed bookings are not affected. The new rate is stored in Firestore and read by the backend when processing each payment.',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFFEA580C), height: 1.5),
                    ),
                  ),
                ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDLORD COMMISSION ROW
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordCommissionRow extends StatefulWidget {
  const _LandlordCommissionRow({required this.doc, required this.globalRate});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final double globalRate;

  @override
  State<_LandlordCommissionRow> createState() => _LandlordCommissionRowState();
}

class _LandlordCommissionRowState extends State<_LandlordCommissionRow> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final d = widget.doc.data();
    final custom = (d['commission_percent'] as num?)?.toDouble();
    _ctrl = TextEditingController(
        text: custom != null ? custom.toStringAsFixed(0) : '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final val = double.tryParse(_ctrl.text.trim());
    if (val == null) return;
    setState(() => _saving = true);
    try {
      // Update Firestore (used for display + per-booking snapshots)
      await _db.collection('landlords').doc(widget.doc.id).update({
        'commission_percent': val,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Update the Paystack subaccount's default split rate too
      try {
        await http.post(
          Uri.parse(
              'https://roomzy-backend-eight.vercel.app/api/update-subaccount-rate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'landlordId': widget.doc.id,
            'percentageCharge': val,
          }),
        );
      } catch (e) {
        debugPrint('Subaccount rate sync failed (non-fatal): $e');
      }

      setState(() => _saved = true);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final name = d['full_name']?.toString() ?? '—';
    final hasSubaccount =
        d['paystack_subaccount']?.toString().isNotEmpty == true;
    final customRate = (d['commission_percent'] as num?)?.toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _kGreenAccent.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kGreenAccent),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Name + status
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kTextDark),
                overflow: TextOverflow.ellipsis),
            Text(
              customRate != null
                  ? 'Custom: ${customRate.toStringAsFixed(0)}%'
                  : 'Using global: ${widget.globalRate.toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 11,
                  color: customRate != null ? _kGreenAccent : _kTextMuted),
            ),
          ]),
        ),

        // Payout badge
        if (!hasSubaccount)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('No Payout',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange)),
          ),

        // Rate input
        SizedBox(
          width: 60,
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}$'))
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _kTextDark),
            decoration: InputDecoration(
              suffixText: '%',
              suffixStyle: const TextStyle(fontSize: 11, color: _kTextLight),
              hintText: '${widget.globalRate.toStringAsFixed(0)}',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: _kGreenAccent, width: 1.5)),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Save button
        GestureDetector(
          onTap: _saving ? null : _save,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _saved ? Colors.green : _kGreenAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: _saving
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kGreenAccent))
                  : Icon(_saved ? Icons.check_rounded : Icons.save_outlined,
                      size: 15, color: _saved ? Colors.white : _kGreenAccent),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPLIT VISUAL
// ─────────────────────────────────────────────────────────────────────────────

class _SplitVisual extends StatelessWidget {
  const _SplitVisual({
    required this.totalPaid,
    required this.commission,
    required this.landlordPayout,
  });
  final double totalPaid;
  final double commission;
  final double landlordPayout;

  @override
  Widget build(BuildContext context) {
    final commissionPct = totalPaid > 0 ? commission / totalPaid : 0.05;
    final landlordPct = 1 - commissionPct;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.pie_chart_outline_rounded, size: 16, color: _kTextLight),
            SizedBox(width: 8),
            Text('Payment Split',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kTextDark)),
          ]),
          const SizedBox(height: 16),

          // Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 24,
              child: Row(children: [
                Flexible(
                  flex: (landlordPct * 100).round(),
                  child: Container(
                    color: const Color(0xFF2563EB),
                    child: Center(
                      child: Text(
                        '${(landlordPct * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  flex: (commissionPct * 100).round(),
                  child: Container(
                    color: _kGreenAccent,
                    child: Center(
                      child: Text(
                        '${(commissionPct * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _LegendItem(
                color: const Color(0xFF2563EB),
                label: 'Landlord Payout',
                value: 'GHS ${_fmt.format(landlordPayout)}'),
            _LegendItem(
                color: _kGreenAccent,
                label: 'Platform Commission',
                value: 'GHS ${_fmt.format(commission)}'),
          ]),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(
      {required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _kTextLight)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kTextDark)),
        ]),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// MONTHLY CHART (simple bar chart)
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.data});
  final Map<String, double> data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()
      ..sort((a, b) {
        final af = DateFormat('MMM yyyy').parse(a.key);
        final bf = DateFormat('MMM yyyy').parse(b.key);
        return af.compareTo(bf);
      });

    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: entries.map((e) {
                final pct = maxVal > 0 ? e.value / maxVal : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'GHS ${_fmt.format(e.value)}',
                          style: const TextStyle(
                              fontSize: 8,
                              color: _kTextMuted,
                              fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          height: (80 * pct).clamp(4.0, 80.0),
                          decoration: BoxDecoration(
                            color: _kGreenAccent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: entries.map((e) {
              return Expanded(
                child: Text(
                  e.key.split(' ').first, // Just "Jan", "Feb" etc
                  style: const TextStyle(fontSize: 9, color: _kTextMuted),
                  textAlign: TextAlign.center,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSACTIONS TABLE
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionsTable extends StatelessWidget {
  const _TransactionsTable({required this.docs});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kGreenAccent.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: const Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: const Row(children: [
              Expanded(
                  flex: 3,
                  child: Text('Student / Hostel',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kTextLight))),
              Expanded(
                  flex: 2,
                  child: Text('Amount Paid',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kTextLight),
                      textAlign: TextAlign.center)),
              Expanded(
                  flex: 2,
                  child: Text('Commission',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kTextLight),
                      textAlign: TextAlign.center)),
              Expanded(
                  flex: 2,
                  child: Text('Date',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kTextLight),
                      textAlign: TextAlign.right)),
            ]),
          ),

          // Rows
          ...docs.asMap().entries.map((entry) {
            final i = entry.key;
            final doc = entry.value;
            final d = doc.data();
            final amountPaid = (d['amount_paid'] as num?)?.toDouble() ?? 0;
            final commission =
                (d['commission_collected'] as num?)?.toDouble() ??
                    (amountPaid * 0.05);
            final paidAt = d['paid_at'];
            String dateStr = '—';
            if (paidAt is Timestamp) {
              dateStr = DateFormat('dd MMM').format(paidAt.toDate());
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: i.isOdd ? const Color(0xFFF9FAFB) : _kSurface,
                border: i < docs.length - 1
                    ? const Border(bottom: BorderSide(color: _kBorder))
                    : null,
                borderRadius: i == docs.length - 1
                    ? const BorderRadius.vertical(bottom: Radius.circular(14))
                    : null,
              ),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['name']?.toString() ?? '—',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kTextDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          d['hostel_name']?.toString() ?? '—',
                          style:
                              const TextStyle(fontSize: 10, color: _kTextMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        _PaymentStatusBadge(
                            status: d['payment_status']?.toString() ?? ''),
                      ]),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'GHS ${_fmt.format(amountPaid)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'GHS ${_fmt.format(commission)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kGreenAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    dateStr,
                    style: const TextStyle(fontSize: 11, color: _kTextLight),
                    textAlign: TextAlign.right,
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

class _PaymentStatusBadge extends StatelessWidget {
  const _PaymentStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    final (label, color) = switch (status) {
      'fully_paid' => ('Fully Paid', _kGreenAccent),
      'deposit_paid' => ('Deposit Paid', Color(0xFFEA580C)),
      _ => ('Pending', Color(0xFF9CA3AF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterByPeriod(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String period) {
  if (period == 'all') return docs;

  final now = DateTime.now();
  final DateTime cutoff;
  switch (period) {
    case 'today':
      cutoff = DateTime(now.year, now.month, now.day);
      break;
    case 'week':
      cutoff = now.subtract(const Duration(days: 7));
      break;
    case 'month':
      cutoff = DateTime(now.year, now.month, 1);
      break;
    default:
      return docs;
  }

  return docs.where((doc) {
    final d = doc.data();
    final ts = d['paid_at'] ?? d['booked_at'];
    if (ts is! Timestamp) return false;
    return ts.toDate().isAfter(cutoff);
  }).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: _kTextLight)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _kTextDark)),
              Text(sub,
                  style: const TextStyle(fontSize: 10, color: _kTextMuted)),
            ]),
          ),
        ]),
      );
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: _kGreenAccent),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: _kTextDark)),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: _kBorder, height: 1)),
      ]);
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner(
      {required this.message, required this.color, required this.icon});
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(message, style: TextStyle(fontSize: 12, color: color))),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: _kTextMuted.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(fontSize: 13, color: _kTextLight)),
          ]),
        ),
      );
}
