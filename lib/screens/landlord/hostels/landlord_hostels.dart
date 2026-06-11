// lib/screens/landlord/hostels/landlord_hostels.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Landlord Hostels Page
// Grid layout + inline rooms view (matches admin HostelsPane).
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../services/landlord_service.dart';
import '../../../models/models.dart';
import 'hostel_form.dart';
import '../rooms/landlord_rooms.dart';

// ── Colour tokens ─────────────────────────────────────────────
class _C {
  static const pageBg = Color(0xFFF5F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF1F2937);
  static const textLight = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const green = Color(0xFF2D6A4F);
  static const greenLight = Color(0xFFD8F3DC);
  static const greenFaint = Color(0xFFF0FAF3);
  static const red = Color(0xFFEF4444);
  static const redLight = Color(0xFFFEE2E2);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFEF3C7);
  static const blue = Color(0xFF3B82F6);
  static const blueFaint = Color(0xFFEFF6FF);
}

// ─────────────────────────────────────────────────────────────
// LANDLORD HOSTELS
// ─────────────────────────────────────────────────────────────
class LandlordHostels extends StatefulWidget {
  const LandlordHostels({
    super.key,
    required this.landlordId,
    required this.service,
  });

  final String landlordId;
  final LandlordService service;

  @override
  State<LandlordHostels> createState() => _LandlordHostelsState();
}

class _LandlordHostelsState extends State<LandlordHostels> {
  String _search = '';
  Hostel? _viewingHostel; // non-null → show inline rooms view

  // ── Navigation ───────────────────────────────────────────
  void _openForm({Hostel? hostel}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HostelForm(
        landlordId: widget.landlordId,
        service: widget.service,
        hostel: hostel,
      ),
    ));
  }

  // ── Delete ───────────────────────────────────────────────
  Future<void> _delete(Hostel hostel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(name: hostel.hostelName),
    );
    if (confirm != true || !mounted) return;

    final result = await widget.service.deleteHostel(hostel.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? '${hostel.hostelName} deleted'
          : result.error ?? 'Delete failed'),
      backgroundColor: result.success ? _C.green : _C.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // ── Inline rooms view (mirrors admin _RoomsView pattern) ──
    if (_viewingHostel != null) {
      return LandlordRooms(
        landlordId: widget.landlordId,
        service: widget.service,
        initialHostel: _viewingHostel,
        onBack: () => setState(() => _viewingHostel = null),
      );
    }

    // ── Hostels grid view ─────────────────────────────────────
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: Column(
        children: [
          _Toolbar(
            onSearch: (v) => setState(() => _search = v),
            onAdd: () => _openForm(),
          ),
          Expanded(
            child: StreamBuilder<List<Hostel>>(
              stream: widget.service.streamHostels(widget.landlordId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _C.green));
                }
                if (snap.hasError) {
                  return _ErrorState(error: snap.error.toString());
                }

                final all = snap.data ?? [];
                final q = _search.toLowerCase();
                final filtered = _search.isEmpty
                    ? all
                    : all
                        .where((h) =>
                            h.hostelName.toLowerCase().contains(q) ||
                            (h.town ?? '').toLowerCase().contains(q) ||
                            h.hostelCode.toLowerCase().contains(q))
                        .toList();

                if (all.isEmpty) return const _EmptyState();
                if (filtered.isEmpty) return _NoResultsState(query: _search);

                return RefreshIndicator(
                  color: _C.green,
                  onRefresh: () async {},
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: _ResponsiveGrid(
                      itemCount: filtered.length,
                      itemBuilder: (i) => _HostelCard(
                        hostel: filtered[i],
                        onEdit: () => _openForm(hostel: filtered[i]),
                        onDelete: () => _delete(filtered[i]),
                        // switch to inline rooms view — same as admin
                        onViewRooms: () =>
                            setState(() => _viewingHostel = filtered[i]),
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
            children.add(SizedBox(width: cardW)); // empty spacer
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
// TOOLBAR
// ─────────────────────────────────────────────────────────────
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onSearch, required this.onAdd});
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(children: [
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
                hintText: 'Search hostels...',
                hintStyle: TextStyle(fontSize: 13, color: _C.textMuted),
                prefixIcon:
                    Icon(Icons.search_rounded, size: 18, color: _C.textMuted),
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
          label: const Text('Add Hostel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.green,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// HOSTEL CARD
// ─────────────────────────────────────────────────────────────
class _HostelCard extends StatelessWidget {
  const _HostelCard({
    required this.hostel,
    required this.onEdit,
    required this.onDelete,
    required this.onViewRooms,
  });

  final Hostel hostel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewRooms;

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
          // ── Cover image ───────────────────────────────
          if (hostel.image != null && hostel.image!.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                hostel.image!,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          // ── Header row ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _C.greenFaint,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.greenLight),
                  ),
                  child: const Icon(Icons.apartment_rounded,
                      color: _C.green, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hostel.hostelName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _C.textDark),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        const Icon(Icons.tag_rounded,
                            size: 11, color: _C.textMuted),
                        const SizedBox(width: 2),
                        Text(hostel.hostelCode,
                            style: const TextStyle(
                                fontSize: 11, color: _C.textMuted)),
                        if (hostel.town != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.location_on_rounded,
                              size: 11, color: _C.textMuted),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(hostel.town!,
                                style: const TextStyle(
                                    fontSize: 11, color: _C.textMuted),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _IconBtn(
                    icon: Icons.edit_outlined,
                    color: _C.green,
                    bg: _C.greenFaint,
                    onTap: onEdit,
                    tooltip: 'Edit Hostel',
                  ),
                  const SizedBox(width: 6),
                  _IconBtn(
                    icon: Icons.delete_outline_rounded,
                    color: _C.red,
                    bg: _C.redLight,
                    onTap: onDelete,
                    tooltip: 'Delete Hostel',
                  ),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: _C.border),

          // ── Stats chips ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  icon: Icons.bed_rounded,
                  label: '${hostel.roomsAvailable} rooms',
                  color: _C.green,
                  bg: _C.greenFaint,
                ),
                _Chip(
                  icon: Icons.schedule_rounded,
                  label: hostel.durationType,
                  color: _C.amber,
                  bg: _C.amberLight,
                ),
                if (hostel.schoolShortName != null || hostel.schoolName != null)
                  _Chip(
                    icon: Icons.school_rounded,
                    label: hostel.schoolShortName ?? hostel.schoolName ?? '',
                    color: _C.textLight,
                    bg: _C.border,
                  ),
                if (hostel.priceRange != null && hostel.priceRange!.isNotEmpty)
                  _Chip(
                    icon: Icons.payments_outlined,
                    label: hostel.priceRange!,
                    color: _C.blue,
                    bg: _C.blueFaint,
                  ),
              ],
            ),
          ),

          // ── Description ───────────────────────────────
          if (hostel.description != null && hostel.description!.isNotEmpty) ...[
            const Divider(height: 1, color: _C.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                hostel.description!,
                style: const TextStyle(
                    fontSize: 12, color: _C.textLight, height: 1.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const Divider(height: 1, color: _C.border),

          // ── View Rooms button ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewRooms,
                icon: const Icon(Icons.door_front_door_outlined,
                    size: 15, color: _C.green),
                label: const Text('View Rooms',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _C.green)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _C.greenLight),
                  backgroundColor: _C.greenFaint,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SMALL SHARED WIDGETS
// ─────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.bg,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final Color color, bg;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });
  final IconData icon;
  final String label;
  final Color color, bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
// EMPTY / ERROR STATES
// ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                color: _C.greenFaint, borderRadius: BorderRadius.circular(20)),
            child:
                const Icon(Icons.apartment_rounded, size: 40, color: _C.green),
          ),
          const SizedBox(height: 16),
          const Text('No hostels yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _C.textDark)),
          const SizedBox(height: 6),
          const Text('Tap "Add Hostel" to list your first property.',
              style: TextStyle(fontSize: 13, color: _C.textMuted)),
        ]),
      );
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded, size: 48, color: _C.textMuted),
          const SizedBox(height: 12),
          Text('No results for "$query"',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _C.textDark)),
          const SizedBox(height: 4),
          const Text('Try a different name, town or code.',
              style: TextStyle(fontSize: 12, color: _C.textMuted)),
        ]),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: _C.textMuted),
          const SizedBox(height: 12),
          const Text('Failed to load hostels',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _C.textDark)),
          const SizedBox(height: 4),
          Text(error,
              style: const TextStyle(fontSize: 11, color: _C.textMuted),
              textAlign: TextAlign.center),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
// CONFIRM DELETE DIALOG
// ─────────────────────────────────────────────────────────────
class _ConfirmDeleteDialog extends StatelessWidget {
  const _ConfirmDeleteDialog({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Hostel',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark)),
        content: RichText(
          text: TextSpan(
            style:
                const TextStyle(fontSize: 13, color: _C.textLight, height: 1.5),
            children: [
              const TextSpan(text: 'Are you sure you want to delete '),
              TextSpan(
                  text: name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _C.textDark)),
              const TextSpan(
                  text:
                      '? This will also delete all its rooms. This cannot be undone.'),
            ],
          ),
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
