import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../constants/admin_theme.dart';
import '../../../utils/admin_helpers.dart';
import 'shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 170,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 14),
            Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: kTextDark,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: kTextLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARDS ROW — live snapshot streams for each collection
// ─────────────────────────────────────────────────────────────────────────────

class StatCardsRow extends StatelessWidget {
  const StatCardsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final collections = ['bookings', 'hostels', 'rooms', 'landlords'];
    final labels = ['Bookings', 'Hostels', 'Rooms', 'Landlords'];
    final icons = [
      Icons.receipt_long_rounded,
      Icons.apartment_rounded,
      Icons.bed_rounded,
      Icons.person_4_rounded,
    ];
    final colors = [
      const Color(0xFFE91E63),
      const Color(0xFF9C27B0),
      kGreenAccent,
      const Color(0xFFFF9800),
    ];

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('users')
          .where('role', isEqualTo: 'student')
          .snapshots(),
      builder: (context, userSnap) {
        final students = userSnap.data?.docs.length ?? 0;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            StatCard(
              label: 'Students',
              value: students,
              icon: Icons.school_rounded,
              color: const Color(0xFF2196F3),
            ),
            for (int i = 0; i < collections.length; i++)
              StreamBuilder<QuerySnapshot>(
                stream: db.collection(collections[i]).snapshots(),
                builder: (ctx, snap) => StatCard(
                  label: labels[i],
                  value: snap.data?.docs.length ?? 0,
                  icon: icons[i],
                  color: colors[i],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK STAT WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class QuickStat extends StatelessWidget {
  const QuickStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: kTextLight),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      color: kTextDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK STATS ROW — live streams for today's bookings, available rooms, schools
// ─────────────────────────────────────────────────────────────────────────────

class QuickStatsRow extends StatelessWidget {
  const QuickStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('bookings').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final todayCount = docs.where((d) {
          final ts = (d.data() as Map)['bookedAt'];
          if (ts == null) return false;
          return (ts as Timestamp).toDate().isAfter(todayStart);
        }).length;

        return StreamBuilder<QuerySnapshot>(
          stream: db
              .collection('rooms')
              .where('available', isEqualTo: true)
              .snapshots(),
          builder: (context, roomSnap) {
            final available = roomSnap.data?.docs.length ?? 0;

            return StreamBuilder<QuerySnapshot>(
              stream: db.collection('schools').snapshots(),
              builder: (context, schoolSnap) {
                final schools = schoolSnap.data?.docs.length ?? 0;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    QuickStat(
                      label: "Today's Bookings",
                      value: '$todayCount new',
                      icon: Icons.calendar_today_rounded,
                      color: const Color(0xFF2196F3),
                    ),
                    QuickStat(
                      label: 'Active Schools',
                      value: '$schools schools',
                      icon: Icons.school_rounded,
                      color: const Color(0xFF9C27B0),
                    ),
                    QuickStat(
                      label: 'Available Rooms',
                      value: '$available rooms',
                      icon: Icons.door_front_door_rounded,
                      color: kGreenAccent,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
