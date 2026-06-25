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

// ─── Theme tokens ─────────────────────────────────────────────────────────────
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

FirebaseFirestore get _db => FirebaseFirestore.instance;

String _fmtDate(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d);
String _fmtShort(DateTime d) => DateFormat('dd MMM yy, hh:mm a').format(d);

// ══════════════════════════════════════════════════════════════════════════════
// ROOM SLOT HELPERS
// ══════════════════════════════════════════════════════════════════════════════

Future<void> _decrementRoomSlots(String roomId, int slots) async {
  await _db.runTransaction((txn) async {
    final roomRef = _db.collection('rooms').doc(roomId);
    final snap = await txn.get(roomRef);
    if (!snap.exists) return;
    final current = (snap.data()?['booked'] ?? 0) as int;
    txn.update(roomRef, {'booked': (current - slots).clamp(0, 999999)});
  });
}

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
// BOOKINGS PANE
// ══════════════════════════════════════════════════════════════════════════════
class BookingsPane extends StatefulWidget {
  const BookingsPane({super.key});
  @override
  State<BookingsPane> createState() => _BookingsPaneState();
}

class _BookingsPaneState extends State<BookingsPane>
    with TickerProviderStateMixin {
  String _statusFilter = 'all';
  String _searchQuery = '';
  String _sortField = 'booked_at';
  bool _sortAsc = false;
  final _searchCtrl = TextEditingController();
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  Stream<QuerySnapshot>? _stream;
  late final TabController _tabCtrl;
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _rebuildStream();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _tabCtrl.dispose();
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
          // ── Pill tab bar ─────────────────────────────────────────────────
          Container(
            color: _kCard,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 40,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: _kBorder),
                  ),
                  child: TabBar(
                    controller: _tabCtrl,
                    indicator: BoxDecoration(
                      gradient:
                          const LinearGradient(colors: [_kPrimary, _kAccent]),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: _kTextMid,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13),
                    tabs: const [
                      Tab(text: 'Bookings'),
                      Tab(text: 'Pre-Bookings'),
                    ],
                  ),
                ),
                const SizedBox(height: 0),
              ],
            ),
          ),

          // ── Tab views ────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // ── Tab 1: existing bookings ──────────────────────────────
                Column(children: [
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
                            isFiltered: _searchQuery.isNotEmpty ||
                                _statusFilter != 'all',
                          );
                        }
                        return _BookingsList(docs: filtered, allDocs: allDocs);
                      },
                    ),
                  ),
                ]),

                // ── Tab 2: pre-bookings ───────────────────────────────────
                const _PreBookingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TOP BAR
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          Flexible(
            child: Text('Bookings Management',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark,
                    letterSpacing: -0.3)),
          ),
          const SizedBox(width: 8),
          _LivePulse(),
        ]),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];
            final total = docs.length;
            final confirmed = docs
                .where((d) => (d.data() as Map)['status'] == 'confirmed')
                .length;
            final pending = docs.where((d) {
              final s = (d.data() as Map)['status'];
              return s == 'booked' || s == 'pending';
            }).length;
            final declined = docs
                .where((d) => (d.data() as Map)['status'] == 'declined')
                .length;
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
              ]),
            );
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              height: 40,
              child: TextField(
                controller: searchCtrl,
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search name, email, room…',
                  hintStyle: const TextStyle(fontSize: 13, color: _kTextLight),
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
            _SortMenu(
                current: sortField, asc: sortAsc, onChanged: onSortChanged),
          ],
        ),
        const SizedBox(height: 14),
      ]),
    );
  }

  Color _statusColor(String s) => switch (s) {
        'confirmed' => _kGreen,
        'declined' => _kRed,
        'booked' => _kOrange,
        _ => _kPrimary,
      };
}

// ══════════════════════════════════════════════════════════════════════════════
// LIST / TABLE / CARDS
// ══════════════════════════════════════════════════════════════════════════════
class _BookingsList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final List<QueryDocumentSnapshot> allDocs;
  const _BookingsList({required this.docs, required this.allDocs});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return isWide ? _BookingsTable(docs: docs) : _BookingsCards(docs: docs);
  }
}

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
            child: Column(children: [
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
              ...docs
                  .asMap()
                  .entries
                  .map((e) => _TableRow(doc: e.value, index: e.key)),
            ]),
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
    final hasMovedIn =
        d['move_in_date'] != null || d['status'] == 'active'; // ← moved here
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
                      ])),
                ])),
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
                    ])),
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
                    ])),
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
                            style:
                                const TextStyle(fontSize: 10, color: _kGreen)),
                        if ((d['balance'] ?? 0) > 0)
                          Text(
                              'Bal: GHS ${NumberFormat('#,##0.00').format((d['balance'] ?? 0).toDouble())}',
                              style: const TextStyle(
                                  fontSize: 10, color: _kOrange)),
                      ],
                    ])),
            // AFTER
            Expanded(
                flex: 2,
                child: _StatusBadge(status: status, isActive: hasMovedIn)),
            Expanded(
                flex: 2,
                child: Text(date,
                    style: const TextStyle(fontSize: 12, color: _kTextMid))),
            SizedBox(
                width: 44, child: _ActionBtn(docId: widget.doc.id, data: d)),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CARD VIEW
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

  Color _statusBg(String s) => switch (s) {
        'confirmed' => _kGreenBg,
        'declined' => _kRedBg,
        _ => _kOrangeBg,
      };

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
                          style:
                              const TextStyle(fontSize: 11, color: _kTextMid)),
                    ])),
                _StatusBadge(
                    status: status,
                    isActive: d['move_in_date'] != null || status == 'active'),
              ]),
            ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _kBorder))),
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
}

class _CardRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _CardRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});

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
// ACTION BUTTON
// ══════════════════════════════════════════════════════════════════════════════
class _ActionBtn extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _ActionBtn({required this.docId, required this.data});

  Future<void> _setStatus(BuildContext ctx, String newStatus) async {
    try {
      final bookingSnap = await _db.collection('bookings').doc(docId).get();
      final oldStatus = (bookingSnap.data()?['status'] ?? 'booked') as String;

      await _db.collection('bookings').doc(docId).update({
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });

      final roomId = (data['room_id'] ?? data['roomId'])?.toString();
      final slots = (data['slots_booked'] ?? 1) as int;

      if (roomId != null && roomId.isNotEmpty) {
        // Only decrement if moving AWAY from confirmed (freeing up the slot)
        if ((newStatus == 'declined' || newStatus == 'booked') &&
            oldStatus == 'confirmed') {
          await _decrementRoomSlots(roomId, slots);
        }
        // Never increment here — slots are booked when the student pays,
        // not when admin confirms
      }

      if (ctx.mounted)
        _showSnack(ctx, _statusMsg(newStatus), _statusColor(newStatus));
    } catch (e) {
      if (ctx.mounted) _showSnack(ctx, 'Error: $e', _kRed);
    }
  }

  Future<void> _deleteBooking(BuildContext ctx) async {
    final messenger = ScaffoldMessenger.of(ctx);

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
    if (confirm != true) return;

    try {
      final roomId = (data['room_id'] ?? data['roomId'])?.toString();
      final slots = (data['slots_booked'] ?? 1) as int;
      final status = (data['status'] ?? 'booked') as String;

      if (roomId != null && roomId.isNotEmpty && status == 'confirmed') {
        await _decrementRoomSlots(roomId, slots);
      }

      final paymentsSnap = await _db
          .collection('bookings')
          .doc(docId)
          .collection('payments')
          .get();
      for (final doc in paymentsSnap.docs) {
        await doc.reference.delete();
      }

      await _db.collection('bookings').doc(docId).delete();
      messenger.showSnackBar(SnackBar(
        content: const Text('Booking deleted',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error: $e',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ));
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
// DETAIL SHEET — now live-streaming so installment updates reflect instantly
// ══════════════════════════════════════════════════════════════════════════════
void _showDetail(BuildContext ctx, String docId, Map<String, dynamic> d) {
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DetailSheet(docId: docId, initialData: d),
  );
}

class _DetailSheet extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> initialData;
  const _DetailSheet({required this.docId, required this.initialData});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  // ── room-slot helpers ──────────────────────────────────────────────────────
  Future<void> _handleConfirm(BuildContext ctx, Map<String, dynamic> d) async {
    try {
      await _db
          .collection('bookings')
          .doc(widget.docId)
          .update({'status': 'confirmed'});
      // No slot change — slots already incremented when student paid
      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _handleDecline(BuildContext ctx, Map<String, dynamic> d) async {
    try {
      final snap = await _db.collection('bookings').doc(widget.docId).get();
      final old = (snap.data()?['status'] ?? 'booked') as String;
      await _db
          .collection('bookings')
          .doc(widget.docId)
          .update({'status': 'declined'});
      final roomId = (d['room_id'] ?? d['roomId'])?.toString();
      final slots = (d['slots_booked'] ?? 1) as int;
      if (roomId != null && roomId.isNotEmpty && old == 'confirmed') {
        await _decrementRoomSlots(roomId, slots);
      }
      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _setDueDate(BuildContext ctx, Map<String, dynamic> d) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Set Balance Payment Deadline',
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _kPrimary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    try {
      await _db.collection('bookings').doc(widget.docId).update({
        'balance_due_date': Timestamp.fromDate(picked),
      });
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: const Text('Due date set'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _setMoveInDate(BuildContext ctx, Map<String, dynamic> d) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: DateTime.now(),
      firstDate:
          DateTime.now().subtract(const Duration(days: 30)), // allow backdating
      lastDate: DateTime.now(),
      helpText: 'Set Move-In Date',
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _kPrimary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    try {
      final snap = await _db.collection('bookings').doc(widget.docId).get();
      final data = snap.data()!;
      final durationType = data['duration_type']?.toString() ?? 'year';
      final totalAmount = (data['amount'] as num).toDouble();

      final schedule = _buildSchedule(picked, durationType, totalAmount);

      await _db.collection('bookings').doc(widget.docId).update({
        'move_in_date': Timestamp.fromDate(picked),
        'payment_schedule': schedule,
        'balance_due_date': schedule.first['due_date'],
        'status': 'active', // ← was 'active'
        'move_in_confirmed': true, // ← add this
        'move_in_set_by': 'admin',
      });

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: const Text('Move-in date set — payment schedule activated'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  List<Map<String, dynamic>> _buildSchedule(
    DateTime moveIn,
    String durationType,
    double totalAmount,
  ) {
    final label = switch (durationType) {
      'year' => 'Full Year Payment',
      'academic_year' => 'Academic Year Payment',
      'semester' => 'Semester Payment',
      _ => 'Month 1',
    };
    return [
      {
        'due_date': Timestamp.fromDate(moveIn),
        'amount': totalAmount,
        'label': label,
        'paid': false,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      // Live stream — updates the whole sheet whenever a payment comes in
      stream: _db
          .collection('bookings')
          .doc(widget.docId)
          .snapshots()
          .cast<DocumentSnapshot<Map<String, dynamic>>>(),
      builder: (context, snap) {
        // Fall back to initial data while the stream warms up
        final d = snap.data?.data() ?? widget.initialData;
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
              // Header
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
                      ])),
                  _StatusBadge(
                      status: status,
                      large: true,
                      isActive:
                          d['move_in_date'] != null || status == 'active'),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
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
                                  _kAccent.withOpacity(0.04),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: _kPrimary.withOpacity(0.15)),
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
                                      child: _SumCell('Slots',
                                          '${d['slots_booked'] ?? 1}')),
                                  Expanded(
                                      child: _SumCell(
                                          'Amount',
                                          amount > 0
                                              ? 'GHS ${NumberFormat('#,##0.00').format(amount)}'
                                              : '—',
                                          valueColor: _kGreen)),
                                ])
                              : Wrap(spacing: 16, runSpacing: 12, children: [
                                  _SumCell('Hostel', d['hostel_name'] ?? '—'),
                                  _SumCell('Room', d['room_number'] ?? '—'),
                                  _SumCell(
                                      'Slots', '${d['slots_booked'] ?? 1}'),
                                  _SumCell(
                                      'Amount',
                                      amount > 0
                                          ? 'GHS ${NumberFormat('#,##0.00').format(amount)}'
                                          : '—',
                                      valueColor: _kGreen),
                                ]),
                        ),
                        const SizedBox(height: 20),

                        // ── Personal Info ───────────────────────────────────────
                        _DetailSection(title: 'Personal Info', children: [
                          _DetailTile(Icons.person_rounded, 'Full Name',
                              d['name'] ?? '—'),
                          _DetailTile(
                              Icons.email_rounded, 'Email', d['email'] ?? '—',
                              copyable: true),
                          _DetailTile(
                              Icons.phone_rounded, 'Phone', d['phone'] ?? '—',
                              copyable: true),
                        ]),
                        const SizedBox(height: 16),

                        // ── Academic Info ───────────────────────────────────────
                        _DetailSection(title: 'Academic Info', children: [
                          _DetailTile(Icons.school_rounded, 'School',
                              d['school'] ?? '—'),
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

                        // ── Payment Info ────────────────────────────────────────
                        _DetailSection(title: 'Payment Info', children: [
                          _DetailTile(Icons.payment_rounded, 'Method',
                              d['payment_method'] ?? d['momo_type'] ?? '—'),
                          _DetailTile(Icons.phone_android_rounded,
                              'MoMo Number', d['momo_number'] ?? '—',
                              copyable: true),
                          _DetailTile(Icons.receipt_rounded, 'Reference',
                              d['payment_reference'] ?? '—',
                              copyable: true),
                          _DetailTile(
                              Icons.percent_rounded,
                              'Commission Rate',
                              d['commission_rate'] != null
                                  ? '${(d['commission_rate'] as num).toStringAsFixed(0)}%'
                                  : '—'),
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
                              Icons.event_rounded,
                              'Balance Due Date',
                              d['balance_due_date'] is Timestamp
                                  ? _fmtDate(
                                      (d['balance_due_date'] as Timestamp)
                                          .toDate())
                                  : 'Not set'),
                          _DetailTile(
                              Icons.key_rounded,
                              'Move-In Date',
                              d['move_in_date'] is Timestamp
                                  ? _fmtDate(
                                      (d['move_in_date'] as Timestamp).toDate())
                                  : 'Not confirmed yet'),
                          _DetailTile(Icons.category_rounded, 'Duration Type',
                              d['duration_type']?.toString() ?? '—'),
                          _DetailTile(
                              Icons.account_balance_wallet_rounded,
                              'Deposit Amount',
                              d['deposit_amount'] != null
                                  ? 'GHS ${NumberFormat('#,##0.00').format((d['deposit_amount'] as num).toDouble())}'
                                  : '—'),
                          // ── Dual-status tiles ──────────────────────────────
                          _DetailTile(Icons.paid_rounded, 'Payment Status',
                              d['payment_status'] ?? '—'),
                          _DetailTile(Icons.toggle_on_rounded, 'Booking Status',
                              d['status'] ?? '—'),
                        ]),
                        const SizedBox(height: 12),

                        // ── Payment progress bar (live) ─────────────────────────
                        if (amount > 0)
                          _PaymentProgressBar(
                            total: amount,
                            paid: (d['amount_paid'] as num? ?? 0).toDouble(),
                            paymentCount:
                                (d['payment_count'] as num? ?? 0).toInt(),
                            paymentStatus:
                                d['payment_status']?.toString() ?? '',
                          ),
                        const SizedBox(height: 16),

                        // ── Booking Info ────────────────────────────────────────
                        _DetailSection(title: 'Booking Info', children: [
                          _DetailTile(
                              Icons.calendar_today_rounded, 'Booked At', date),
                          if ((d['notes'] ?? '').toString().isNotEmpty)
                            _DetailTile(
                                Icons.notes_rounded, 'Notes', d['notes']),
                          _DetailTile(Icons.fingerprint_rounded, 'Booking ID',
                              widget.docId,
                              copyable: true, small: true),
                        ]),
                        const SizedBox(height: 16),

                        // ── Payment timeline ────────────────────────────────────
                        _PaymentTimeline(docId: widget.docId),
                        const SizedBox(height: 24),
                        Row(children: [
                          Expanded(
                            child: _BigActionBtn(
                              label: 'Set Due Date',
                              icon: Icons.event_rounded,
                              color: _kBlue,
                              onTap: () => _setDueDate(context, d),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        // ── NEW: Set Move-In Date (only when not yet active) ────────────────
                        if (status == 'confirmed' || status == 'booked')
                          Row(children: [
                            Expanded(
                              child: _BigActionBtn(
                                label: 'Set Move-In Date',
                                icon: Icons.key_rounded,
                                color: _kOrange,
                                onTap: () => _setMoveInDate(context, d),
                              ),
                            ),
                          ]),
                        if (status == 'confirmed' || status == 'booked')
                          const SizedBox(height: 10),

                        // ── Quick-action buttons ────────────────────────────────
                        Row(children: [
                          if (status != 'confirmed')
                            Expanded(
                                child: _BigActionBtn(
                              label: 'Confirm',
                              icon: Icons.check_circle_rounded,
                              color: _kGreen,
                              onTap: () => _handleConfirm(context, d),
                            )),
                          if (status != 'confirmed' && status != 'declined')
                            const SizedBox(width: 10),
                          if (status != 'declined')
                            Expanded(
                                child: _BigActionBtn(
                              label: 'Decline',
                              icon: Icons.cancel_rounded,
                              color: _kRed,
                              onTap: () => _handleDecline(context, d),
                            )),
                        ]),
                      ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAYMENT PROGRESS BAR
// ══════════════════════════════════════════════════════════════════════════════
class _PaymentProgressBar extends StatelessWidget {
  final double total;
  final double paid;
  final int paymentCount;
  final String paymentStatus;
  const _PaymentProgressBar({
    required this.total,
    required this.paid,
    required this.paymentCount,
    required this.paymentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final balance = (total - paid).clamp(0.0, total);
    final isFullyPaid = paymentStatus == 'fully_paid' || balance == 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Amount Paid',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              Text(
                'GHS ${NumberFormat('#,##0.00').format(paid)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
            ]),
            if (isFullyPaid)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded, size: 12, color: _kGreen),
                  SizedBox(width: 4),
                  Text('Fully Paid',
                      style: TextStyle(
                          color: _kGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ]),
              )
            else
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('Balance',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                Text(
                  'GHS ${NumberFormat('#,##0.00').format(balance)}',
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ]),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor:
                AlwaysStoppedAnimation<Color>(isFullyPaid ? _kGreen : _kAccent),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            '$paymentCount payment${paymentCount != 1 ? 's' : ''} made',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          Text(
            '${(progress * 100).toStringAsFixed(0)}% of GHS ${NumberFormat('#,##0.00').format(total)}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAYMENT TIMELINE  — replaces _PaymentHistorySection
// Shows every installment as a vertical timeline with commission breakdown
// ══════════════════════════════════════════════════════════════════════════════
class _PaymentTimeline extends StatelessWidget {
  final String docId;
  const _PaymentTimeline({required this.docId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('bookings')
          .doc(docId)
          .collection('payments')
          .orderBy('paid_at') // ascending: oldest first = chronological
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Section header
          Row(children: [
            Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                    color: _kPrimary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(
                'Payment History  ·  ${docs.length} payment${docs.length != 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark)),
          ]),
          const SizedBox(height: 12),

          // Timeline
          ...docs.asMap().entries.map((entry) {
            final i = entry.key;
            final doc = entry.value;
            final p = doc.data() as Map<String, dynamic>;
            final isLast = i == docs.length - 1;
            return _TimelineEntry(data: p, index: i, isLast: isLast);
          }),
        ]);
      },
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final bool isLast;
  const _TimelineEntry({
    required this.data,
    required this.index,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final p = data;
    final ts = p['paid_at'];
    final date = ts is Timestamp ? _fmtShort(ts.toDate()) : '—';
    final amt = (p['amount'] ?? 0).toDouble();
    final commissionTaken = (p['commission_taken'] as num?)?.toDouble() ?? 0.0;
    final landlordRec = (p['landlord_received'] as num?)?.toDouble() ?? 0.0;
    final method = (p['method'] ?? '').toString().toUpperCase();
    final note = (p['note'] ?? '').toString();
    final status = (p['status'] ?? '').toString();
    final payNum = (p['payment_number'] as num?)?.toInt() ?? (index + 1);
    final isTest = p['is_test'] == true;
    final isFirst = p['is_first_payment'] == true;
    final isFinal = p['is_final_payment'] == true;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: dot + line ──────────────────────────────────────────────
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Dot
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: status == 'paid'
                        ? _kGreen.withOpacity(0.15)
                        : _kOrange.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: status == 'paid' ? _kGreen : _kOrange,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$payNum',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: status == 'paid' ? _kGreen : _kOrange),
                    ),
                  ),
                ),
                // Connecting line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _kBorder,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // ── Right: card ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top row: label + badges + amount ─────────────────────
                      Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      note.isNotEmpty
                                          ? note
                                          : 'Payment #$payNum',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _kTextDark),
                                    ),
                                  ),
                                  if (isTest) _Badge('TEST', _kOrange),
                                  if (isFirst) _Badge('1st', _kBlue),
                                  if (isFinal) _Badge('Final', _kGreen),
                                ]),
                                const SizedBox(height: 3),
                                Text(
                                  method.isNotEmpty ? '$method · $date' : date,
                                  style: const TextStyle(
                                      fontSize: 11, color: _kTextLight),
                                ),
                                if (status.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: status == 'paid'
                                          ? _kGreenBg
                                          : _kOrangeBg,
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: status == 'paid'
                                              ? _kGreen
                                              : _kOrange),
                                    ),
                                  ),
                                ],
                              ]),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'GHS ${NumberFormat('#,##0.00').format(amt)}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _kGreen),
                        ),
                      ]),

                      // ── Commission breakdown ──────────────────────────────────
                      if (commissionTaken > 0 || landlordRec > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: _kPrimary.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: _kPrimary.withOpacity(0.12)),
                          ),
                          child: Row(children: [
                            _CommissionCell(
                              icon: Icons.account_balance_rounded,
                              label: 'Platform commission',
                              value:
                                  'GHS ${NumberFormat('#,##0.00').format(commissionTaken)}',
                              color: _kPrimary,
                            ),
                            Container(
                              width: 1,
                              height: 32,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              color: _kBorder,
                            ),
                            _CommissionCell(
                              icon: Icons.home_work_rounded,
                              label: 'Landlord received',
                              value:
                                  'GHS ${NumberFormat('#,##0.00').format(landlordRec)}',
                              color: _kBlue,
                            ),
                          ]),
                        ),
                      ],
                    ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Small inline badge used inside timeline entries
class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COMMISSION CELL
// ══════════════════════════════════════════════════════════════════════════════
class _CommissionCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _CommissionCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(children: [
          Icon(icon, size: 13, color: color.withOpacity(0.7)),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: color.withOpacity(0.7),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 1),
            Text(value,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ]),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED DETAIL-SHEET WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
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
// HELPERS
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
  final bool isActive; // ← add this
  const _StatusBadge(
      {required this.status, this.large = false, this.isActive = false});

  (Color, Color, String, IconData) get _cfg => switch (status.toLowerCase()) {
        'confirmed' => (
            _kGreen,
            _kGreenBg,
            'Confirmed',
            Icons.check_circle_rounded
          ),
        'active' => (
            _kGreen,
            _kGreenBg,
            'Confirmed',
            Icons.check_circle_rounded
          ), // ← handles old docs
        'declined' => (_kRed, _kRedBg, 'Declined', Icons.cancel_rounded),
        'cancelled' => (_kRed, _kRedBg, 'Cancelled', Icons.cancel_rounded),
        _ => (_kOrange, _kOrangeBg, 'Pending', Icons.schedule_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (color, bg, label, icon) = _cfg;
    final showActive = isActive || status == 'active'; // ← handles old docs too
    // AFTER
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        Container(
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
        ),
        if (showActive)
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: large ? 10 : 6, vertical: large ? 6 : 4),
            decoration: BoxDecoration(
              color: _kBlueBg,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: _kBlue.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.home_rounded, size: large ? 13 : 11, color: _kBlue),
              const SizedBox(width: 4),
              Text('Active',
                  style: TextStyle(
                      fontSize: large ? 12 : 10,
                      fontWeight: FontWeight.w700,
                      color: _kBlue)),
            ]),
          ),
      ],
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
        final sel = o.$1 == current;
        return PopupMenuItem(
          value: o.$1,
          height: 38,
          child: Row(children: [
            Icon(
                sel
                    ? (asc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded)
                    : Icons.sort_rounded,
                size: 14,
                color: sel ? _kPrimary : _kTextLight),
            const SizedBox(width: 10),
            Text(o.$2,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? _kPrimary : _kTextDark)),
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
// LIVE PULSE
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
  const _ConfirmDialog(
      {required this.title,
      required this.message,
      required this.confirmLabel,
      required this.confirmColor});
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
// LOADING / EMPTY / ERROR
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

// ══════════════════════════════════════════════════════════════════════════════
// PRE-BOOKINGS TAB — admin view
// ══════════════════════════════════════════════════════════════════════════════
class _PreBookingsTab extends StatefulWidget {
  const _PreBookingsTab();
  @override
  State<_PreBookingsTab> createState() => _PreBookingsTabState();
}

class _PreBookingsTabState extends State<_PreBookingsTab> {
  String _statusFilter = 'all';
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl
        .addListener(() => setState(() => _searchQuery = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String docId, String status,
      {String? reason}) async {
    final update = <String, dynamic>{
      'status': status,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (reason != null) update['lost_reason'] = reason;
    await _db.collection('pre_bookings').doc(docId).update(update);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Search + filters
      Container(
        color: _kCard,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search hostel, room, student…',
                  hintStyle: const TextStyle(fontSize: 13, color: _kTextLight),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: _kTextLight),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () => _searchCtrl.clear(),
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
            for (final entry in {
              'all': 'All',
              'active': 'Active',
              'converted': 'Converted',
              'expired': 'Expired',
              'lost': 'Lost',
            }.entries)
              _FilterChip(
                label: entry.value,
                selected: _statusFilter == entry.key,
                color: _statusChipColor(entry.key),
                onTap: () => setState(() => _statusFilter = entry.key),
              ),
          ],
        ),
      ),

      // Live stream list
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: _statusFilter == 'all'
              ? _db
                  .collection('pre_bookings')
                  .orderBy('created_at', descending: true)
                  .snapshots()
              : _db
                  .collection('pre_bookings')
                  .where('status', isEqualTo: _statusFilter)
                  .orderBy('created_at', descending: true)
                  .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingGrid();
            }
            if (snap.hasError) {
              return _ErrorBox(message: snap.error.toString());
            }

            var docs = snap.data?.docs ?? [];

            // Search filter
            if (_searchQuery.trim().isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              docs = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['hostel_name'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(q) ||
                    (data['room_number'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(q) ||
                    (data['student_name'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(q) ||
                    (data['email'] ?? '').toString().toLowerCase().contains(q);
              }).toList();
            }

            // Stats
            final allDocs = snap.data?.docs ?? [];
            final activeCount = allDocs
                .where((d) => (d.data() as Map)['status'] == 'active')
                .length;
            final convertedCount = allDocs
                .where((d) => (d.data() as Map)['status'] == 'converted')
                .length;
            final expiredCount = allDocs
                .where((d) => (d.data() as Map)['status'] == 'expired')
                .length;
            final lostCount = allDocs
                .where((d) => (d.data() as Map)['status'] == 'lost')
                .length;

            if (docs.isEmpty) {
              return _EmptyBox(
                  isFiltered:
                      _searchQuery.isNotEmpty || _statusFilter != 'all');
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stats row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _StatChip(
                        label: 'Active',
                        value: '$activeCount',
                        icon: Icons.bookmark_rounded,
                        color: _kPrimary,
                        bg: _kBlueBg),
                    const SizedBox(width: 10),
                    _StatChip(
                        label: 'Converted',
                        value: '$convertedCount',
                        icon: Icons.check_circle_rounded,
                        color: _kGreen,
                        bg: _kGreenBg),
                    const SizedBox(width: 10),
                    _StatChip(
                        label: 'Expired',
                        value: '$expiredCount',
                        icon: Icons.timer_off_rounded,
                        color: _kOrange,
                        bg: _kOrangeBg),
                    const SizedBox(width: 10),
                    _StatChip(
                        label: 'Lost',
                        value: '$lostCount',
                        icon: Icons.cancel_rounded,
                        color: _kRed,
                        bg: _kRedBg),
                  ]),
                ),
                const SizedBox(height: 16),

                // Cards
                ...docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final status = d['status'] as String? ?? 'active';
                  final expiresTs = d['expires_at'] as Timestamp?;
                  final createdTs = d['created_at'] as Timestamp?;
                  final daysLeft = expiresTs != null
                      ? expiresTs.toDate().difference(DateTime.now()).inDays
                      : null;
                  final isUrgent =
                      daysLeft != null && daysLeft <= 1 && status == 'active';

                  final accentColor = switch (status) {
                    'converted' => _kGreen,
                    'expired' || 'lost' => _kTextLight,
                    _ => isUrgent ? _kOrange : _kPrimary,
                  };

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accentColor.withOpacity(0.25)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.07),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(14)),
                        ),
                        child: Row(children: [
                          Icon(
                            status == 'converted'
                                ? Icons.check_circle_rounded
                                : status == 'active'
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_remove_rounded,
                            color: accentColor,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d['hostel_name'] ?? '—',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: _kTextDark)),
                                  Text('Room ${d['room_number'] ?? '—'}',
                                      style: const TextStyle(
                                          fontSize: 12, color: _kTextMid)),
                                ]),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                    color: accentColor.withOpacity(0.3)),
                              ),
                              child: Text(
                                status == 'active'
                                    ? (daysLeft != null
                                        ? '$daysLeft day${daysLeft == 1 ? '' : 's'} left'
                                        : 'Active')
                                    : status.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: accentColor),
                              ),
                            ),
                          )
                        ]),
                      ),

                      // Body
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          _CardRow(
                              icon: Icons.person_rounded,
                              label: 'Student',
                              value: d['student_name'] ?? '—'),
                          _CardRow(
                              icon: Icons.email_rounded,
                              label: 'Email',
                              value: d['email'] ?? '—'),
                          _CardRow(
                              icon: Icons.phone_rounded,
                              label: 'Phone',
                              value: d['phone'] ?? '—'),
                          _CardRow(
                              icon: Icons.timer_outlined,
                              label: 'Window',
                              value: '${d['visit_window_days'] ?? '—'} days'),
                          if (createdTs != null)
                            _CardRow(
                                icon: Icons.calendar_today_rounded,
                                label: 'Registered',
                                value: _fmtShort(createdTs.toDate())),
                          if (status == 'converted' &&
                              d['converted_booking_id'] != null)
                            _CardRow(
                                icon: Icons.receipt_long_rounded,
                                label: 'Booking ID',
                                value: (d['converted_booking_id'] as String)
                                    .substring(0, 8)
                                    .toUpperCase()),
                          if (status == 'lost' && d['lost_reason'] != null)
                            _CardRow(
                                icon: Icons.info_outline_rounded,
                                label: 'Reason',
                                value: d['lost_reason']),
                        ]),
                      ),

                      if (status == 'active')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _SmallActionBtn(
                                label: 'Mark Converted',
                                icon: Icons.check_circle_rounded,
                                color: _kGreen,
                                onTap: () => _updateStatus(doc.id, 'converted'),
                              ),
                              _SmallActionBtn(
                                label: 'Mark Expired',
                                icon: Icons.timer_off_rounded,
                                color: _kOrange,
                                onTap: () => _updateStatus(doc.id, 'expired'),
                              ),
                              _SmallActionBtn(
                                label: 'Mark Lost',
                                icon: Icons.cancel_rounded,
                                color: _kRed,
                                onTap: () => _updateStatus(doc.id, 'lost',
                                    reason: 'Marked lost by admin'),
                              ),
                            ],
                          ),
                        ),
                    ]),
                  );
                }),
              ],
            );
          },
        ),
      ),
    ]);
  }

  Color _statusChipColor(String s) => switch (s) {
        'active' => _kPrimary,
        'converted' => _kGreen,
        'expired' => _kOrange,
        'lost' => _kRed,
        _ => _kTextMid,
      };
}
