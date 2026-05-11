import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../utils/admin_helpers.dart';
import '../widgets/dialog_widgets.dart';
import '../widgets/form_widgets.dart';
import '../widgets/shared_widgets.dart';
import '../../../../utils/activity_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ROOMZYFIND COLOUR TOKENS  — 100 % green, zero blue
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const primary = Color(0xFF1B4332);
  static const primaryHover = Color(0xFF2D6A4F);
  static const primaryLight = Color(0xFFD8F3DC);
  static const primaryFaint = Color(0xFFF0FAF3);

  static const pageBg = Color(0xFFF2F4F0);
  static const surface = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);

  static const amber = Color(0xFFD97706);
  static const amberBg = Color(0xFFFEF3C7);
  static const red = Color(0xFFDC2626);
  static const redBg = Color(0xFFFEE2E2);

  static const border = Color(0xFFE5E7EB);
}

// ─────────────────────────────────────────────────────────────────────────────
// FACILITIES PANE
// ─────────────────────────────────────────────────────────────────────────────
class FacilitiesPane extends StatefulWidget {
  const FacilitiesPane({super.key});
  @override
  State<FacilitiesPane> createState() => _FacilitiesPaneState();
}

class _FacilitiesPaneState extends State<FacilitiesPane> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          _GreenHeader(
            onAdd: () => showDialog(
              context: context,
              builder: (_) => const _FacilityDialog(),
            ),
          ),

          // ── Search bar — OUTSIDE StreamBuilder so it never loses focus ──────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: _SearchBar(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  db.collection('hostels').orderBy('hostel_name').snapshots(),
              builder: (_, hostelSnap) {
                if (hostelSnap.connectionState == ConnectionState.waiting) {
                  return const _Loader();
                }
                final hostels = hostelSnap.data?.docs ?? [];

                return StreamBuilder<QuerySnapshot>(
                  stream: db
                      .collection('facilities')
                      .orderBy('facility_name')
                      .snapshots(),
                  builder: (_, facSnap) {
                    if (facSnap.connectionState == ConnectionState.waiting) {
                      return const _Loader();
                    }

                    final allFacs = facSnap.data?.docs ?? [];

                    // Group facilities by hostel_id
                    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
                    for (final f in allFacs) {
                      final d = f.data() as Map<String, dynamic>;
                      final hid = (d['hostel_id'] as String?) ?? '__none__';
                      grouped.putIfAbsent(hid, () => []).add(f);
                    }

                    final q = _search;
                    final visibleHostels = hostels.where((h) {
                      final hd = h.data() as Map<String, dynamic>;
                      final hn =
                          (hd['hostel_name'] ?? '').toString().toLowerCase();
                      final hc =
                          (hd['hostel_code'] ?? '').toString().toLowerCase();
                      if (q.isEmpty) return true;
                      if (hn.contains(q) || hc.contains(q)) return true;
                      return (grouped[h.id] ?? []).any((f) {
                        final fd = f.data() as Map<String, dynamic>;
                        return (fd['facility_name'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(q);
                      });
                    }).toList();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                      children: [
                        _StatsRow(
                          hostelCount: hostels.length,
                          facilityCount: allFacs.length,
                        ),
                        const SizedBox(height: 18),
                        const _Label('All hostels'),
                        const SizedBox(height: 12),
                        if (visibleHostels.isEmpty)
                          const _EmptyState()
                        else
                          ...visibleHostels.map((hDoc) {
                            final hd = hDoc.data() as Map<String, dynamic>;
                            final hFacs = (grouped[hDoc.id] ?? []).where((f) {
                              if (q.isEmpty) return true;
                              final fd = f.data() as Map<String, dynamic>;
                              final hn = (hd['hostel_name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              return (fd['facility_name'] ?? '')
                                      .toString()
                                      .toLowerCase()
                                      .contains(q) ||
                                  hn.contains(q);
                            }).toList();

                            return _HostelGroup(
                              hostelDoc: hDoc,
                              facilities: hFacs,
                              onAddFacility: () => showDialog(
                                context: context,
                                builder: (_) =>
                                    _FacilityDialog(preselectedHostel: hDoc),
                              ),
                            );
                          }),
                      ],
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
}

// ─────────────────────────────────────────────────────────────────────────────
// GREEN HEADER
// ─────────────────────────────────────────────────────────────────────────────
class _GreenHeader extends StatelessWidget {
  const _GreenHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.primary,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          const Text(
            'Facilities',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _C.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH BAR
// ─────────────────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13, color: _C.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search facilities or hostels...',
          hintStyle: const TextStyle(color: _C.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: _C.textMuted, size: 19),
          filled: true,
          fillColor: _C.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _C.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _C.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _C.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.hostelCount, required this.facilityCount});
  final int hostelCount;
  final int facilityCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(value: hostelCount, label: 'Hostels'),
        const SizedBox(width: 12),
        _StatCard(value: facilityCount, label: 'Facilities'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border, width: 0.5),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: _C.primary,
                  height: 1),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: _C.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            color: _C.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// HOSTEL GROUP CARD
// ─────────────────────────────────────────────────────────────────────────────
class _HostelGroup extends StatelessWidget {
  const _HostelGroup({
    required this.hostelDoc,
    required this.facilities,
    required this.onAddFacility,
  });
  final QueryDocumentSnapshot hostelDoc;
  final List<QueryDocumentSnapshot> facilities;
  final VoidCallback onAddFacility;

  @override
  Widget build(BuildContext context) {
    final hd = hostelDoc.data() as Map<String, dynamic>;
    final hostelName = (hd['hostel_name'] as String?) ?? '—';
    final hostelCode = (hd['hostel_code'] as String?) ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: _C.primary,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.apartment_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hostelName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _C.textPrimary)),
                      const SizedBox(height: 1),
                      Text(hostelCode.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _C.amber,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: _C.primaryLight,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${facilities.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _C.primary)),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onAddFacility,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _C.primary, width: 1.5)),
                    child: const Icon(Icons.add, size: 16, color: _C.primary),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, thickness: 0.5, color: _C.border),

          // Chips grid
          if (facilities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add_circle_outline, size: 14, color: _C.textMuted),
                  SizedBox(width: 5),
                  Text('No facilities yet — tap + to add one',
                      style: TextStyle(fontSize: 12, color: _C.textMuted)),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(10),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: facilities.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.8,
                ),
                itemBuilder: (_, i) => _FacilityChip(doc: facilities[i]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FACILITY CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _FacilityChip extends StatelessWidget {
  const _FacilityChip({required this.doc});
  final QueryDocumentSnapshot doc;

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('wifi') || n.contains('wi-fi') || n.contains('internet'))
      return Icons.wifi_rounded;
    if (n.contains('laundry') || n.contains('wash'))
      return Icons.local_laundry_service_rounded;
    if (n.contains('kitchen') || n.contains('cook'))
      return Icons.kitchen_rounded;
    if (n.contains('secur') || n.contains('guard') || n.contains('cctv'))
      return Icons.security_rounded;
    if (n.contains('study') || n.contains('library'))
      return Icons.menu_book_rounded;
    if (n.contains('common') || n.contains('lounge') || n.contains('rec'))
      return Icons.weekend_rounded;
    if (n.contains('park')) return Icons.local_parking_rounded;
    if (n.contains('gym') || n.contains('fitness'))
      return Icons.fitness_center_rounded;
    if (n.contains('pool') || n.contains('swim')) return Icons.pool_rounded;
    if (n.contains('power') || n.contains('electric') || n.contains('gen'))
      return Icons.electrical_services_rounded;
    if (n.contains('water')) return Icons.water_drop_rounded;
    if (n.contains('air') || n.contains('ac') || n.contains('cooling'))
      return Icons.air_rounded;
    if (n.contains('tv') || n.contains('entertainment'))
      return Icons.tv_rounded;
    if (n.contains('bus') || n.contains('shuttle') || n.contains('transport'))
      return Icons.directions_bus_rounded;
    if (n.contains('canter') || n.contains('cafet') || n.contains('dining'))
      return Icons.restaurant_rounded;
    return Icons.star_outline_rounded;
  }

  void _showSheet(BuildContext context, String name) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _FacilityActionSheet(doc: doc, name: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final name = (d['facility_name'] as String?) ?? '—';

    return GestureDetector(
      onLongPress: () => _showSheet(context, name),
      child: Container(
        decoration: BoxDecoration(
          color: _C.primaryFaint,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _C.primaryLight, width: 0.8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(_iconFor(name), size: 13, color: _C.primaryHover),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _C.primary,
                    letterSpacing: 0.1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => _showSheet(context, name),
              child: const Icon(Icons.more_vert, size: 13, color: _C.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// ACTION BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _FacilityActionSheet extends StatelessWidget {
  const _FacilityActionSheet({required this.doc, required this.name});
  final QueryDocumentSnapshot doc;
  final String name;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: _C.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _C.textPrimary)),
            const SizedBox(height: 4),
            const Text('Choose an action',
                style: TextStyle(fontSize: 12, color: _C.textMuted)),
            const SizedBox(height: 14),
            Divider(height: 1, color: _C.border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: _C.amberBg, borderRadius: BorderRadius.circular(9)),
                child:
                    const Icon(Icons.edit_outlined, size: 17, color: _C.amber),
              ),
              title: const Text('Edit facility',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                    context: context,
                    builder: (_) => _FacilityDialog(doc: doc));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: _C.redBg, borderRadius: BorderRadius.circular(9)),
                child:
                    const Icon(Icons.delete_outline, size: 17, color: _C.red),
              ),
              title: const Text('Delete facility',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.red)),
              onTap: () async {
                // 1️⃣ Close the bottom sheet FIRST and keep the scaffold context
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);

                // 2️⃣ Show confirmation dialog — only proceed if user confirms
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    title: const Text('Confirm Delete',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    content:
                        Text('Delete "$name"? This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style:
                            ElevatedButton.styleFrom(backgroundColor: _C.red),
                        child: const Text('Delete',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (confirmed != true)
                  return; // 3️⃣ User cancelled — stop here, no log

                // 4️⃣ Actually delete
                try {
                  final hostelName =
                      (doc.data() as Map<String, dynamic>)['hostel_name'] ??
                          'Unknown';

                  await db.collection('facilities').doc(doc.id).delete();

                  // 5️⃣ Log ONLY after successful deletion
                  await ActivityLogger.log(
                    action: 'Deleted Facility',
                    details: 'Facility: $name, Hostel: $hostelName',
                  );

                  // 6️⃣ Show success snackbar
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('"$name" deleted successfully'),
                      backgroundColor: _C.primary,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  // 7️⃣ Show error snackbar if something goes wrong
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Failed to delete. Please try again.'),
                      backgroundColor: _C.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
                color: _C.primaryLight,
                borderRadius: BorderRadius.circular(14)),
            child:
                const Icon(Icons.domain_outlined, size: 28, color: _C.primary),
          ),
          const SizedBox(height: 14),
          const Text('No facilities found',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _C.textPrimary)),
          const SizedBox(height: 5),
          const Text(
            'Try a different search or add a new facility',
            style: TextStyle(fontSize: 12, color: _C.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADER
// ─────────────────────────────────────────────────────────────────────────────
class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: _C.primary));
}

// ─────────────────────────────────────────────────────────────────────────────
// FACILITY ADD / EDIT DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _FacilityDialog extends StatefulWidget {
  const _FacilityDialog({this.doc, this.preselectedHostel});
  final QueryDocumentSnapshot? doc;
  final QueryDocumentSnapshot? preselectedHostel;

  @override
  State<_FacilityDialog> createState() => _FacilityDialogState();
}

class _FacilityDialogState extends State<_FacilityDialog> {
  final _nameCtrl = TextEditingController();
  String? _hostelId, _hostelName, _hostelCode;
  bool _saving = false;

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final d = widget.doc!.data() as Map<String, dynamic>;
      _nameCtrl.text = (d['facility_name'] as String?) ?? '';
      _hostelId = d['hostel_id'] as String?;
      _hostelName = d['hostel_name'] as String?;
      _hostelCode = d['hostel_code'] as String?;
    } else if (widget.preselectedHostel != null) {
      final hd = widget.preselectedHostel!.data() as Map<String, dynamic>;
      _hostelId = widget.preselectedHostel!.id;
      _hostelName = hd['hostel_name'] as String?;
      _hostelCode = hd['hostel_code'] as String?;
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _hostelId == null) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'facility_name': name,
      'hostel_id': _hostelId,
      'hostel_name': _hostelName,
      'hostel_code': _hostelCode,
    };
    try {
      if (_isEdit) {
        await db.collection('facilities').doc(widget.doc!.id).update(data);
        await ActivityLogger.log(
          action: 'Updated Facility',
          details: 'Facility: $name, Hostel: $_hostelName',
        );
      } else {
        await db.collection('facilities').add(data);
        await ActivityLogger.log(
          action: 'Created Facility',
          details: 'Facility: $name, Hostel: $_hostelName',
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormDialog(
        title: _isEdit ? 'Edit Facility' : 'Add Facility',
        saving: _saving,
        onSave: _save,
        fields: [
          AdminFormField(
            label: 'Facility Name *',
            controller: _nameCtrl,
            hint: 'e.g. Free Wi-Fi, Laundry, Kitchen',
          ),
        ],
        extraWidgets: [
          const SizedBox(height: 12),
          FirestoreDropdown(
            label: 'Hostel *',
            collection: 'hostels',
            displayField: 'hostel_name',
            selectedId: _hostelId,
            onChanged: (id, doc) => setState(() {
              _hostelId = id;
              final d = doc?.data() as Map?;
              _hostelName = d?['hostel_name'] as String?;
              _hostelCode = d?['hostel_code'] as String?;
            }),
          ),
        ],
      );

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }
}
