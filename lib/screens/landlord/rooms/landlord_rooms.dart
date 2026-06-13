import 'package:flutter/material.dart';

import '../../../services/landlord_service.dart';
import '../../../models/models.dart';
import 'room_form.dart';

// ── Colour tokens ─────────────────────────────────────────────
class _C {
  static const pageBg = Color(0xFFF5F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF9FAFB);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF1F2937);
  static const textLight = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const green = Color(0xFF2D6A4F);
  static const greenAccent = Color(0xFF40916C);
  static const greenLight = Color(0xFFD8F3DC);
  static const greenFaint = Color(0xFFF0FAF3);
  static const red = Color(0xFFEF4444);
  static const redLight = Color(0xFFFEE2E2);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFEF3C7);
  static const blue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFFDBEAFE);
}

// ─────────────────────────────────────────────────────────────
// LANDLORD ROOMS
// ─────────────────────────────────────────────────────────────
class LandlordRooms extends StatefulWidget {
  const LandlordRooms({
    super.key,
    required this.landlordId,
    required this.service,
    this.initialHostel,
    this.onBack,
  });

  final String landlordId;
  final LandlordService service;
  final Hostel? initialHostel;
  final VoidCallback? onBack;

  @override
  State<LandlordRooms> createState() => _LandlordRoomsState();
}

class _LandlordRoomsState extends State<LandlordRooms> {
  String _search = '';
  late String _filterHostel;
  List<Hostel> _hostels = [];

  @override
  void initState() {
    super.initState();
    _filterHostel = widget.initialHostel?.id ?? 'all';
    _loadHostels();
  }

  Future<void> _loadHostels() async {
    final hostels = await widget.service.getHostels(widget.landlordId);
    if (mounted) setState(() => _hostels = hostels);
  }

  void _openForm({Room? room, String? preselectedHostelId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoomForm(
        landlordId: widget.landlordId,
        service: widget.service,
        hostels: _hostels,
        room: room,
        preselectedHostelId: preselectedHostelId,
      ),
    ));
  }

  Future<void> _delete(Room room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(roomNumber: room.roomNumber),
    );
    if (confirm != true) return;

    final result = await widget.service.deleteRoom(room.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? 'Room ${room.roomNumber} deleted'
          : result.error ?? 'Delete failed'),
      backgroundColor: result.success ? _C.green : _C.red,
    ));
  }

  Future<void> _toggleAvailability(Room room) async {
    await widget.service.toggleRoomAvailability(room.id, !room.available);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: Column(
        children: [
          // ── Back bar ──────────────────────────────────────
          if (widget.onBack != null)
            _BackBar(
              hostelName: widget.initialHostel?.hostelName ?? 'Rooms',
              onBack: widget.onBack!,
            ),

          // ── Toolbar ──────────────────────────────────────
          _Toolbar(
            hostels: _hostels,
            selectedHostelId: _filterHostel,
            onSearch: (v) => setState(() => _search = v),
            onHostelFilter: (v) => setState(() => _filterHostel = v),
            onAdd: () => _openForm(
              preselectedHostelId:
                  _filterHostel == 'all' ? null : _filterHostel,
            ),
          ),

          // ── Grid ─────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Room>>(
              stream: widget.service.streamAllRooms(widget.landlordId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _C.green),
                  );
                }
                if (snap.hasError) {
                  return _ErrorState(error: snap.error.toString());
                }

                final all = snap.data ?? [];

                var filtered = _filterHostel == 'all'
                    ? all
                    : all.where((r) => r.hostelId == _filterHostel).toList();

                if (_search.isNotEmpty) {
                  final q = _search.toLowerCase();
                  filtered = filtered
                      .where((r) =>
                          r.roomNumber.toLowerCase().contains(q) ||
                          r.type.toLowerCase().contains(q) ||
                          r.hostelName.toLowerCase().contains(q))
                      .toList();
                }

                if (all.isEmpty) {
                  return _EmptyState(onAdd: () => _openForm());
                }
                if (filtered.isEmpty) {
                  return _NoResultsState(query: _search);
                }

                return RefreshIndicator(
                  color: _C.green,
                  onRefresh: () async => _loadHostels(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: _ResponsiveGrid(
                      itemCount: filtered.length,
                      itemBuilder: (i) => _RoomCard(
                        room: filtered[i],
                        onEdit: () => _openForm(room: filtered[i]),
                        onDelete: () => _delete(filtered[i]),
                        onToggle: () => _toggleAvailability(filtered[i]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// RESPONSIVE GRID  (mirrors admin _ResponsiveGrid)
// phone <560 → 1 col | tablet <900 → 2 cols | desktop → 3 cols
// ─────────────────────────────────────────────────────────────
class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = w < 560 ? 1 : (w < 900 ? 2 : 3);
      const gap = 16.0;
      final cardW = (w - gap * (cols - 1)) / cols;

      final rows = <Widget>[];
      for (var i = 0; i < itemCount; i += cols) {
        final children = <Widget>[];
        for (var j = 0; j < cols; j++) {
          if (j > 0) children.add(const SizedBox(width: gap));
          if (i + j < itemCount) {
            children.add(SizedBox(width: cardW, child: itemBuilder(i + j)));
          } else {
            children.add(SizedBox(width: cardW));
          }
        }
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ));
      }

      return Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) const SizedBox(height: gap),
          ],
          const SizedBox(height: 20),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────
// BACK BAR
// ─────────────────────────────────────────────────────────────
class _BackBar extends StatelessWidget {
  const _BackBar({required this.hostelName, required this.onBack});
  final String hostelName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: _C.greenFaint,
          border: Border(bottom: BorderSide(color: _C.greenLight)),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(8),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, color: _C.green, size: 20),
                  Text('Back to Hostels',
                      style: TextStyle(
                          fontSize: 13,
                          color: _C.green,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded,
                size: 14, color: _C.textMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(hostelName,
                  style: const TextStyle(fontSize: 13, color: _C.textMuted),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// TOOLBAR
// ─────────────────────────────────────────────────────────────
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.hostels,
    required this.selectedHostelId,
    required this.onSearch,
    required this.onHostelFilter,
    required this.onAdd,
  });

  final List<Hostel> hostels;
  final String selectedHostelId;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onHostelFilter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: _C.pageBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.border),
                  ),
                  child: TextField(
                    onChanged: onSearch,
                    style: const TextStyle(fontSize: 13, color: _C.textDark),
                    decoration: const InputDecoration(
                      hintText: 'Search rooms...',
                      hintStyle: TextStyle(fontSize: 13, color: _C.textMuted),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 18, color: _C.textMuted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Room',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          if (hostels.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'All Hostels',
                    selected: selectedHostelId == 'all',
                    onTap: () => onHostelFilter('all'),
                  ),
                  ...hostels.map((h) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _FilterChip(
                          label: h.hostelName,
                          selected: selectedHostelId == h.id,
                          onTap: () => onHostelFilter(h.id),
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? _C.green : _C.pageBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _C.green : _C.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : _C.textLight)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// ROOM CARD  (mirrors admin _RoomCard exactly)
// ─────────────────────────────────────────────────────────────
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final Room room;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // With this:
    final available = room.available;
    final slotsLeft = room.slotsLeft;
    final isBooked = !available || slotsLeft == 0;

    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Room image ────────────────────────────────
          if (room.image != null && room.image!.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.network(
                room.image!,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Title ──────────────────────────────
                Row(children: [
                  const Icon(Icons.bed_rounded, color: _C.green, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Room ${room.roomNumber}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _C.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Divider(height: 1, color: _C.border),
                const SizedBox(height: 8),

                // ── Info rows ──────────────────────────
                _InfoRow(label: 'Hostel', value: room.hostelName),
                _InfoRow(label: 'Type', value: room.type),
                _InfoRow(label: 'Capacity', value: '${room.capacity}'),
// ── Slot usage bar ──────────────────────────────────────
                Builder(builder: (_) {
                  final booked = room.booked;
                  final cap = room.capacity;
                  final slotsLeft = (cap - booked).clamp(0, cap);
                  final progress =
                      cap > 0 ? (booked / cap).clamp(0.0, 1.0) : 0.0;
                  final isFull = booked >= cap;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            SizedBox(
                              width: 72,
                              child: Text('Slots:',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _C.textLight)),
                            ),
                            Expanded(
                              child: Text(
                                isFull
                                    ? 'Fully booked ($booked/$cap)'
                                    : '$booked of $cap slot${cap == 1 ? '' : 's'} booked · $slotsLeft left',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isFull ? _C.red : _C.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 72),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isFull
                                      ? _C.red
                                      : progress > 0.6
                                          ? _C.amber
                                          : _C.green,
                                ),
                              ),
                            ),
                          ),
                        ]),
                  );
                }),
                _InfoRow(
                    label: 'Price',
                    value: 'GHS ${room.price.toStringAsFixed(2)}'),
                _InfoRow(
                    label: 'Booked', value: '${room.booked}/${room.capacity}'),

                // ── Availability badge ──────────────────
                _BadgeRow(
                  label: 'Availability',
                  badgeLabel: available ? 'Available' : 'Unavailable',
                  color: available ? Colors.green : Colors.red,
                ),

                // ── Booking status badge ────────────────
                // With this:
                _BadgeRow(
                  label: 'Booking',
                  badgeLabel: !available
                      ? 'Unavailable'
                      : slotsLeft == 0
                          ? 'Fully Booked'
                          : 'Has Space',
                  color: !available
                      ? Colors.red
                      : slotsLeft == 0
                          ? Colors.orange
                          : Colors.blue,
                ),

                const SizedBox(height: 12),

                // ── Action buttons ──────────────────────
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    // Availability toggle
                    _CardBtn(
                      icon: available
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      label: available ? 'Disable' : 'Enable',
                      color: available ? _C.amber : _C.green,
                      onTap: onToggle,
                    ),
                    _CardBtn(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      color: Colors.orange,
                      onTap: onEdit,
                    ),
                    _CardBtn(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS  (mirrors admin _InfoRow / _BadgeRow)
// ─────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text('$label:',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _C.textLight)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 12, color: _C.textDark),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.label,
    required this.badgeLabel,
    required this.color,
  });
  final String label, badgeLabel;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          SizedBox(
            width: 72,
            child: Text('$label:',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textLight)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(badgeLabel,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ),
        ]),
      );
}

class _CardBtn extends StatelessWidget {
  const _CardBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// EMPTY / ERROR STATES
// ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  color: _C.greenFaint,
                  borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.bed_rounded, size: 40, color: _C.green),
            ),
            const SizedBox(height: 16),
            const Text('No rooms yet',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _C.textDark)),
            const SizedBox(height: 6),
            const Text('Add rooms to your hostels to start getting bookings.',
                style: TextStyle(fontSize: 13, color: _C.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Room'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: _C.textMuted),
            const SizedBox(height: 12),
            Text('No results for "$query"',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _C.textDark)),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: _C.textMuted),
            const SizedBox(height: 12),
            const Text('Failed to load rooms',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _C.textDark)),
            const SizedBox(height: 4),
            Text(error,
                style: const TextStyle(fontSize: 11, color: _C.textMuted),
                textAlign: TextAlign.center),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// DELETE CONFIRM DIALOG
// ─────────────────────────────────────────────────────────────
// ignore: unused_element
class _ConfirmDeleteDialog extends StatelessWidget {
  const _ConfirmDeleteDialog({required this.roomNumber});
  final String roomNumber;

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Room',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark)),
        content: Text(
          'Are you sure you want to delete Room $roomNumber? This cannot be undone.',
          style:
              const TextStyle(fontSize: 13, color: _C.textLight, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _C.textLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      );
}
