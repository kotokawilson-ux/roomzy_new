// lib/screens/landlord/bookings/landlord_bookings.dart
// ╔══════════════════════════════════════════════════════════════════════════╗
// ║ LANDLORD BOOKINGS — Live, Advanced, Real-time View                      ║
// ╚══════════════════════════════════════════════════════════════════════════╝
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/landlord_service.dart';

class _C {
  static const pageBg = Color(0xFFF5F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF1F2937);
  static const textMid = Color(0xFF475569);
  static const textMuted = Color(0xFF9CA3AF);
  static const green = Color(0xFF2D6A4F);
  static const greenAccent = Color(0xFF40916C);
  static const greenLight = Color(0xFFD8F3DC);
  static const greenFaint = Color(0xFFF0FAF3);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFEF3C7);
  static const red = Color(0xFFEF4444);
  static const redLight = Color(0xFFFEE2E2);
  static const blue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFFDBEAFE);
  static const dark = Color(0xFF111827);
  static const teal = Color(0xFF0D9488);
  static const tealLight = Color(0xFFCCFBF1);
}

FirebaseFirestore get _db => FirebaseFirestore.instance;

String _fmtDate(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d);
String _fmtShort(DateTime d) => DateFormat('dd MMM yy').format(d);

Future<void> _decrementRoomSlots(String roomId, int slots) async {
  await _db.runTransaction((txn) async {
    final ref = _db.collection('rooms').doc(roomId);
    final snap = await txn.get(ref);
    if (!snap.exists) return;
    final current = (snap.data()?['booked'] ?? 0) as int;
    txn.update(ref, {'booked': (current - slots).clamp(0, 999999)});
  });
}

Future<void> _incrementRoomSlots(String roomId, int slots) async {
  await _db.runTransaction((txn) async {
    final ref = _db.collection('rooms').doc(roomId);
    final snap = await txn.get(ref);
    if (!snap.exists) return;
    final booked = (snap.data()?['booked'] ?? 0) as int;
    final capacity = (snap.data()?['capacity'] ?? 1) as int;
    if (booked + slots > capacity) throw Exception('Not enough slots');
    txn.update(ref, {'booked': FieldValue.increment(slots)});
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class LandlordBookingsScreen extends StatefulWidget {
  const LandlordBookingsScreen({
    super.key,
    required this.landlordId,
    required this.service,
  });

  final String landlordId;
  final LandlordService service;

  @override
  State<LandlordBookingsScreen> createState() => _LandlordBookingsScreenState();
}

class _LandlordBookingsScreenState extends State<LandlordBookingsScreen>
    with TickerProviderStateMixin {
  String _statusFilter = 'all';
  String _searchQuery = '';
  String _sortField = 'booked_at';
  bool _sortAsc = false;

  final _searchCtrl = TextEditingController();

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    debugPrint('🔑 landlordId: "${widget.landlordId}"');
    widget.service.getHostels(widget.landlordId).then((hostels) {
      debugPrint('🏠 Hostels found: ${hostels.length}');
      debugPrint('🏠 Hostel IDs: ${hostels.map((h) => h.id).toList()}');
      if (hostels.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('bookings')
            .where('hostel_id',
                whereIn: hostels.map((h) => h.id).take(30).toList())
            .get()
            .then(
                (snap) => debugPrint('📋 Bookings found: ${snap.docs.length}'))
            .catchError((e) => debugPrint('❌ Bookings error: $e'));
      }
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Booking> _applyFilters(List<Booking> all) {
    var result = List<Booking>.from(all);

    if (_statusFilter != 'all') {
      result = result.where((b) {
        if (_statusFilter == 'cancelled') {
          return b.status == 'cancelled' || b.status == 'declined';
        }
        return b.status == _statusFilter;
      }).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((b) =>
              b.name.toLowerCase().contains(q) ||
              b.email.toLowerCase().contains(q) ||
              b.phone.toLowerCase().contains(q) ||
              b.hostelName.toLowerCase().contains(q) ||
              b.roomNumber.toLowerCase().contains(q))
          .toList();
    }

    result.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case 'name':
          cmp = a.name.compareTo(b.name);
        case 'status':
          cmp = a.status.compareTo(b.status);
        default:
          cmp = a.bookedAt.compareTo(b.bookedAt);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: StreamBuilder<List<Booking>>(
          stream: widget.service.streamBookings(widget.landlordId),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: _C.green));
            }
            if (snap.hasError) {
              return _ErrorBox(message: snap.error.toString());
            }

            final allBookings = snap.data ?? [];
            final filtered = _applyFilters(allBookings);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(
                  allBookings: allBookings,
                  searchCtrl: _searchCtrl,
                  statusFilter: _statusFilter,
                  sortField: _sortField,
                  sortAsc: _sortAsc,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onFilterChanged: (v) => setState(() => _statusFilter = v),
                  onSortChanged: (f, a) => setState(() {
                    _sortField = f;
                    _sortAsc = a;
                  }),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyBox(
                          isFiltered:
                              _searchQuery.isNotEmpty || _statusFilter != 'all')
                      : _BookingsList(bookings: filtered),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TOP BAR
// ══════════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.allBookings,
    required this.searchCtrl,
    required this.statusFilter,
    required this.sortField,
    required this.sortAsc,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  final List<Booking> allBookings;
  final TextEditingController searchCtrl;
  final String statusFilter;
  final String sortField;
  final bool sortAsc;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;
  final void Function(String, bool) onSortChanged;

  @override
  Widget build(BuildContext context) {
    final total = allBookings.length;
    final confirmed = allBookings.where((b) => b.status == 'confirmed').length;
    final pending = allBookings
        .where((b) => b.status == 'booked' || b.status == 'pending')
        .length;
    final cancelled = allBookings
        .where((b) => b.status == 'cancelled' || b.status == 'declined')
        .length;

    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1B4332), _C.green],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.book_online_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Bookings',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _C.textDark,
                    letterSpacing: -0.3)),
            const Spacer(),
            const _LivePulse(),
          ]),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatChip(
                  label: 'Total',
                  value: '$total',
                  icon: Icons.receipt_long_rounded,
                  color: _C.blue,
                  bg: _C.blueLight),
              const SizedBox(width: 10),
              _StatChip(
                  label: 'Confirmed',
                  value: '$confirmed',
                  icon: Icons.check_circle_rounded,
                  color: _C.green,
                  bg: _C.greenLight),
              const SizedBox(width: 10),
              _StatChip(
                  label: 'Pending',
                  value: '$pending',
                  icon: Icons.schedule_rounded,
                  color: _C.amber,
                  bg: _C.amberLight),
              const SizedBox(width: 10),
              _StatChip(
                  label: 'Cancelled',
                  value: '$cancelled',
                  icon: Icons.cancel_rounded,
                  color: _C.red,
                  bg: _C.redLight),
            ]),
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
                    hintText: 'Search name, room, hostel…',
                    hintStyle:
                        const TextStyle(fontSize: 13, color: _C.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: _C.textMuted),
                    suffixIcon: searchCtrl.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              searchCtrl.clear();
                              onSearchChanged('');
                            },
                            child: const Icon(Icons.close_rounded,
                                size: 16, color: _C.textMuted))
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    filled: true,
                    fillColor: _C.pageBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _C.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _C.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _C.green, width: 1.5)),
                  ),
                ),
              ),
              ...[
                ('all', 'All'),
                ('booked', 'Pending'),
                ('confirmed', 'Confirmed'),
                ('cancelled', 'Cancelled'),
              ].map((t) => _FilterChip(
                    label: t.$2,
                    selected: statusFilter == t.$1,
                    color: _chipColor(t.$1),
                    onTap: () => onFilterChanged(t.$1),
                  )),
              _SortMenu(
                  current: sortField, asc: sortAsc, onChanged: onSortChanged),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Color _chipColor(String s) => switch (s) {
        'confirmed' => _C.green,
        'cancelled' => _C.red,
        'booked' => _C.amber,
        _ => _C.blue,
      };
}

// ══════════════════════════════════════════════════════════════════════════════
// LIST / TABLE / CARDS
// ══════════════════════════════════════════════════════════════════════════════

class _BookingsList extends StatelessWidget {
  const _BookingsList({required this.bookings});
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) => MediaQuery.of(context).size.width > 800
      ? _BookingsTable(bookings: bookings)
      : _BookingsCards(bookings: bookings);
}

class _BookingsTable extends StatelessWidget {
  const _BookingsTable({required this.bookings});
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.border),
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
                  color: _C.pageBg,
                  border: Border(bottom: BorderSide(color: _C.border)),
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
              ...bookings
                  .asMap()
                  .entries
                  .map((e) => _TableRow(booking: e.value, index: e.key)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Showing ${bookings.length} booking${bookings.length != 1 ? 's' : ''}',
            style: const TextStyle(
                fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _TH extends StatelessWidget {
  const _TH(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _C.textMuted,
          letterSpacing: 0.5));
}

class _TableRow extends StatefulWidget {
  const _TableRow({required this.booking, required this.index});
  final Booking booking;
  final int index;
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
    final b = widget.booking;
    return FadeTransition(
      opacity: _anim,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _hovered ? _C.green.withOpacity(0.03) : Colors.transparent,
            border:
                const Border(bottom: BorderSide(color: _C.border, width: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Row(children: [
                _Avatar(name: b.name, status: b.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _C.textDark)),
                        Text(b.email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: _C.textMuted)),
                      ]),
                ),
              ]),
            ),
            Expanded(
              flex: 3,
              child: Text(b.hostelName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.textDark)),
            ),
            Expanded(
              flex: 2,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.roomNumber,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _C.textDark)),
                    if (b.slotsBooked > 0)
                      Text('${b.slotsBooked} slot(s)',
                          style: const TextStyle(
                              fontSize: 11, color: _C.textMuted)),
                  ]),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.amount > 0
                        ? 'GHS ${NumberFormat('#,##0.00').format(b.amount)}'
                        : '—',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: b.amount > 0 ? _C.green : _C.textMuted),
                  ),
                  if (b.amountPaid > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Paid: GHS ${NumberFormat('#,##0.00').format(b.amountPaid)}',
                      style: const TextStyle(fontSize: 10, color: _C.green),
                    ),
                    if (b.balance > 0)
                      Text(
                        'Bal: GHS ${NumberFormat('#,##0.00').format(b.balance)}',
                        style: const TextStyle(fontSize: 10, color: _C.amber),
                      ),
                  ],
                ],
              ),
            ),
            Expanded(flex: 2, child: _StatusBadge(status: b.status)),
            Expanded(
              flex: 2,
              child: Text(_fmtShort(b.bookedAt),
                  style: const TextStyle(fontSize: 12, color: _C.textMid)),
            ),
            SizedBox(width: 44, child: _ActionBtn(booking: b)),
          ]),
        ),
      ),
    );
  }
}

// ── CARD VIEW ─────────────────────────────────────────────────────────────────

class _BookingsCards extends StatelessWidget {
  const _BookingsCards({required this.bookings});
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _BookingCard(booking: bookings[i], index: i),
    );
  }
}

class _BookingCard extends StatefulWidget {
  const _BookingCard({required this.booking, required this.index});
  final Booking booking;
  final int index;
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
    final b = widget.booking;
    final headerBg = switch (b.status) {
      'confirmed' => _C.greenLight,
      'cancelled' || 'declined' => _C.redLight,
      _ => _C.amberLight,
    };

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.border),
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
                color: headerBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                _Avatar(name: b.name, status: b.status, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: _C.textDark)),
                        Text(b.email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: _C.textMid)),
                      ]),
                ),
                _StatusBadge(status: b.status),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _CardRow(
                    icon: Icons.apartment_rounded,
                    label: 'Hostel',
                    value: b.hostelName),
                _CardRow(
                    icon: Icons.bed_rounded,
                    label: 'Room',
                    value: '${b.roomNumber}  ·  ${b.slotsBooked} slot(s)'),
                _CardRow(
                    icon: Icons.phone_rounded,
                    label: 'Phone',
                    value: b.phone.isNotEmpty ? b.phone : '—'),
                _CardRow(
                    icon: Icons.payments_rounded,
                    label: 'Amount',
                    value: b.amount > 0
                        ? 'GHS ${NumberFormat('#,##0.00').format(b.amount)}'
                        : '—',
                    valueColor: b.amount > 0 ? _C.green : null),
                if (b.amountPaid > 0)
                  _CardRow(
                      icon: Icons.check_circle_rounded,
                      label: 'Paid',
                      value:
                          'GHS ${NumberFormat('#,##0.00').format(b.amountPaid)}',
                      valueColor: _C.green),
                if (b.balance > 0)
                  _CardRow(
                      icon: Icons.pending_rounded,
                      label: 'Balance',
                      value:
                          'GHS ${NumberFormat('#,##0.00').format(b.balance)}',
                      valueColor: _C.amber),
                _CardRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Booked',
                    value: _fmtShort(b.bookedAt)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _C.border))),
              child: Row(children: [
                Expanded(
                  child: _SmallBtn(
                    label: 'View Details',
                    icon: Icons.visibility_rounded,
                    color: _C.blue,
                    onTap: () => _showDetail(context, b),
                  ),
                ),
                const SizedBox(width: 8),
                _ActionBtn(booking: b),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 14, color: _C.green),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12,
                  color: _C.textMuted,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? _C.textDark)),
          ),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// ACTION BUTTON
// ══════════════════════════════════════════════════════════════════════════════

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.booking});
  final Booking booking;

  Future<void> _setStatus(BuildContext ctx, String newStatus) async {
    try {
      final snap = await _db.collection('bookings').doc(booking.id).get();
      final oldStatus = (snap.data()?['status'] ?? 'booked') as String;

      await _db.collection('bookings').doc(booking.id).update({
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (booking.roomId.isNotEmpty) {
        if ((newStatus == 'cancelled' ||
                newStatus == 'declined' ||
                newStatus == 'booked') &&
            oldStatus == 'confirmed') {
          await _decrementRoomSlots(booking.roomId, booking.slotsBooked);
        }
        // Never increment — slots already booked when student paid
      }

      if (ctx.mounted) _snack(ctx, _msg(newStatus), _color(newStatus));
    } catch (e) {
      if (ctx.mounted) _snack(ctx, 'Error: $e', _C.red);
    }
  }

  Future<void> _delete(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Booking',
        message:
            'This will permanently remove the booking for ${booking.name}.',
        confirmLabel: 'Delete',
        confirmColor: _C.red,
      ),
    );
    if (ok != true || !ctx.mounted) return;
    try {
      if (booking.roomId.isNotEmpty && booking.isConfirmed) {
        await _decrementRoomSlots(booking.roomId, booking.slotsBooked);
      }

      // Delete payments subcollection first to avoid ghost documents
      final paymentsSnap = await _db
          .collection('bookings')
          .doc(booking.id)
          .collection('payments')
          .get();
      for (final doc in paymentsSnap.docs) {
        await doc.reference.delete();
      }

      await _db.collection('bookings').doc(booking.id).delete();
      if (ctx.mounted) _snack(ctx, 'Booking deleted', _C.red);
    } catch (e) {
      if (ctx.mounted) _snack(ctx, 'Error: $e', _C.red);
    }
  }

  String _msg(String s) => switch (s) {
        'confirmed' => '✅ Booking confirmed',
        'cancelled' || 'declined' => '❌ Booking cancelled',
        _ => '🔄 Reset to pending',
      };

  Color _color(String s) => switch (s) {
        'confirmed' => _C.green,
        'cancelled' || 'declined' => _C.red,
        _ => _C.amber,
      };

  void _snack(BuildContext ctx, String msg, Color color) {
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
    final status = booking.status;
    return PopupMenuButton<String>(
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _C.pageBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _C.border),
        ),
        child:
            const Icon(Icons.more_vert_rounded, size: 16, color: _C.textMuted),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      onSelected: (v) {
        if (v == 'view') {
          _showDetail(context, booking);
          return;
        }
        if (v == 'delete') {
          _delete(context);
          return;
        }
        _setStatus(context, v);
      },
      itemBuilder: (_) => [
        _mi('view', Icons.visibility_rounded, 'View Details', _C.blue),
        const PopupMenuDivider(),
        if (status != 'confirmed')
          _mi('confirmed', Icons.check_circle_rounded, 'Confirm Booking',
              _C.green),
        if (status != 'cancelled' && status != 'declined')
          _mi('declined', Icons.cancel_rounded, 'Cancel Booking', _C.red),
        if (status != 'booked')
          _mi('booked', Icons.refresh_rounded, 'Reset to Pending', _C.amber),
        const PopupMenuDivider(),
        _mi('delete', Icons.delete_outline_rounded, 'Delete Booking', _C.red),
      ],
    );
  }

  PopupMenuItem<String> _mi(
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
                color: value == 'delete' ? _C.red : _C.textDark,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DETAIL BOTTOM SHEET — Live StreamBuilder, matches admin bookings_pane.dart
// ══════════════════════════════════════════════════════════════════════════════

void _showDetail(BuildContext ctx, Booking b) {
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DetailSheet(bookingId: b.id),
  );
}

/// Live detail sheet — streams the booking doc so any payment update
/// (progress bar, balance, timeline) is reflected without closing/reopening.
class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.bookingId});
  final String bookingId;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  Future<void> _confirm(BuildContext ctx, Booking booking) async {
    try {
      await _db.collection('bookings').doc(booking.id).update(
          {'status': 'confirmed', 'updated_at': FieldValue.serverTimestamp()});
      // No slot change — slots already incremented when student paid
      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _C.red,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _cancel(BuildContext ctx, Booking booking) async {
    try {
      final snap = await _db.collection('bookings').doc(booking.id).get();
      final oldStatus = (snap.data()?['status'] ?? 'booked') as String;

      await _db.collection('bookings').doc(booking.id).update(
          {'status': 'declined', 'updated_at': FieldValue.serverTimestamp()});

      if (booking.roomId.isNotEmpty && oldStatus == 'confirmed') {
        await _decrementRoomSlots(booking.roomId, booking.slotsBooked);
      }
      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _C.red,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('bookings').doc(widget.bookingId).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const Center(
              child: CircularProgressIndicator(color: _C.green));
        }

        final data = snap.data!.data() as Map<String, dynamic>;
        // Reconstruct a Booking from live data so every field reflects latest
        final b = Booking.fromJson(widget.bookingId, data);
        final isWide = MediaQuery.of(context).size.width > 700;

        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          maxChildSize: 0.97,
          minChildSize: 0.5,
          builder: (_, ctrl) => Container(
            decoration: const BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: _C.border, borderRadius: BorderRadius.circular(2)),
              ),
              // Gradient header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF1B4332), _C.green],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Row(children: [
                  _Avatar(name: b.name, status: b.status, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          Text(b.email,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.85))),
                        ]),
                  ),
                  _StatusBadge(status: b.status, large: true),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ]),
              ),
              // Scrollable body
              Expanded(
                child: SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Summary card ─────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            _C.green.withOpacity(0.06),
                            _C.greenAccent.withOpacity(0.04),
                          ]),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _C.green.withOpacity(0.15)),
                        ),
                        child: isWide
                            ? Row(children: [
                                Expanded(
                                    child: _SumCell('Hostel', b.hostelName)),
                                Expanded(child: _SumCell('Room', b.roomNumber)),
                                Expanded(
                                    child:
                                        _SumCell('Slots', '${b.slotsBooked}')),
                                Expanded(
                                  child: _SumCell(
                                    'Amount',
                                    b.amount > 0
                                        ? 'GHS ${NumberFormat('#,##0.00').format(b.amount)}'
                                        : '—',
                                    valueColor: b.amount > 0 ? _C.green : null,
                                  ),
                                ),
                              ])
                            : Wrap(
                                spacing: 16,
                                runSpacing: 12,
                                children: [
                                  _SumCell('Hostel', b.hostelName),
                                  _SumCell('Room', b.roomNumber),
                                  _SumCell('Slots', '${b.slotsBooked}'),
                                  _SumCell(
                                    'Amount',
                                    b.amount > 0
                                        ? 'GHS ${NumberFormat('#,##0.00').format(b.amount)}'
                                        : '—',
                                    valueColor: b.amount > 0 ? _C.green : null,
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

                      // ── Payment Progress Bar ──────────────────────────
                      if (b.amount > 0)
                        _PaymentProgressBar(
                          total: b.amount,
                          paid: b.amountPaid,
                          balance: b.balance,
                          paymentStatus: b.paymentStatus,
                        ),
                      if (b.amount > 0) const SizedBox(height: 16),

                      // ── Personal Info ─────────────────────────────────
                      _Section(title: 'Personal Info', children: [
                        _Tile(Icons.person_rounded, 'Full Name', b.name),
                        _Tile(Icons.email_rounded, 'Email', b.email,
                            copyable: true),
                        _Tile(Icons.phone_rounded, 'Phone',
                            b.phone.isNotEmpty ? b.phone : '—',
                            copyable: true),
                      ]),
                      const SizedBox(height: 16),

                      // ── Academic Info ─────────────────────────────────
                      _Section(title: 'Academic Info', children: [
                        _Tile(Icons.school_rounded, 'School',
                            b.school.isNotEmpty ? b.school : '—'),
                        _Tile(Icons.badge_rounded, 'School ID',
                            b.schoolId.isNotEmpty ? b.schoolId : '—'),
                        _Tile(Icons.person_off_rounded, 'Is Student',
                            b.notStudent ? 'No' : 'Yes'),
                      ]),
                      const SizedBox(height: 16),

                      // ── Payment Info ──────────────────────────────────
                      _Section(title: 'Payment Info', children: [
                        _Tile(Icons.payment_rounded, 'Method',
                            b.paymentMethod.isNotEmpty ? b.paymentMethod : '—'),
                        _Tile(Icons.phone_android_rounded, 'MoMo Number',
                            b.momoNumber.isNotEmpty ? b.momoNumber : '—',
                            copyable: true),
                        _Tile(
                            Icons.receipt_rounded,
                            'Reference',
                            b.paymentReference.isNotEmpty
                                ? b.paymentReference
                                : '—',
                            copyable: true),
                        // payment_status (from payments subcollection)
                        _Tile(Icons.credit_score_rounded, 'Payment Status',
                            b.paymentStatus.isNotEmpty ? b.paymentStatus : '—'),
                        // booking status (workflow status)
                        _Tile(Icons.flag_rounded, 'Booking Status', b.status),
                        // commission_rate
                        _CommissionCell(
                            commissionRate: data['commission_rate']),
                        _Tile(
                            Icons.savings_rounded,
                            'Total Amount',
                            b.amount > 0
                                ? 'GHS ${NumberFormat('#,##0.00').format(b.amount)}'
                                : '—'),
                        _Tile(Icons.check_rounded, 'Amount Paid',
                            'GHS ${NumberFormat('#,##0.00').format(b.amountPaid)}'),
                        _Tile(
                            Icons.pending_rounded,
                            'Balance Remaining',
                            b.balance > 0
                                ? 'GHS ${NumberFormat('#,##0.00').format(b.balance)}'
                                : '—'),
                        _Tile(
                            Icons.account_balance_wallet_rounded,
                            'Deposit Amount',
                            b.depositAmount > 0
                                ? 'GHS ${NumberFormat('#,##0.00').format(b.depositAmount)}'
                                : '—'),
                        // payment count
                        StreamBuilder<QuerySnapshot>(
                          stream: _db
                              .collection('bookings')
                              .doc(b.id)
                              .collection('payments')
                              .snapshots(),
                          builder: (_, ps) {
                            final count = ps.data?.docs.length ?? 0;
                            return _Tile(
                                Icons.format_list_numbered_rounded,
                                'Payment Count',
                                count == 0
                                    ? '—'
                                    : '$count instalment${count != 1 ? 's' : ''}');
                          },
                        ),
                      ]),
                      const SizedBox(height: 16),

                      // ── Booking Info ──────────────────────────────────
                      _Section(title: 'Booking Info', children: [
                        _Tile(Icons.calendar_today_rounded, 'Booked At',
                            _fmtDate(b.bookedAt)),
                        if (b.notes.isNotEmpty)
                          _Tile(Icons.notes_rounded, 'Notes', b.notes),
                        _Tile(Icons.fingerprint_rounded, 'Booking ID', b.id,
                            copyable: true, small: true),
                      ]),
                      const SizedBox(height: 24),

                      // ── Advanced Payment Timeline ─────────────────────
                      _PaymentTimeline(
                        bookingId: b.id,
                        totalAmount: b.amount,
                        commissionRate:
                            (data['commission_rate'] ?? 0.0).toDouble(),
                      ),
                      const SizedBox(height: 24),

                      // ── Action buttons ────────────────────────────────
                      Row(children: [
                        if (!b.isConfirmed)
                          Expanded(
                            child: _BigBtn(
                              label: 'Confirm',
                              icon: Icons.check_circle_rounded,
                              color: _C.green,
                              onTap: () => _confirm(context, b),
                            ),
                          ),
                        if (!b.isConfirmed &&
                            b.status != 'cancelled' &&
                            b.status != 'declined')
                          const SizedBox(width: 10),
                        if (b.status != 'cancelled' && b.status != 'declined')
                          Expanded(
                            child: _BigBtn(
                              label: 'Cancel',
                              icon: Icons.cancel_rounded,
                              color: _C.red,
                              onTap: () => _cancel(context, b),
                            ),
                          ),
                      ]),
                    ],
                  ),
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
  const _PaymentProgressBar({
    required this.total,
    required this.paid,
    required this.balance,
    required this.paymentStatus,
  });

  final double total, paid, balance;
  final String paymentStatus;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final isFullyPaid = balance <= 0;
    final barColor = isFullyPaid ? _C.green : _C.teal;
    final fmt = NumberFormat('#,##0.00');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.dark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_rounded,
              size: 15, color: Colors.white70),
          const SizedBox(width: 8),
          const Text('Payment Progress',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.4)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isFullyPaid
                  ? _C.green.withOpacity(0.3)
                  : _C.teal.withOpacity(0.25),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isFullyPaid ? _C.greenLight : _C.tealLight),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        // progress track
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _ProgCell(
              label: 'Paid', value: 'GHS ${fmt.format(paid)}', color: _C.green),
          const SizedBox(width: 20),
          _ProgCell(
              label: 'Balance',
              value: balance > 0 ? 'GHS ${fmt.format(balance)}' : '—',
              color: balance > 0 ? _C.amber : Colors.white54),
          const Spacer(),
          _ProgCell(
              label: 'Total',
              value: 'GHS ${fmt.format(total)}',
              color: Colors.white70),
        ]),
      ]),
    );
  }
}

class _ProgCell extends StatelessWidget {
  const _ProgCell(
      {required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ],
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// PAYMENT TIMELINE — advanced, with commission breakdown per instalment
// ══════════════════════════════════════════════════════════════════════════════

class _PaymentTimeline extends StatelessWidget {
  const _PaymentTimeline({
    required this.bookingId,
    required this.totalAmount,
    required this.commissionRate,
  });

  final String bookingId;
  final double totalAmount;
  final double commissionRate;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('bookings')
          .doc(bookingId)
          .collection('payments')
          .orderBy('paid_at', descending: false)
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
                    color: _C.green, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('Payment Timeline',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _C.textDark)),
            const Spacer(),
            Text('${docs.length} instalment${docs.length != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 11, color: _C.textMuted)),
          ]),
          const SizedBox(height: 12),
          ...docs.asMap().entries.map((entry) {
            final i = entry.key;
            final doc = entry.value;
            final p = doc.data() as Map<String, dynamic>;
            final isLast = i == docs.length - 1;

            final ts = p['paid_at'];
            final date = ts is Timestamp ? ts.toDate() : DateTime.now();
            final amt = (p['amount'] ?? 0).toDouble();
            final method = (p['method'] ?? '').toString().toUpperCase();
            final note = (p['note'] ?? '').toString();
            final status = (p['status'] ?? '').toString();
            final isPaid = status == 'paid';

            // commission breakdown
            // commission breakdown — use stored values from payment doc (same as admin)
            final commission =
                (p['commission_taken'] as num?)?.toDouble() ?? 0.0;
            final landlordReceives =
                (p['landlord_received'] as num?)?.toDouble() ??
                    (amt - commission);
            final rate = amt > 0 ? commission / amt : 0.0;
            // badge logic
            final isTest = note.toLowerCase().contains('test');
            final isFirst = i == 0 && !isTest;
            final isFinal = isLast && docs.length > 1;

            return IntrinsicHeight(
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Timeline spine
                SizedBox(
                  width: 36,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // numbered circle
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isPaid ? _C.green : _C.amber,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: (isPaid ? _C.green : _C.amber)
                                      .withOpacity(0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Center(
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ),
                        // connecting line
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: _C.border,
                            ),
                          ),
                      ]),
                ),
                const SizedBox(width: 12),
                // card
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _C.pageBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _C.border),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // top row: note + badges + amount
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          note.isNotEmpty
                                              ? note
                                              : 'Instalment ${i + 1}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: _C.textDark),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(spacing: 6, children: [
                                          // method badge
                                          if (method.isNotEmpty)
                                            _MiniTag(
                                                method, _C.blue, _C.blueLight),
                                          // status badge
                                          _MiniTag(
                                            isPaid ? 'Paid' : 'Pending',
                                            isPaid ? _C.green : _C.amber,
                                            isPaid
                                                ? _C.greenLight
                                                : _C.amberLight,
                                          ),
                                          if (isTest)
                                            _MiniTag('TEST', _C.textMuted,
                                                _C.border),
                                          if (isFirst)
                                            _MiniTag(
                                                '1st', _C.green, _C.greenFaint),
                                          if (isFinal)
                                            _MiniTag(
                                                'Final', _C.blue, _C.blueLight),
                                        ]),
                                      ]),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'GHS ${NumberFormat('#,##0.00').format(amt)}',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: _C.green),
                                ),
                              ]),
                          // timestamp
                          const SizedBox(height: 6),
                          Text(
                            _fmtDate(date),
                            style: const TextStyle(
                                fontSize: 10, color: _C.textMuted),
                          ),
                          // commission breakdown strip
                          if ((commission > 0 || landlordReceives > 0) &&
                              isPaid) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: _C.green.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: _C.green.withOpacity(0.12)),
                              ),
                              child: Row(children: [
                                _CommissionSplit(
                                  label: 'Platform',
                                  value: commission,
                                  color: _C.red,
                                ),
                                Container(
                                    width: 1,
                                    height: 28,
                                    color: _C.border,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 12)),
                                _CommissionSplit(
                                  label: 'You receive',
                                  value: landlordReceives,
                                  color: _C.green,
                                ),
                                const Spacer(),
                                Text(
                                  '${(rate * 100).toStringAsFixed(0)}% fee',
                                  style: const TextStyle(
                                      fontSize: 10, color: _C.textMuted),
                                ),
                              ]),
                            ),
                          ],
                        ]),
                  ),
                ),
              ]),
            );
          }),
        ]);
      },
    );
  }
}

class _CommissionSplit extends StatelessWidget {
  const _CommissionSplit(
      {required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: _C.textMuted)),
          Text(
            'GHS ${NumberFormat('#,##0.00').format(value)}',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      );
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.label, this.color, this.bg);
  final String label;
  final Color color, bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// COMMISSION CELL — inline in Payment Info section
// ══════════════════════════════════════════════════════════════════════════════

class _CommissionCell extends StatelessWidget {
  const _CommissionCell({required this.commissionRate});
  final dynamic commissionRate;

  @override
  Widget build(BuildContext context) {
    final rawRate =
        commissionRate != null ? (commissionRate as num).toDouble() : null;
    final rate =
        rawRate != null ? (rawRate > 1 ? rawRate / 100 : rawRate) : null;
    final display = rate != null ? '${(rate * 100).toStringAsFixed(1)}%' : '—';
    return _Tile(Icons.percent_rounded, 'Commission Rate', display);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _SumCell extends StatelessWidget {
  const _SumCell(this.label, this.value, {this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: _C.textMuted,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? _C.textDark)),
        ],
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
                color: _C.green, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: _C.textDark)),
      ]),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: _C.pageBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: Column(children: [
          ...children.asMap().entries.map((e) => Column(children: [
                e.value,
                if (e.key < children.length - 1)
                  const Divider(height: 1, color: _C.border, indent: 16),
              ])),
        ]),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.label, this.value,
      {this.copyable = false, this.small = false});
  final IconData icon;
  final String label, value;
  final bool copyable, small;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(icon, size: 16, color: _C.green),
        title: Text(label,
            style: const TextStyle(fontSize: 11, color: _C.textMuted)),
        subtitle: Text(value,
            style: TextStyle(
                fontSize: small ? 11 : 13,
                fontWeight: FontWeight.w700,
                color: _C.textDark,
                fontFamily: small ? 'monospace' : null)),
        trailing: copyable
            ? IconButton(
                icon: const Icon(Icons.copy_rounded,
                    size: 14, color: _C.textMuted),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Copied!'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating),
                  );
                },
              )
            : null,
      );
}

class _BigBtn extends StatelessWidget {
  const _BigBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          shadowColor: color.withOpacity(0.35),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.status, this.size = 32});
  final String name, status;
  final double size;

  Color get _color => switch (status) {
        'confirmed' => _C.green,
        'cancelled' || 'declined' => _C.red,
        _ => _C.amber,
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
  const _StatusBadge({required this.status, this.large = false});
  final String status;
  final bool large;

  (Color, Color, String, IconData) get _cfg => switch (status.toLowerCase()) {
        'confirmed' => (
            _C.green,
            _C.greenLight,
            'Confirmed',
            Icons.check_circle_rounded
          ),
        'cancelled' || 'declined' => (
            _C.red,
            _C.redLight,
            'Cancelled',
            Icons.cancel_rounded
          ),
        _ => (_C.amber, _C.amberLight, 'Pending', Icons.schedule_rounded),
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
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bg,
  });
  final String label, value;
  final IconData icon;
  final Color color, bg;

  @override
  Widget build(BuildContext context) => Container(
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.1) : _C.pageBg,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
                color: selected ? color : _C.border, width: selected ? 1.5 : 1),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : _C.textMid)),
        ),
      );
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({
    required this.current,
    required this.asc,
    required this.onChanged,
  });
  final String current;
  final bool asc;
  final void Function(String, bool) onChanged;

  static const _opts = [
    ('booked_at', 'Date Booked'),
    ('name', 'Name'),
    ('status', 'Status'),
  ];

  @override
  Widget build(BuildContext context) {
    final label =
        _opts.firstWhere((o) => o.$1 == current, orElse: () => _opts[0]).$2;
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      onSelected: (v) {
        if (v == current) {
          onChanged(current, !asc);
        } else {
          onChanged(v, false);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _C.pageBg,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: _C.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14, color: _C.green),
          const SizedBox(width: 6),
          Text('Sort: $label',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.textMid)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 16, color: _C.textMuted),
        ]),
      ),
      itemBuilder: (_) => _opts.map((o) {
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
                color: sel ? _C.green : _C.textMuted),
            const SizedBox(width: 10),
            Text(o.$2,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? _C.green : _C.textDark)),
          ]),
        );
      }).toList(),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
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

class _LivePulse extends StatefulWidget {
  const _LivePulse();
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
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_anim),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _C.greenLight,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: _C.green.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: _C.green, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('Live',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _C.green)),
          ]),
        ),
      );
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });
  final String title, message, confirmLabel;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) => Dialog(
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
                    color: _C.textDark)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: _C.textMid, height: 1.5)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    side: const BorderSide(color: _C.border),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: _C.textMid, fontWeight: FontWeight.w600)),
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

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.isFiltered});
  final bool isFiltered;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _C.pageBg,
              shape: BoxShape.circle,
              border: Border.all(color: _C.border),
            ),
            child: Icon(
                isFiltered
                    ? Icons.search_off_rounded
                    : Icons.book_online_outlined,
                size: 40,
                color: _C.textMuted),
          ),
          const SizedBox(height: 16),
          Text(isFiltered ? 'No results found' : 'No bookings yet',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _C.textMid)),
          const SizedBox(height: 6),
          Text(
              isFiltered
                  ? 'Try adjusting your search or filter'
                  : 'Bookings from students will appear here',
              style: const TextStyle(fontSize: 13, color: _C.textMuted),
              textAlign: TextAlign.center),
        ]),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: _C.red),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _C.textMid, fontSize: 13)),
          ]),
        ),
      );
}
