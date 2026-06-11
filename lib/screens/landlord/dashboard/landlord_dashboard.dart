// lib/screens/landlord/dashboard/landlord_dashboard.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Landlord Dashboard  (fully responsive)
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/landlord_service.dart';
import '../../../models/models.dart';

class _C {
  static const pageBg = Color(0xFFF5F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF1F2937);
  static const textLight = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const green = Color(0xFF2D6A4F);
  static const greenAccent = Color(0xFF40916C);
  static const greenLight = Color(0xFFD8F3DC);
  static const greenFaint = Color(0xFFF0FAF3);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFEF3C7);
  static const blue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFFDBEAFE);
  static const red = Color(0xFFEF4444);
  static const redLight = Color(0xFFFEE2E2);
}

// ── Responsive helpers ────────────────────────────────────────
double _responsivePadding(double width) {
  if (width < 400) return 16;
  if (width < 600) return 20;
  return 24;
}

// ─────────────────────────────────────────────────────────────
// DASHBOARD
// ─────────────────────────────────────────────────────────────
class LandlordDashboard extends StatefulWidget {
  const LandlordDashboard({
    super.key,
    required this.landlordId,
    required this.service,
  });

  final String landlordId;
  final LandlordService service;

  @override
  State<LandlordDashboard> createState() => _LandlordDashboardState();
}

class _LandlordDashboardState extends State<LandlordDashboard> {
  late Future<LandlordStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _statsFuture = widget.service.getDashboardStats(widget.landlordId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: FutureBuilder<LandlordStats>(
        future: _statsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _C.green),
            );
          }
          if (snap.hasError) return _ErrorState(onRetry: _refresh);

          final stats = snap.data!;
          return RefreshIndicator(
            color: _C.green,
            onRefresh: () async => _refresh(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final pad = _responsivePadding(w);
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeBanner(width: w),
                      SizedBox(height: pad),
                      _StatsGrid(stats: stats, width: w),
                      SizedBox(height: pad),
                      // Two-column at ≥ 640 px, stacked below
                      if (w >= 640)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _RecentBookings(
                                  bookings: stats.recentBookings, width: w),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 2,
                              child: _OccupancyCard(stats: stats),
                            ),
                          ],
                        )
                      else
                        Column(children: [
                          _RecentBookings(
                              bookings: stats.recentBookings, width: w),
                          SizedBox(height: pad),
                          _OccupancyCard(stats: stats),
                        ]),
                      SizedBox(height: pad),
                      _QuickActions(width: w),
                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WELCOME BANNER
// ─────────────────────────────────────────────────────────────
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final isNarrow = width < 400;

    return Container(
      padding: EdgeInsets.all(isNarrow ? 16 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _C.green.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting 👋',
                  style: TextStyle(
                      color: const Color(0xCCFFFFFF),
                      fontSize: isNarrow ? 11 : 13,
                      fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 4),
                Text(
                  'Here\'s your hostel overview',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: isNarrow ? 16 : 20,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                  style: TextStyle(
                      color: const Color(0xAAFFFFFF),
                      fontSize: isNarrow ? 10 : 12),
                ),
              ],
            ),
          ),
          // Hide decorative icon on very narrow screens
          if (!isNarrow) ...[
            const SizedBox(width: 12),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.apartment_rounded,
                  color: Colors.white, size: 28),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STATS GRID
// ─────────────────────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.width});
  final LandlordStats stats;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatData(
        label: 'Total Hostels',
        value: '${stats.totalHostels}',
        icon: Icons.apartment_rounded,
        iconBg: _C.greenFaint,
        iconColor: _C.green,
        sub: stats.totalHostels == 1
            ? '1 property'
            : '${stats.totalHostels} properties',
      ),
      _StatData(
        label: 'Total Rooms',
        value: '${stats.totalRooms}',
        icon: Icons.bed_rounded,
        iconBg: _C.blueLight,
        iconColor: _C.blue,
        sub: '${stats.availableRooms} available',
      ),
      _StatData(
        label: 'Active Bookings',
        value: '${stats.confirmedBookings}',
        icon: Icons.calendar_month_rounded,
        iconBg: _C.greenLight,
        iconColor: _C.greenAccent,
        sub: '${stats.pendingBookings} pending',
      ),
      _StatData(
        label: 'Occupancy Rate',
        value: '${(stats.occupancyRate * 100).toStringAsFixed(0)}%',
        icon: Icons.pie_chart_rounded,
        iconBg: _C.amberLight,
        iconColor: _C.amber,
        sub: '${stats.occupiedRooms} of ${stats.totalRooms} rooms',
      ),
    ];

    // 4 cols ≥ 800 | 2 cols ≥ 360 | 1 col on tiny phones
    final cols = width >= 800
        ? 4
        : width >= 360
            ? 2
            : 1;
    final cardHeight = width < 400 ? 110.0 : 120.0;

    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisExtent: cardHeight,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (_, i) => _StatCard(data: cards[i], compact: width < 400),
    );
  }
}

class _StatData {
  final String label, value, sub;
  final IconData icon;
  final Color iconBg, iconColor;
  const _StatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.sub,
  });
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data, this.compact = false});
  final _StatData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(data.label,
                    style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        color: _C.textLight,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                width: compact ? 28 : 32,
                height: compact ? 28 : 32,
                decoration: BoxDecoration(
                    color: data.iconBg, borderRadius: BorderRadius.circular(8)),
                child: Icon(data.icon,
                    color: data.iconColor, size: compact ? 14 : 16),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.value,
                  style: TextStyle(
                      fontSize: compact ? 20 : 24,
                      fontWeight: FontWeight.w700,
                      color: _C.textDark)),
              const SizedBox(height: 2),
              Text(data.sub,
                  style: TextStyle(
                      fontSize: compact ? 9 : 10, color: _C.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// RECENT BOOKINGS
// ─────────────────────────────────────────────────────────────
class _RecentBookings extends StatelessWidget {
  const _RecentBookings({required this.bookings, required this.width});
  final List<Booking> bookings;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Bookings',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _C.textDark)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _C.greenFaint,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${bookings.length} recent',
                      style: const TextStyle(
                          fontSize: 10,
                          color: _C.green,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _C.border),
          if (bookings.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 36, color: _C.textMuted),
                  SizedBox(height: 8),
                  Text('No bookings yet',
                      style: TextStyle(color: _C.textMuted, fontSize: 13)),
                ]),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bookings.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _C.border),
              itemBuilder: (_, i) =>
                  _BookingRow(booking: bookings[i], width: width),
            ),
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.booking, required this.width});
  final Booking booking;
  final double width;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (booking.status.toLowerCase()) {
      'confirmed' => _C.green,
      'pending' => _C.amber,
      'cancelled' => _C.red,
      _ => _C.textMuted,
    };
    final statusBg = switch (booking.status.toLowerCase()) {
      'confirmed' => _C.greenFaint,
      'pending' => _C.amberLight,
      'cancelled' => _C.redLight,
      _ => _C.border,
    };
    final statusLabel = switch (booking.status.toLowerCase()) {
      'confirmed' => 'Confirmed',
      'pending' => 'Pending',
      'cancelled' => 'Cancelled',
      _ => booking.status,
    };

    final date = DateFormat('MMM d').format(booking.bookedAt);
    // On very narrow screens, hide the hostel sub-label to save space
    final showHostel = width >= 360;

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: width < 400 ? 12 : 18, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
                color: _C.greenFaint, shape: BoxShape.circle),
            child: Center(
              child: Text(
                (booking.name.isNotEmpty ? booking.name[0] : '?').toUpperCase(),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _C.green),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _C.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (showHostel) ...[
                  const SizedBox(height: 2),
                  Text(booking.hostelName,
                      style: const TextStyle(fontSize: 11, color: _C.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(date,
                  style: const TextStyle(fontSize: 11, color: _C.textMuted)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: statusBg, borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// OCCUPANCY CARD  (unchanged — already compact)
// ─────────────────────────────────────────────────────────────
class _OccupancyCard extends StatelessWidget {
  const _OccupancyCard({required this.stats});
  final LandlordStats stats;

  @override
  Widget build(BuildContext context) {
    final rate = stats.occupancyRate.clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Text('Occupancy Breakdown',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _C.textDark)),
          ),
          const Divider(height: 28, color: _C.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                _CircleOccupancy(rate: rate),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OccupancyLegend(
                          color: _C.green,
                          label: 'Occupied',
                          count: stats.occupiedRooms),
                      const SizedBox(height: 10),
                      _OccupancyLegend(
                          color: _C.greenLight,
                          label: 'Available',
                          count: stats.availableRooms),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: _C.border),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bookings by Status',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _C.textLight)),
                const SizedBox(height: 12),
                _StatusBar(
                    label: 'Confirmed',
                    count: stats.confirmedBookings,
                    total: stats.totalBookings,
                    color: _C.green),
                const SizedBox(height: 8),
                _StatusBar(
                    label: 'Pending',
                    count: stats.pendingBookings,
                    total: stats.totalBookings,
                    color: _C.amber),
                const SizedBox(height: 8),
                _StatusBar(
                    label: 'Cancelled',
                    count: stats.totalBookings -
                        stats.pendingBookings -
                        stats.confirmedBookings,
                    total: stats.totalBookings,
                    color: _C.red),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleOccupancy extends StatelessWidget {
  const _CircleOccupancy({required this.rate});
  final double rate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: rate,
            strokeWidth: 9,
            backgroundColor: _C.greenLight,
            valueColor: const AlwaysStoppedAnimation<Color>(_C.green),
            strokeCap: StrokeCap.round,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(rate * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _C.textDark),
              ),
              const Text('full',
                  style: TextStyle(fontSize: 10, color: _C.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OccupancyLegend extends StatelessWidget {
  const _OccupancyLegend(
      {required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text('$label ',
          style: const TextStyle(fontSize: 12, color: _C.textLight)),
      Text('$count',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: _C.textDark)),
    ]);
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });
  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: _C.textLight)),
            Text('$count',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _C.textDark)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: _C.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// QUICK ACTIONS
// ─────────────────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(width < 400 ? 14 : 18),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick Actions',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _C.textDark)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionButton(
                  icon: Icons.add_home_rounded,
                  label: 'Add Hostel',
                  color: _C.green,
                  bg: _C.greenFaint,
                  compact: width < 400),
              _ActionButton(
                  icon: Icons.bed_rounded,
                  label: 'Add Room',
                  color: _C.blue,
                  bg: _C.blueLight,
                  compact: width < 400),
              _ActionButton(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Review Bookings',
                  color: _C.amber,
                  bg: _C.amberLight,
                  compact: width < 400),
              _ActionButton(
                  icon: Icons.bar_chart_rounded,
                  label: 'View Reports',
                  color: _C.greenAccent,
                  bg: _C.greenLight,
                  compact: width < 400),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 0 : 120),
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16, vertical: compact ? 8 : 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: compact ? 14 : 16),
            SizedBox(width: compact ? 6 : 8),
            Text(label,
                style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ERROR STATE
// ─────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: _C.textMuted),
          const SizedBox(height: 12),
          const Text('Failed to load dashboard',
              style: TextStyle(color: _C.textDark, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Check your connection and try again.',
              style: TextStyle(color: _C.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: _C.green),
          ),
        ],
      ),
    );
  }
}
