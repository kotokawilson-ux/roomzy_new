import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../utils/activity_logger.dart';
import '../../../../constants/admin_theme.dart';
import '../../../../utils/admin_helpers.dart';
import '../widgets/shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BOOKINGS PANE
// ─────────────────────────────────────────────────────────────────────────────

class BookingsPane extends StatefulWidget {
  const BookingsPane({super.key});

  @override
  State<BookingsPane> createState() => _BookingsPaneState();
}

class _BookingsPaneState extends State<BookingsPane> {
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FilterBar(
            current: _statusFilter,
            onChanged: (v) => setState(() => _statusFilter = v),
          ),
          Expanded(
            child: _BookingsTable(statusFilter: _statusFilter),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER BAR
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  static const _filters = ['all', 'booked', 'confirmed', 'declined'];

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Wrap(
          spacing: 8,
          children: _filters.map((f) {
            final selected = f == current;
            return ChoiceChip(
              label: Text(
                f[0].toUpperCase() + f.substring(1),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : kTextLight,
                ),
              ),
              selected: selected,
              selectedColor: kGreen,
              backgroundColor: kSurfaceAlt,
              side: BorderSide(color: selected ? kGreen : kBorder),
              onSelected: (_) => onChanged(f),
            );
          }).toList(),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BOOKINGS TABLE
// ─────────────────────────────────────────────────────────────────────────────

class _BookingsTable extends StatelessWidget {
  const _BookingsTable({required this.statusFilter});

  final String statusFilter;

  @override
  Widget build(BuildContext context) {
    Query query =
        db.collection('bookings').orderBy('bookedAt', descending: true);

    if (statusFilter != 'all') {
      query = query.where('status', isEqualTo: statusFilter);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kGreen));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: EmptyCard(message: 'No bookings found', height: 120),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: DataCard(
            title: 'All Bookings',
            child: Column(
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
                        flex: 2,
                        child: Text('Student',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kTextLight)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('Hostel',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kTextLight)),
                      ),
                      Expanded(
                        child: Text('Room',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kTextLight)),
                      ),
                      Expanded(
                        child: Text('Status',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kTextLight)),
                      ),
                      Expanded(
                        child: Text('Date',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kTextLight)),
                      ),
                      SizedBox(width: 80),
                    ],
                  ),
                ),
                // Rows
                ...docs.map((doc) => _BookingRow(doc: doc)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOOKING ROW
// ─────────────────────────────────────────────────────────────────────────────

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.doc});

  final QueryDocumentSnapshot doc;

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = d['bookedAt'];
    final date = ts is Timestamp ? fmtDate(ts.toDate()) : '—';
    final status = (d['status'] ?? 'booked') as String;
    final statusColor = switch (status.toLowerCase()) {
      'confirmed' => kGreenAccent,
      'declined' => const Color(0xFFE53935),
      _ => const Color(0xFFFF9800),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d['name'] ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      color: kTextDark,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  d['email'] ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kTextLight),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              d['hostel_name'] ?? d['hostelName'] ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: kTextDark),
            ),
          ),
          Expanded(
            child: Text(
              d['room_number'] ?? d['roomNumber'] ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: kTextDark),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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
              style: const TextStyle(fontSize: 12, color: kTextLight),
            ),
          ),
          SizedBox(
            width: 80,
            child: _ActionMenu(docId: doc.id, currentStatus: status),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION MENU (confirm / decline)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.docId, required this.currentStatus});

  final String docId;
  final String currentStatus;

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    try {
      await db.collection('bookings').doc(docId).update({'status': newStatus});
      await ActivityLogger.log(
        action: 'Updated Booking',
        details: 'Booking ID: $docId, New Status: $newStatus',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18, color: kTextLight),
        onSelected: (v) => _updateStatus(context, v),
        itemBuilder: (_) => [
          if (currentStatus != 'confirmed')
            const PopupMenuItem(
              value: 'confirmed',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: kGreenAccent),
                  SizedBox(width: 8),
                  Text('Confirm', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          if (currentStatus != 'declined')
            const PopupMenuItem(
              value: 'declined',
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined,
                      size: 16, color: Color(0xFFE53935)),
                  SizedBox(width: 8),
                  Text('Decline', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          if (currentStatus != 'booked')
            const PopupMenuItem(
              value: 'booked',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 16, color: kTextLight),
                  SizedBox(width: 8),
                  Text('Reset to Booked', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
        ],
      );
}
