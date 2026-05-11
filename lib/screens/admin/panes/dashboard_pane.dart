import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../constants/admin_theme.dart';
import '../../../../utils/admin_helpers.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/stat_cards.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD PANE
// ─────────────────────────────────────────────────────────────────────────────

class DashboardPane extends StatelessWidget {
  const DashboardPane({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SectionLabel('Overview'),
            SizedBox(height: 12),
            StatCardsRow(),
            SizedBox(height: 28),
            SectionLabel('Quick Stats'),
            SizedBox(height: 12),
            QuickStatsRow(),
            SizedBox(height: 28),
            SectionLabel('Recent Bookings'),
            SizedBox(height: 12),
            _RecentBookingsTable(),
            SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TopHostelsCard()),
                SizedBox(width: 16),
                Expanded(child: _RecentStudentsCard()),
              ],
            ),
            SizedBox(height: 28),
            SectionLabel('Monthly Booking Trends'),
            SizedBox(height: 12),
            _MonthlyChart(),
            SizedBox(height: 28),
            SectionLabel('Bookings by School'),
            SizedBox(height: 12),
            _SchoolChart(),
            SizedBox(height: 40),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENT BOOKINGS TABLE
// ─────────────────────────────────────────────────────────────────────────────

class _RecentBookingsTable extends StatelessWidget {
  const _RecentBookingsTable();

  @override
  Widget build(BuildContext context) => DataCard(
        title: '',
        child: StreamBuilder<QuerySnapshot>(
          stream: db
              .collection('bookings')
              .orderBy('bookedAt', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const CardLoading(height: 160);
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const EmptyCard(
                message: 'No bookings yet',
                height: 100,
              );
            }
            return Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: kSurfaceAlt,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: kBorder)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                          child: Text('Student',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kTextLight))),
                      Expanded(
                          child: Text('Hostel',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kTextLight))),
                      Expanded(
                          child: Text('Room',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kTextLight))),
                      Expanded(
                          child: Text('Status',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kTextLight))),
                      Expanded(
                          child: Text('Date',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kTextLight))),
                    ],
                  ),
                ),
                // Rows
                ...docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final ts = d['bookedAt'];
                  final date = ts is Timestamp ? fmtDate(ts.toDate()) : '—';
                  final status = d['status'] ?? 'booked';
                  final statusColor = switch (status.toLowerCase()) {
                    'confirmed' => kGreenAccent,
                    'declined' => const Color(0xFFE53935),
                    _ => const Color(0xFFFF9800),
                  };
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: kBorder, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            d['name'] ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 13, color: kTextDark),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            d['hostel_name'] ?? d['hostelName'] ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 13, color: kTextDark),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            d['room_number'] ?? d['roomNumber'] ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 13, color: kTextDark),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: statusColor.withOpacity(0.3)),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            date,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 13, color: kTextDark),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP HOSTELS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TopHostelsCard extends StatelessWidget {
  const _TopHostelsCard();

  @override
  Widget build(BuildContext context) => DataCard(
        title: 'Top Hostels by Bookings',
        child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('bookings').snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const CardLoading(height: 100);
            }
            final counts = <String, int>{};
            for (final doc in snap.data?.docs ?? []) {
              final name = (doc.data() as Map)['hostel_name'] ??
                  (doc.data() as Map)['hostelName'] ??
                  '—';
              counts[name] = (counts[name] ?? 0) + 1;
            }
            final top = (counts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(5)
                .toList();
            if (top.isEmpty) {
              return const EmptyCard(message: 'No data yet', height: 80);
            }
            return Column(
              children: top
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: kGreenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kTextDark,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: kGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${e.value}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: kGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENT STUDENTS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _RecentStudentsCard extends StatelessWidget {
  const _RecentStudentsCard();

  @override
  Widget build(BuildContext context) => DataCard(
        title: 'Recent Students',
        child: StreamBuilder<QuerySnapshot>(
          stream: db
              .collection('users')
              .where('role', isEqualTo: 'student')
              .orderBy('createdAt', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const CardLoading(height: 100);
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const EmptyCard(
                message: 'No students yet',
                height: 80,
              );
            }
            return Column(
              children: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final name = d['username'] as String? ?? '—';
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: kGreen,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: kTextDark,
                              ),
                            ),
                            Text(
                              d['email'] ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: kTextLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MONTHLY BAR CHART
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart();

  @override
  Widget build(BuildContext context) => DataCard(
        title: '',
        child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('bookings').snapshots(),
          builder: (context, snap) {
            final now = DateTime.now();
            final counts = List<int>.filled(12, 0);
            for (final doc in snap.data?.docs ?? []) {
              final ts = (doc.data() as Map)['bookedAt'];
              if (ts is Timestamp) {
                final dt = ts.toDate();
                if (dt.year == now.year) counts[dt.month - 1]++;
              }
            }
            // Clamp to 1 to prevent division by zero
            final maxVal =
                counts.reduce((a, b) => a > b ? a : b).clamp(1, 999999);
            const months = [
              'J',
              'F',
              'M',
              'A',
              'M',
              'J',
              'J',
              'A',
              'S',
              'O',
              'N',
              'D'
            ];
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 160,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(12, (i) {
                    final frac = counts[i] / maxVal;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (counts[i] > 0)
                              Text(
                                '${counts[i]}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: kTextLight,
                                ),
                              ),
                            const SizedBox(height: 3),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 600),
                              height: 120 * frac + 4,
                              decoration: BoxDecoration(
                                color: i == now.month - 1
                                    ? kGreenAccent
                                    : kGreen.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              months[i],
                              style: const TextStyle(
                                fontSize: 10,
                                color: kTextLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCHOOL HORIZONTAL BAR CHART
// ─────────────────────────────────────────────────────────────────────────────

class _SchoolChart extends StatelessWidget {
  const _SchoolChart();

  @override
  Widget build(BuildContext context) => DataCard(
        title: '',
        child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('bookings').snapshots(),
          builder: (context, snap) {
            final counts = <String, int>{};
            for (final doc in snap.data?.docs ?? []) {
              final s = (doc.data() as Map)['school'] as String? ?? 'Unknown';
              counts[s] = (counts[s] ?? 0) + 1;
            }
            final top = (counts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(5)
                .toList();
            if (top.isEmpty) {
              return const EmptyCard(
                message: 'No school data',
                height: 80,
              );
            }
            // Clamp to 1 to prevent division by zero
            final maxVal = top
                .map((e) => e.value)
                .reduce((a, b) => a > b ? a : b)
                .clamp(1, 999999);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: top
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(
                                e.key,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextLight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: e.value / maxVal,
                                  minHeight: 10,
                                  backgroundColor: kBorder,
                                  valueColor:
                                      const AlwaysStoppedAnimation(kGreen),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${e.value}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: kTextDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
      );
}
