// lib/screens/admin/panes/bookings_pane.dart
//
// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BOOKINGS PANE — Advanced, Real-time, Fully Interactive Admin View      ║
// ╚══════════════════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// ─── Theme tokens (self-contained so pane compiles standalone) ────────────────
const _kPrimary = Color(0xFF0F766E);
const _kAccent = Color(0xFF14B8A6);
const _kDark = Color(0xFF0D1B2A);
const _kSurface = Color(0xFFF8FAFC);
const _kCard = Colors.white;
const _kBorder = Color(0xFFE2E8F0);
const _kGreen = Color(0xFF16A34A);
const _kGreenBg = Color(0xFFDCFCE7);
const _kOrange = Color(0xFFEA580C);
const _kOrangeBg = Color(0xFFFFF7ED);
const _kRed = Color(0xFFDC2626);
const _kRedBg = Color(0xFFFEF2F2);
const _kBlue = Color(0xFF2563EB);
const _kBlueBg = Color(0xFFEFF6FF);
const _kTextDark = Color(0xFF1E293B);
const _kTextMid = Color(0xFF475569);
const _kTextLight = Color(0xFF94A3B8);

// ─── Shortcut ─────────────────────────────────────────────────────────────────
FirebaseFirestore get _db => FirebaseFirestore.instance;

String _fmtDate(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d);
String _fmtShort(DateTime d) => DateFormat('dd MMM yy').format(d);

// ══════════════════════════════════════════════════════════════════════════════
// ROOM SLOT HELPERS
// ══════════════════════════════════════════════════════════════════════════════

/// Decrements the room's [booked] count by [slots], clamped to 0.
/// Only call this when you are certain the slot was previously counted
/// (i.e. the booking's old status was 'confirmed').
Future<void> _decrementRoomSlots(String roomId, int slots) async {
  await _db.runTransaction((txn) async {
    final roomRef = _db.collection('rooms').doc(roomId);
    final snap = await txn.get(roomRef);
    if (!snap.exists) return;
    final current = (snap.data()?['booked'] ?? 0) as int;
    final updated = (current - slots).clamp(0, 999999);
    txn.update(roomRef, {'booked': updated});
  });
}

/// Increments the room's [booked] count by [slots].
/// Throws if there are not enough remaining slots.
Future<void> _incrementRoomSlots(String roomId, int slots) async {
  await _db.runTransaction((txn) async {
    final roomRef = _db.collection('rooms').doc(roomId);
    final snap = await txn.get(roomRef);
    if (!snap.exists) return;
    final booked = (snap.data()?['booked'] ?? 0) as int;
    final capacity = (snap.data()?['capacity'] ?? 1) as int;
    if (booked + slots > capacity) throw Exception('Not enough slots');
    txn.update(roomRef, {'booked': FieldValue.increment(slots)});
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// BOOKINGS PANE — root widget
// ══════════════════════════════════════════════════════════════════════════════
class BookingsPane extends StatefulWidget {
  const BookingsPane({super.key});
  @override
  State<BookingsPane> createState() => _BookingsPaneState();
}

class _BookingsPaneState extends State<BookingsPane>
    with TickerProviderStateMixin {
  // ── state ──────────────────────────────────────────────────────────────────
  String _statusFilter = 'all';
  String _searchQuery = '';
  String _sortField = 'booked_at';
  bool _sortAsc = false;
  final _searchCtrl = TextEditingController();
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── summary stream ─────────────────────────────────────────────────────────
  Stream<QuerySnapshot>? _stream;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _rebuildStream();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _rebuildStream() {
    Query q =
        _db.collection('bookings').orderBy(_sortField, descending: !_sortAsc);
    if (_statusFilter != 'all') q = q.where('status', isEqualTo: _statusFilter);
    setState(() => _stream = q.snapshots());
  }

  List<QueryDocumentSnapshot> _applySearch(List<QueryDocumentSnapshot> docs) {
    if (_searchQuery.trim().isEmpty) return docs;
    final q = _searchQuery.toLowerCase();
    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return (d['name'] ?? '').toString().toLowerCase().contains(q) ||
          (d['email'] ?? '').toString().toLowerCase().contains(q) ||
          (d['phone'] ?? '').toString().toLowerCase().contains(q) ||
          (d['hostel_name'] ?? '').toString().toLowerCase().contains(q) ||
          (d['room_number'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar: stats + search + filters ────────────────────────────
          _TopBar(
            stream: _db.collection('bookings').snapshots(),
            searchCtrl: _searchCtrl,
            statusFilter: _statusFilter,
            sortField: _sortField,
            sortAsc: _sortAsc,
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            onFilterChanged: (v) {
              _statusFilter = v;
              _rebuildStream();
            },
            onSortChanged: (field, asc) {
              _sortField = field;
              _sortAsc = asc;
              _rebuildStream();
            },
          ),
          // ── Table / list ────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _stream,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _LoadingGrid();
                }
                if (snap.hasError) {
                  return _ErrorBox(message: snap.error.toString());
                }
                final allDocs = snap.data?.docs ?? [];
                final filtered = _applySearch(allDocs);
                if (filtered.isEmpty) {
                  return _EmptyBox(
                    isFiltered:
                        _searchQuery.isNotEmpty || _statusFilter != 'all',
                  );
                }
                return _BookingsList(
                  docs: filtered,
                  allDocs: allDocs,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TOP BAR  ── stats chips + search + filters + sort
// ══════════════════════════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final TextEditingController searchCtrl;
  final String statusFilter;
  final String sortField;
  final bool sortAsc;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;
  final void Function(String, bool) onSortChanged;

  const _TopBar({
    required this.stream,
    required this.searchCtrl,
    required this.statusFilter,
    required this.sortField,
    required this.sortAsc,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_kPrimary, _kAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.book_online_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Bookings Management',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark,
                    letterSpacing: -0.3)),
            const Spacer(),
            // Live indicator
            _LivePulse(),
          ]),
          const SizedBox(height: 16),
          // Stat chips — real-time
          StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (ctx, snap) {
              final docs = snap.data?.docs ?? [];
              int total = docs.length;
              int confirmed = docs
                  .where((d) => (d.data() as Map)['status'] == 'confirmed')
                  .length;
              int pending = docs
                  .where((d) =>
                      (d.data() as Map)['status'] == 'booked' ||
                      (d.data() as Map)['status'] == 'pending')
                  .length;
              int declined = docs
                  .where((d) => (d.data() as Map)['status'] == 'declined')
                  .length;
              double revenue = docs.fold(
                  0.0,
                  (sum, d) =>
                      sum + ((d.data() as Map)['amount_paid'] ?? 0).toDouble());
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _StatChip(
                      label: 'Total',
                      value: '$total',
                      icon: Icons.receipt_long_rounded,
                      color: _kBlue,
                      bg: _kBlueBg),
                  const SizedBox(width: 10),
                  _StatChip(
                      label: 'Confirmed',
                      value: '$confirmed',
                      icon: Icons.check_circle_rounded,
                      color: _kGreen,
                      bg: _kGreenBg),
                  const SizedBox(width: 10),
                  _StatChip(
                      label: 'Pending',
                      value: '$pending',
                      icon: Icons.schedule_rounded,
                      color: _kOrange,
                      bg: _kOrangeBg),
                  const SizedBox(width: 10),
                  _StatChip(
                      label: 'Declined',
                      value: '$declined',
                      icon: Icons.cancel_rounded,
                      color: _kRed,
                      bg: _kRedBg),
                  const SizedBox(width: 10),
                ]),
              );
            },
          ),
          const SizedBox(height: 14),
          // Search + filter row
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search field
              SizedBox(
                width: 260,
                height: 40,
                child: TextField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search name, email, room…',
                    hintStyle:
                        const TextStyle(fontSize: 13, color: _kTextLight),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: _kTextLight),
                    suffixIcon: searchCtrl.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              searchCtrl.clear();
                              onSearchChanged('');
                            },
                            child: const Icon(Icons.close_rounded,
                                size: 16, color: _kTextLight))
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    filled: true,
                    fillColor: _kSurface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _kPrimary, width: 1.5)),
                  ),
                ),
              ),
              // Status filters
              ...[
                ('all', 'All'),
                ('booked', 'Pending'),
                ('confirmed', 'Confirmed'),
                ('declined', 'Declined'),
              ].map((t) => _FilterChip(
                    label: t.$2,
                    selected: statusFilter == t.$1,
                    color: _statusColor(t.$1),
                    onTap: () => onFilterChanged(t.$1),
                  )),
              // Sort menu
              _SortMenu(
                  current: sortField, asc: sortAsc, onChanged: onSortChanged),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Color _statusColor(String s) {
    return switch (s) {
      'confirmed' => _kGreen,
      'declined' => _kRed,
      'booked' => _kOrange,
      _ => _kPrimary,
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BOOKINGS LIST — responsive: table on wide, cards on narrow
// ══════════════════════════════════════════════════════════════════════════════
class _BookingsList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final List<QueryDocumentSnapshot> allDocs;
  const _BookingsList({required this.docs, required this.allDocs});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 800;
    return isWide ? _BookingsTable(docs: docs) : _BookingsCards(docs: docs);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TABLE VIEW (wide screens)
// ══════════════════════════════════════════════════════════════════════════════
class _BookingsTable extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  const _BookingsTable({required this.docs});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: const Row(children: [
                    Expanded(flex: 3, child: _TH('Guest / Student')),
                    Expanded(flex: 3, child: _TH('Hostel')),
                    Expanded(flex: 2, child: _TH('Room')),
                    Expanded(flex: 2, child: _TH('Amount')),
                    Expanded(flex: 2, child: _TH('Status')),
                    Expanded(flex: 2, child: _TH('Booked On')),
                    SizedBox(width: 44),
                  ]),
                ),
                // Rows
                ...docs
                    .asMap()
                    .entries
                    .map((e) => _TableRow(doc: e.value, index: e.key)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Showing ${docs.length} booking${docs.length != 1 ? 's' : ''}',
            style: const TextStyle(
                fontSize: 12, color: _kTextLight, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kTextLight,
          letterSpacing: 0.5));
}

class _TableRow extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final int index;
  const _TableRow({required this.doc, required this.index});
  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 40), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final ts = d['booked_at'];
    final date = ts is Timestamp ? _fmtShort(ts.toDate()) : '—';
    final status = (d['status'] ?? 'booked') as String;
    final amount = (d['amount'] ?? 0).toDouble();

    return FadeTransition(
      opacity: _anim,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _hovered ? _kPrimary.withOpacity(0.03) : Colors.transparent,
            border:
                const Border(bottom: BorderSide(color: _kBorder, width: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            // Guest
            Expanded(
              flex: 3,
              child: Row(children: [
                _Avatar(name: d['name'] ?? '?', status: status),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['name'] ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _kTextDark)),
                        Text(d['email'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: _kTextLight)),
                      ]),
                ),
              ]),
            ),
            // Hostel
            Expanded(
              flex: 3,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['hostel_name'] ?? d['hostelName'] ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            color: _kTextDark,
                            fontWeight: FontWeight.w600)),
                    if ((d['hostel_code'] ?? '').toString().isNotEmpty)
                      Text(d['hostel_code'],
                          style: const TextStyle(
                              fontSize: 11, color: _kTextLight)),
                  ]),
            ),
            // Room
            Expanded(
              flex: 2,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['room_number'] ?? d['roomNumber'] ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kTextDark)),
                    if ((d['slots_booked'] ?? 0) > 0)
                      Text('${d['slots_booked']} slot(s)',
                          style: const TextStyle(
                              fontSize: 11, color: _kTextLight)),
                  ]),
            ),
            // Amount
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    amount > 0
                        ? 'GHS ${NumberFormat('#,##0.00').format(amount)}'
                        : '—',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: amount > 0 ? _kGreen : _kTextLight),
                  ),
                  if ((d['amount_paid'] ?? 0) > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Paid: GHS ${NumberFormat('#,##0.00').format((d['amount_paid'] ?? 0).toDouble())}',
                      style: const TextStyle(fontSize: 10, color: _kGreen),
                    ),
                    if ((d['balance'] ?? 0) > 0)
                      Text(
                        'Bal: GHS ${NumberFormat('#,##0.00').format((d['balance'] ?? 0).toDouble())}',
                        style: const TextStyle(fontSize: 10, color: _kOrange),
                      ),
                  ],
                ],
              ),
            ),
            // Status
            Expanded(
              flex: 2,
              child: _StatusBadge(status: status),
            ),
            // Date
            Expanded(
              flex: 2,
              child: Text(date,
                  style: const TextStyle(fontSize: 12, color: _kTextMid)),
            ),
            // Actions
            SizedBox(
              width: 44,
              child: _ActionBtn(docId: widget.doc.id, data: d),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CARD VIEW (narrow screens)
// ══════════════════════════════════════════════════════════════════════════════
class _BookingsCards extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  const _BookingsCards({required this.docs});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _BookingCard(doc: docs[i], index: i),
    );
  }
}

class _BookingCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final int index;
  const _BookingCard({required this.doc, required this.index});
  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _slide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final ts = d['booked_at'];
    final date = ts is Timestamp ? _fmtShort(ts.toDate()) : '—';
    final status = (d['status'] ?? 'booked') as String;
    final amount = (d['amount'] ?? 0).toDouble();

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(children: [
            // Card header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _statusBg(status),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                _Avatar(name: d['name'] ?? '?', status: status, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['name'] ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: _kTextDark)),
                        Text(d['email'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: _kTextMid)),
                      ]),
                ),
                _StatusBadge(status: status),
              ]),
            ),
            // Card body
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _CardRow(
                    icon: Icons.apartment_rounded,
                    label: 'Hostel',
                    value: d['hostel_name'] ?? '—'),
                _CardRow(
                    icon: Icons.bed_rounded,
                    label: 'Room',
                    value:
                        '${d['room_number'] ?? '—'}  ·  ${d['slots_booked'] ?? 1} slot(s)'),
                _CardRow(
                    icon: Icons.phone_rounded,
                    label: 'Phone',
                    value: d['phone'] ?? '—'),
                _CardRow(
                    icon: Icons.payments_rounded,
                    label: 'Amount',
                    value: amount > 0
                        ? 'GHS ${NumberFormat('#,##0.00').format(amount)}'
                        : '—',
                    valueColor: amount > 0 ? _kGreen : _kTextLight),
                _CardRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Booked',
                    value: date),
              ]),
            ),
            // Actions row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              child: Row(children: [
                Expanded(
                  child: _SmallActionBtn(
                    label: 'View Details',
                    icon: Icons.visibility_rounded,
                    color: _kBlue,
                    onTap: () => _showDetail(context, widget.doc.id, d),
                  ),
                ),
                const SizedBox(width: 8),
                _ActionBtn(docId: widget.doc.id, data: d),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Color _statusBg(String s) {
    return switch (s) {
      'confirmed' => _kGreenBg,
      'declined' => _kRedBg,
      _ => _kOrangeBg,
    };
  }
}

class _CardRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _CardRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: _kPrimary),
        const SizedBox(width: 8),
        Text('$label:',
            style: const TextStyle(
                fontSize: 12, color: _kTextLight, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? _kTextDark)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ACTION BUTTON — opens popup menu
// ══════════════════════════════════════════════════════════════════════════════
class _ActionBtn extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _ActionBtn({required this.docId, required this.data});

  // ── FIXED: correctly manage room slots on every status change ─────────────
  Future<void> _setStatus(BuildContext ctx, String newStatus) async {
    try {
      // 1. Read current status BEFORE writing anything
      final bookingSnap = await _db.collection('bookings').doc(docId).get();
      final oldStatus = (bookingSnap.data()?['status'] ?? 'booked') as String;

      // 2. Update the booking document
      await _db.collection('bookings').doc(docId).update({
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 3. Adjust room slot count based on transition
      final roomId = (data['room_id'] ?? data['roomId'])?.toString();
      final slots = (data['slots_booked'] ?? 1) as int;

      if (roomId != null && roomId.isNotEmpty) {
        if (newStatus == 'confirmed' && oldStatus != 'confirmed') {
          // Pending/declined → confirmed: lock the slot
          await _incrementRoomSlots(roomId, slots);
        } else if (newStatus == 'declined' && oldStatus == 'confirmed') {
          // Confirmed → declined: free the slot
          await _decrementRoomSlots(roomId, slots);
        } else if (newStatus == 'booked' && oldStatus == 'confirmed') {
          // Confirmed → reset to pending: free the slot
          await _decrementRoomSlots(roomId, slots);
        }
        // pending → declined: slot was never locked, nothing to do
      }

      if (ctx.mounted) {
        _showSnack(ctx, _statusMsg(newStatus), _statusColor(newStatus));
      }
    } catch (e) {
      if (ctx.mounted) _showSnack(ctx, 'Error: $e', _kRed);
    }
  }

  // ── FIXED: decrement room booked count if booking was confirmed ───────────
  Future<void> _deleteBooking(BuildContext ctx) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Booking',
        message: 'This will permanently remove the booking for '
            '${data['name'] ?? 'this guest'}. This action cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: _kRed,
      ),
    );
    if (confirm != true || !ctx.mounted) return;

    try {
      final roomId = (data['room_id'] ?? data['roomId'])?.toString();
      final slots = (data['slots_booked'] ?? 1) as int;
      final status = (data['status'] ?? 'booked') as String;

      // Only free the slot if it was actually locked (confirmed)
      if (roomId != null && roomId.isNotEmpty && status == 'confirmed') {
        await _decrementRoomSlots(roomId, slots);
      }

      await _db.collection('bookings').doc(docId).delete();

      if (ctx.mounted) _showSnack(ctx, 'Booking deleted', _kRed);
    } catch (e) {
      if (ctx.mounted) _showSnack(ctx, 'Error: $e', _kRed);
    }
  }

  String _statusMsg(String s) => switch (s) {
        'confirmed' => '✅ Booking confirmed',
        'declined' => '❌ Booking declined',
        _ => '🔄 Status reset to pending',
      };

  Color _statusColor(String s) => switch (s) {
        'confirmed' => _kGreen,
        'declined' => _kRed,
        _ => _kOrange,
      };

  void _showSnack(BuildContext ctx, String msg, Color color) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'booked') as String;
    return PopupMenuButton<String>(
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: const Icon(Icons.more_vert_rounded, size: 16, color: _kTextMid),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      onSelected: (v) {
        if (v == 'view') {
          _showDetail(context, docId, data);
          return;
        }
        if (v == 'delete') {
          _deleteBooking(context);
          return;
        }
        _setStatus(context, v);
      },
      itemBuilder: (_) => [
        _menuItem('view', Icons.visibility_rounded, 'View Details', _kBlue),
        const PopupMenuDivider(),
        if (status != 'confirmed')
          _menuItem('confirmed', Icons.check_circle_rounded, 'Confirm Booking',
              _kGreen),
        if (status != 'declined')
          _menuItem('declined', Icons.cancel_rounded, 'Decline Booking', _kRed),
        if (status != 'booked')
          _menuItem(
              'booked', Icons.refresh_rounded, 'Reset to Pending', _kOrange),
        const PopupMenuDivider(),
        _menuItem(
            'delete', Icons.delete_outline_rounded, 'Delete Booking', _kRed),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: value == 'delete' ? _kRed : _kTextDark,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DETAIL BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════
void _showDetail(BuildContext ctx, String docId, Map<String, dynamic> d) {
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DetailSheet(docId: docId, data: d),
  );
}

class _DetailSheet extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _DetailSheet({required this.docId, required this.data});

  // ── FIXED: frees room slot when declining a confirmed booking ─────────────
  Future<void> _handleConfirm(BuildContext ctx) async {
    try {
      final bookingSnap = await _db.collection('bookings').doc(docId).get();
      final oldStatus = (bookingSnap.data()?['status'] ?? 'booked') as String;

      await _db
          .collection('bookings')
          .doc(docId)
          .update({'status': 'confirmed'});

      final roomId = (data['room_id'] ?? data['roomId'])?.toString();
      final slots = (data['slots_booked'] ?? 1) as int;

      if (roomId != null && roomId.isNotEmpty && oldStatus != 'confirmed') {
        await _incrementRoomSlots(roomId, slots);
      }

      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: _kRed,
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  // ── FIXED: frees room slot when declining a confirmed booking ─────────────
  Future<void> _handleDecline(BuildContext ctx) async {
    try {
      final bookingSnap = await _db.collection('bookings').doc(docId).get();
      final oldStatus = (bookingSnap.data()?['status'] ?? 'booked') as String;

      await _db
          .collection('bookings')
          .doc(docId)
          .update({'status': 'declined'});

      final roomId = (data['room_id'] ?? data['roomId'])?.toString();
      final slots = (data['slots_booked'] ?? 1) as int;

      // Only decrement if the slot was previously locked
      if (roomId != null && roomId.isNotEmpty && oldStatus == 'confirmed') {
        await _decrementRoomSlots(roomId, slots);
      }

      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: _kRed,
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final ts = d['booked_at'];
    final date = ts is Timestamp ? _fmtDate(ts.toDate()) : '—';
    final status = (d['status'] ?? 'booked') as String;
    final amount = (d['amount'] ?? 0).toDouble();
    final isWide = MediaQuery.of(context).size.width > 700;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
          // Sheet header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_kPrimary, _kAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(children: [
              _Avatar(name: d['name'] ?? '?', status: status, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d['name'] ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text(d['email'] ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.85))),
                    ]),
              ),
              _StatusBadge(status: status, large: true),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ]),
          ),
          // Body
          Expanded(
            child: SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [
                              _kPrimary.withOpacity(0.06),
                              _kAccent.withOpacity(0.04)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _kPrimary.withOpacity(0.15)),
                      ),
                      child: isWide
                          ? Row(children: [
                              Expanded(
                                  child: _SumCell(
                                      'Hostel', d['hostel_name'] ?? '—')),
                              Expanded(
                                  child: _SumCell(
                                      'Room', d['room_number'] ?? '—')),
                              Expanded(
                                  child: _SumCell(
                                      'Slots', '${d['slots_booked'] ?? 1}')),
                              Expanded(
                                child: _SumCell(
                                    'Amount',
                                    amount > 0
                                        ? 'GHS ${NumberFormat('#,##0.00').format(amount)}'
                                        : '—',
                                    valueColor: _kGreen),
                              ),
                            ])
                          : Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              children: [
                                _SumCell('Hostel', d['hostel_name'] ?? '—'),
                                _SumCell('Room', d['room_number'] ?? '—'),
                                _SumCell('Slots', '${d['slots_booked'] ?? 1}'),
                                _SumCell(
                                    'Amount',
                                    amount > 0
                                        ? 'GHS ${NumberFormat('#,##0.00').format(amount)}'
                                        : '—',
                                    valueColor: _kGreen),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),
                    // Sections
                    _DetailSection(title: 'Personal Info', children: [
                      _DetailTile(
                          Icons.person_rounded, 'Full Name', d['name'] ?? '—'),
                      _DetailTile(
                          Icons.email_rounded, 'Email', d['email'] ?? '—',
                          copyable: true),
                      _DetailTile(
                          Icons.phone_rounded, 'Phone', d['phone'] ?? '—',
                          copyable: true),
                    ]),
                    const SizedBox(height: 16),
                    _DetailSection(title: 'Academic Info', children: [
                      _DetailTile(
                          Icons.school_rounded, 'School', d['school'] ?? '—'),
                      _DetailTile(
                          Icons.badge_rounded,
                          'School ID',
                          d['school_id']?.toString().isNotEmpty == true
                              ? d['school_id']
                              : '—'),
                      _DetailTile(Icons.person_off_rounded, 'Is Student',
                          d['not_student'] == true ? 'No' : 'Yes'),
                    ]),
                    const SizedBox(height: 16),
                    _DetailSection(title: 'Payment Info', children: [
                      _DetailTile(Icons.payment_rounded, 'Method',
                          d['payment_method'] ?? d['momo_type'] ?? '—'),
                      _DetailTile(Icons.phone_android_rounded, 'MoMo Number',
                          d['momo_number'] ?? '—',
                          copyable: true),
                      _DetailTile(Icons.receipt_rounded, 'Reference',
                          d['payment_reference'] ?? '—',
                          copyable: true),
                      _DetailTile(Icons.paid_rounded, 'Payment Status',
                          d['payment_status'] ?? '—'),
                      _DetailTile(
                          Icons.savings_rounded,
                          'Total Amount',
                          d['amount'] != null
                              ? 'GHS ${NumberFormat('#,##0.00').format((d['amount'] as num).toDouble())}'
                              : '—'),
                      _DetailTile(
                          Icons.check_rounded,
                          'Amount Paid',
                          d['amount_paid'] != null
                              ? 'GHS ${NumberFormat('#,##0.00').format((d['amount_paid'] as num).toDouble())}'
                              : 'GHS 0.00'),
                      _DetailTile(
                          Icons.pending_rounded,
                          'Balance Remaining',
                          d['balance'] != null
                              ? 'GHS ${NumberFormat('#,##0.00').format((d['balance'] as num).toDouble())}'
                              : '—'),
                      _DetailTile(
                          Icons.account_balance_wallet_rounded,
                          'Deposit Amount',
                          d['deposit_amount'] != null
                              ? 'GHS ${NumberFormat('#,##0.00').format((d['deposit_amount'] as num).toDouble())}'
                              : '—'),
                    ]),
                    const SizedBox(height: 16),
                    _DetailSection(title: 'Booking Info', children: [
                      _DetailTile(
                          Icons.calendar_today_rounded, 'Booked At', date),
                      if ((d['notes'] ?? '').toString().isNotEmpty)
                        _DetailTile(Icons.notes_rounded, 'Notes', d['notes']),
                      _DetailTile(
                          Icons.fingerprint_rounded, 'Booking ID', docId,
                          copyable: true, small: true),
                    ]),

                    const SizedBox(height: 16),
                    _PaymentHistorySection(docId: docId),
                    const SizedBox(height: 24),

                    // Quick action buttons — now with proper room slot management
                    Row(children: [
                      if (status != 'confirmed')
                        Expanded(
                          child: _BigActionBtn(
                            label: 'Confirm',
                            icon: Icons.check_circle_rounded,
                            color: _kGreen,
                            onTap: () => _handleConfirm(context),
                          ),
                        ),
                      if (status != 'confirmed' && status != 'declined')
                        const SizedBox(width: 10),
                      if (status != 'declined')
                        Expanded(
                          child: _BigActionBtn(
                            label: 'Decline',
                            icon: Icons.cancel_rounded,
                            color: _kRed,
                            onTap: () => _handleDecline(context),
                          ),
                        ),
                    ]),
                  ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SumCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SumCell(this.label, this.value, {this.valueColor});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: _kTextLight,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? _kTextDark)),
        ],
      );
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
                color: _kPrimary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kTextDark,
                letterSpacing: 0.1)),
      ]),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Column(children: [
          ...children.asMap().entries.map((e) => Column(children: [
                e.value,
                if (e.key < children.length - 1)
                  const Divider(height: 1, color: _kBorder, indent: 16),
              ])),
        ]),
      ),
    ]);
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;
  final bool small;
  const _DetailTile(this.icon, this.label, this.value,
      {this.copyable = false, this.small = false});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, size: 16, color: _kPrimary),
      title:
          Text(label, style: const TextStyle(fontSize: 11, color: _kTextLight)),
      subtitle: Text(value,
          style: TextStyle(
              fontSize: small ? 11 : 13,
              fontWeight: FontWeight.w700,
              color: _kTextDark,
              fontFamily: small ? 'monospace' : null)),
      trailing: copyable
          ? IconButton(
              icon:
                  const Icon(Icons.copy_rounded, size: 14, color: _kTextLight),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Copied!'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ));
              },
            )
          : null,
    );
  }
}

class _BigActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BigActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        shadowColor: color.withOpacity(0.35),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS — Avatar, StatusBadge, etc.
// ══════════════════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String name;
  final String status;
  final double size;
  const _Avatar({required this.name, required this.status, this.size = 32});

  Color get _color => switch (status) {
        'confirmed' => _kGreen,
        'declined' => _kRed,
        _ => _kOrange,
      };

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: _color.withOpacity(0.4), width: 1.5),
      ),
      child: Center(
        child: Text(initials,
            style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w800,
                color: _color)),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool large;
  const _StatusBadge({required this.status, this.large = false});

  (Color, Color, String, IconData) get _cfg => switch (status.toLowerCase()) {
        'confirmed' => (
            _kGreen,
            _kGreenBg,
            'Confirmed',
            Icons.check_circle_rounded
          ),
        'declined' => (_kRed, _kRedBg, 'Declined', Icons.cancel_rounded),
        _ => (_kOrange, _kOrangeBg, 'Pending', Icons.schedule_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (color, bg, label, icon) = _cfg;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 12 : 8, vertical: large ? 6 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: large ? 13 : 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: large ? 12 : 10,
                fontWeight: FontWeight.w700,
                color: color)),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bg;
  const _StatChip(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      required this.bg});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.8))),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ]),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : _kSurface,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
              color: selected ? color : _kBorder, width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : _kTextMid)),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final String current;
  final bool asc;
  final void Function(String, bool) onChanged;
  const _SortMenu(
      {required this.current, required this.asc, required this.onChanged});

  static const _options = [
    ('booked_at', 'Date Booked'),
    ('name', 'Name'),
    ('amount', 'Amount'),
    ('status', 'Status'),
  ];

  @override
  Widget build(BuildContext context) {
    final label = _options
        .firstWhere((o) => o.$1 == current, orElse: () => _options[0])
        .$2;
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: _kBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14, color: _kPrimary),
          const SizedBox(width: 6),
          Text('Sort: $label',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMid)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 16, color: _kTextLight),
        ]),
      ),
      onSelected: (v) {
        if (v == current) {
          onChanged(current, !asc);
        } else {
          onChanged(v, false);
        }
      },
      itemBuilder: (_) => _options.map((o) {
        final isSelected = o.$1 == current;
        return PopupMenuItem(
          value: o.$1,
          height: 38,
          child: Row(children: [
            Icon(
                isSelected
                    ? (asc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded)
                    : Icons.sort_rounded,
                size: 14,
                color: isSelected ? _kPrimary : _kTextLight),
            const SizedBox(width: 10),
            Text(o.$2,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? _kPrimary : _kTextDark)),
          ]),
        );
      }).toList(),
    );
  }
}

class _SmallActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SmallActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LIVE PULSE indicator
// ══════════════════════════════════════════════════════════════════════════════
class _LivePulse extends StatefulWidget {
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_anim),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _kGreenBg,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: _kGreen.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: _kGreen, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          const Text('Live',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _kGreen)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONFIRM DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: confirmColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: confirmColor, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: _kTextMid, height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: _kBorder),
                ),
                child: const Text('Cancel',
                    style: TextStyle(
                        color: _kTextMid, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
                child: Text(confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LOADING / EMPTY / ERROR states
// ══════════════════════════════════════════════════════════════════════════════

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 1),
      itemBuilder: (_, i) => _ShimmerRow(),
    );
  }
}

class _ShimmerRow extends StatefulWidget {
  @override
  State<_ShimmerRow> createState() => _ShimmerRowState();
}

class _ShimmerRowState extends State<_ShimmerRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _shimmerBox(double w, double h) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Color.lerp(
              const Color(0xFFE2E8F0), const Color(0xFFF1F5F9), _anim.value),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder, width: 0.5))),
      child: Row(children: [
        _shimmerBox(32, 32),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _shimmerBox(120, 12),
          const SizedBox(height: 5),
          _shimmerBox(80, 10),
        ]),
        const Spacer(),
        _shimmerBox(100, 12),
        const SizedBox(width: 16),
        _shimmerBox(60, 22),
      ]),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final bool isFiltered;
  const _EmptyBox({required this.isFiltered});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _kSurface,
            shape: BoxShape.circle,
            border: Border.all(color: _kBorder),
          ),
          child: Icon(
              isFiltered ? Icons.search_off_rounded : Icons.hotel_rounded,
              size: 40,
              color: _kTextLight),
        ),
        const SizedBox(height: 16),
        Text(
          isFiltered ? 'No results found' : 'No bookings yet',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: _kTextMid),
        ),
        const SizedBox(height: 6),
        Text(
          isFiltered
              ? 'Try adjusting your search or filter'
              : 'Bookings will appear here once students start booking',
          style: const TextStyle(fontSize: 13, color: _kTextLight),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 44, color: _kRed),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextMid, fontSize: 13)),
        ]),
      ),
    );
  }
}

class _PaymentHistorySection extends StatelessWidget {
  final String docId;
  const _PaymentHistorySection({required this.docId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('bookings')
          .doc(docId)
          .collection('payments')
          .orderBy('paid_at', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                    color: _kPrimary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('Payment History',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark)),
          ]),
          const SizedBox(height: 10),
          ...docs.map((doc) {
            final p = doc.data() as Map<String, dynamic>;
            final ts = p['paid_at'];
            final date = ts is Timestamp ? _fmtShort(ts.toDate()) : '—';
            final amt = (p['amount'] ?? 0).toDouble();
            final method = (p['method'] ?? '').toString().toUpperCase();
            final note = p['note'] ?? '';
            final status = p['status'] ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.payments_rounded,
                      size: 16, color: _kGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(note.isNotEmpty ? note : 'Payment',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _kTextDark)),
                        const SizedBox(height: 2),
                        Text('$method · $date',
                            style: const TextStyle(
                                fontSize: 11, color: _kTextLight)),
                        if (status.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: status == 'paid' ? _kGreenBg : _kOrangeBg,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Text(status,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        status == 'paid' ? _kGreen : _kOrange)),
                          ),
                      ]),
                ),
                Text(
                  'GHS ${NumberFormat('#,##0.00').format(amt)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _kGreen),
                ),
              ]),
            );
          }),
        ]);
      },
    );
  }
}
