// lib/screens/bookings/bookings_screen.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/booking_storage_service.dart';
import '../../widgets/navbar.dart';
import '../../widgets/footer.dart';

// ─── Constants ───────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF0F766E);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kOrange = Color(0xFFEA580C);

enum _Filter { all, confirmed, pending, cancelled }

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;
  _Filter _filter = _Filter.all;
  final _searchCtrl = TextEditingController();
  late TabController _tabCtrl;
  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _bookings = [];
          _filtered = [];
          _loading = false;
        });
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('email', isEqualTo: user.email)
          .orderBy('booked_at', descending: true)
          .get();

      final allBookings =
          snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      if (!mounted) return;
      setState(() {
        _bookings = allBookings;
        _filtered = allBookings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _bookings.where((b) {
        final matchSearch = q.isEmpty ||
            (b['hostel_name'] ?? '').toLowerCase().contains(q) ||
            (b['room_number'] ?? '').toLowerCase().contains(q) ||
            (b['id'] ?? '').toLowerCase().contains(q);

        final matchFilter = _filter == _Filter.all ||
            (_filter == _Filter.confirmed && b['status'] == 'confirmed') ||
            (_filter == _Filter.pending &&
                (b['status'] == 'pending' || b['status'] == 'booked')) ||
            (_filter == _Filter.cancelled &&
                (b['status'] == 'cancelled' || b['status'] == 'declined'));

        return matchSearch && matchFilter;
      }).toList();
    });
  }

  void _setFilter(_Filter f) {
    setState(() => _filter = f);
    _applyFilter();
  }

  Future<void> _cancelBooking(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Booking',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _kRed, foregroundColor: Colors.white),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
        'status': 'cancelled',
        'cancelled_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Booking cancelled'), backgroundColor: _kOrange));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _kRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 900;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: const Navbar(),
      endDrawer: const NavbarDrawer(),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Column(children: [
              // ── Header ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 60 : 24, vertical: 40),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_kPrimary, Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('My Bookings',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                      const SizedBox(height: 6),
                      Text('Your hostel booking history',
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8))),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10)
                            ]),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Search by hostel, room…',
                            hintStyle:
                                TextStyle(fontSize: 14, color: Colors.black38),
                            prefixIcon:
                                Icon(Icons.search_rounded, color: _kPrimary),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: TabBar(
                          controller: _tabCtrl,
                          indicator: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelColor: _kPrimary,
                          unselectedLabelColor: Colors.white,
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
                    ]),
              ),

              // ── Stats (Bookings tab only) ────────────────────────
              if (!_loading && _error == null && _bookings.isNotEmpty)
                AnimatedBuilder(
                  animation: _tabCtrl,
                  builder: (_, __) {
                    if (_tabCtrl.index != 0) return const SizedBox.shrink();
                    return Container(
                      color: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: isWide ? 60 : 16, vertical: 16),
                      child: Row(children: [
                        _StatChip(
                            label: 'Total',
                            count: _bookings.length,
                            color: _kPrimary),
                        const SizedBox(width: 10),
                        _StatChip(
                            label: 'Confirmed',
                            count: _bookings
                                .where((b) => b['status'] == 'confirmed')
                                .length,
                            color: _kGreen),
                        const SizedBox(width: 10),
                        _StatChip(
                            label: 'Pending',
                            count: _bookings
                                .where((b) =>
                                    b['status'] == 'pending' ||
                                    b['status'] == 'booked')
                                .length,
                            color: _kOrange),
                        const SizedBox(width: 10),
                        _StatChip(
                            label: 'Cancelled',
                            count: _bookings
                                .where((b) =>
                                    b['status'] == 'cancelled' ||
                                    b['status'] == 'declined')
                                .length,
                            color: _kRed),
                      ]),
                    );
                  },
                ),

              // ── Filter pills (Bookings tab only) ─────────────────
              if (!_loading && _error == null && _bookings.isNotEmpty)
                AnimatedBuilder(
                  animation: _tabCtrl,
                  builder: (_, __) {
                    if (_tabCtrl.index != 0) return const SizedBox.shrink();
                    return Container(
                      color: Colors.white,
                      padding:
                          EdgeInsets.symmetric(horizontal: isWide ? 60 : 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: _Filter.values
                                .map((f) => _FilterTab(
                                      label: f.name[0].toUpperCase() +
                                          f.name.substring(1),
                                      isActive: _filter == f,
                                      onTap: () => _setFilter(f),
                                    ))
                                .toList()),
                      ),
                    );
                  },
                ),
            ]),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            // ── Tab 1: Bookings ──────────────────────────────────
            _loading
                ? _buildShimmer()
                : _error != null
                    ? _buildError()
                    : _filtered.isEmpty
                        ? _buildEmpty()
                        : isWide
                            ? SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 60, vertical: 24),
                                  child: _buildList(true),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 24),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (_, i) => _BookingCard(
                                    booking: _filtered[i],
                                    onCancel: _cancelBooking),
                              ),

            // ── Tab 2: Pre-Bookings ──────────────────────────────
            const _PreBookingsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool isWide) {
    if (isWide) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 1.3,
        ),
        itemCount: _filtered.length,
        itemBuilder: (_, i) =>
            _BookingCard(booking: _filtered[i], onCancel: _cancelBooking),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, i) =>
          _BookingCard(booking: _filtered[i], onCancel: _cancelBooking),
    );
  }

  Widget _buildShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
          children: List.generate(
              3,
              (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(
                          height: 180,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20))),
                    ),
                  ))),
    );
  }

  Widget _buildError() {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey),
        const SizedBox(height: 12),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black45)),
        const SizedBox(height: 16),
        ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: const Text('Retry')),
      ]),
    ));
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hotel_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('No bookings yet',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 8),
          const Text('Bookings you make will appear here',
              style: TextStyle(color: Colors.black45)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/hostels'),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Find a Hostel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Booking Card ─────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final void Function(String) onCancel;
  const _BookingCard({required this.booking, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final id = booking['id'] as String;
    final shortRef = id.toUpperCase().substring(0, 8);
    final status = booking['status'] ?? 'pending';
    final statusDisplay = (status == 'booked') ? 'pending' : status;
    final paymentStatus = booking['payment_status'] ?? 'pending';
    final hostelName = booking['hostel_name'] ?? '—';
    final roomNumber = booking['room_number'] ?? '—';
    final roomType = booking['room_type'] ?? '';
    final slots = booking['slots_booked'] ?? 1;
    final amount = (booking['amount'] ?? 0.0).toDouble();
    final momoType = booking['momo_type'] ?? 'Mobile Money';
    final hostelId = booking['hostel_id'] ?? '';
    final hostelPhone = booking['hostel_phone'] ?? '';
    final canCancel = status == 'pending' || status == 'booked';
    final amountPaid = (booking['amount_paid'] ?? 0.0).toDouble();
    final balance = (booking['balance'] ?? 0.0).toDouble();
    final depositAmount = (booking['deposit_amount'] ?? 0.0).toDouble();
    final statusColor = _statusColor(status);
    final payColor = _payColor(paymentStatus);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border:
                Border(bottom: BorderSide(color: statusColor.withOpacity(0.2))),
          ),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(hostelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _kDark)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: shortRef));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Reference copied!'),
                          duration: Duration(seconds: 2)));
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('REF: $shortRef',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded,
                          size: 12, color: Colors.black38),
                    ]),
                  ),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _StatusBadge(
                  label: statusDisplay.toUpperCase(), color: statusColor),
              const SizedBox(height: 4),
              _StatusBadge(
                  label: paymentStatus == 'fully_paid'
                      ? '✓ FULLY PAID'
                      : paymentStatus == 'deposit_paid'
                          ? '⬤ DEPOSIT PAID'
                          : paymentStatus == 'paid'
                              ? '✓ PAID'
                              : 'UNPAID',
                  color: payColor),
            ]),
          ]),
        ),

        // ── Details ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              _InfoTile(
                  icon: Icons.bed_rounded,
                  label: 'Room',
                  value: '$roomType $roomNumber'.trim()),
              const SizedBox(width: 12),
              _InfoTile(
                  icon: Icons.people_rounded, label: 'Slots', value: '$slots'),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _InfoTile(
                  icon: Icons.payments_rounded,
                  label: 'Total',
                  value: 'GHS ${amount.toStringAsFixed(2)}'),
              const SizedBox(width: 12),
              _InfoTile(
                  icon: Icons.phone_android_rounded,
                  label: 'Payment',
                  value: momoType),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _InfoTile(
                  icon: Icons.check_rounded,
                  label: 'Paid',
                  value:
                      'GHS ${(booking['amount_paid'] ?? 0.0).toStringAsFixed(2)}'),
              const SizedBox(width: 12),
              _InfoTile(
                  icon: Icons.pending_rounded,
                  label: 'Balance',
                  value:
                      'GHS ${(booking['balance'] ?? 0.0).toStringAsFixed(2)}'),
            ]),
          ]),
        ),

        // ── Action buttons ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => context.push('/bookings/$id'),
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('Receipt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                ),
              ),
              if (hostelPhone.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:$hostelPhone')),
                  icon: const Icon(Icons.phone_rounded, size: 16),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPrimary,
                    side: const BorderSide(color: _kPrimary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 16),
                  ),
                ),
              if (canCancel)
                OutlinedButton.icon(
                  onPressed: () => onCancel(id),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: const BorderSide(color: _kRed),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 16),
                  ),
                ),
              if (hostelId.isNotEmpty)
                IconButton(
                  onPressed: () => context.go('/hostels/$hostelId'),
                  icon: const Icon(Icons.apartment_rounded, color: _kPrimary),
                  tooltip: 'View hostel',
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return _kGreen;
      case 'cancelled':
      case 'declined':
        return _kRed;
      default:
        return _kOrange;
    }
  }

  Color _payColor(String status) {
    switch (status) {
      case 'fully_paid':
      case 'paid':
        return _kGreen;
      case 'deposit_paid':
        return _kOrange;
      default:
        return _kRed;
    }
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: _kPrimary),
      const SizedBox(width: 6),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.black45,
                fontWeight: FontWeight.w500)),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _kDark)),
      ])),
    ]));
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text('$count',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
    ));
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _FilterTab(
      {required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: isActive ? _kPrimary : Colors.black12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : Colors.black45)),
      ),
    );
  }
}
// ─── Pre-Bookings Tab ─────────────────────────────────────────────────────────

class _PreBookingsTab extends StatefulWidget {
  const _PreBookingsTab();
  @override
  State<_PreBookingsTab> createState() => _PreBookingsTabState();
}

class _PreBookingsTabState extends State<_PreBookingsTab> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Sign in to view pre-bookings'));
    }

    return CustomScrollView(slivers: [
      // ── Filter pills ──────────────────────────────────────────
      SliverToBoxAdapter(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const [
                  ('all', 'All'),
                  ('active', 'Active'),
                  ('converted', 'Converted'),
                  ('expired', 'Expired'),
                ])
                  GestureDetector(
                    onTap: () => setState(() => _filter = entry.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _filter == entry.$1
                            ? _kPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                            color: _filter == entry.$1
                                ? _kPrimary
                                : Colors.black12),
                      ),
                      child: Text(entry.$2,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _filter == entry.$1
                                  ? Colors.white
                                  : Colors.black45)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),

      // ── Live stream ───────────────────────────────────────────
      StreamBuilder<QuerySnapshot>(
        stream: _filter == 'all'
            ? FirebaseFirestore.instance
                .collection('pre_bookings')
                .where('user_id', isEqualTo: user.uid)
                .orderBy('created_at', descending: true)
                .snapshots()
            : FirebaseFirestore.instance
                .collection('pre_bookings')
                .where('user_id', isEqualTo: user.uid)
                .where('status', isEqualTo: _filter)
                .orderBy('created_at', descending: true)
                .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _kPrimary)),
            );
          }
          if (snap.hasError) {
            return SliverFillRemaining(
              child: Center(
                  child: Text('Error: ${snap.error}',
                      style: const TextStyle(color: Colors.black45))),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bookmark_border_rounded,
                        size: 48, color: Colors.black12),
                    SizedBox(height: 12),
                    Text('No pre-bookings yet',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _kDark)),
                    SizedBox(height: 6),
                    Text('Pre-bookings you register will appear here',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45)),
                  ]),
                ),
              ),
            );
          }

          return SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.separated(
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final status = d['status'] as String? ?? 'active';
                final expiresTs = d['expires_at'] as Timestamp?;
                final daysLeft = expiresTs != null
                    ? expiresTs.toDate().difference(DateTime.now()).inDays
                    : null;
                final isUrgent =
                    daysLeft != null && daysLeft <= 1 && status == 'active';

                final accentColor = switch (status) {
                  'converted' => _kGreen,
                  'expired' => _kOrange,
                  _ => isUrgent ? _kOrange : _kPrimary,
                };

                return Container(
                  // your existing card code here, no changes needed
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accentColor.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Column(children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.07),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                      ),
                      child: Row(children: [
                        Icon(
                            status == 'converted'
                                ? Icons.check_circle_rounded
                                : status == 'expired'
                                    ? Icons.timer_off_rounded
                                    : Icons.bookmark_rounded,
                            color: accentColor,
                            size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['hostel_name'] ?? '—',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: _kDark)),
                                Text('Room ${d['room_number'] ?? '—'}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black45)),
                              ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(50),
                            border:
                                Border.all(color: accentColor.withOpacity(0.3)),
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
                      ]),
                    ),

                    // Body
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Row(children: [
                          _InfoTile(
                              icon: Icons.timer_outlined,
                              label: 'Visit Window',
                              value: '${d['visit_window_days'] ?? '—'} days'),
                        ]),
                        if (status == 'converted' &&
                            d['converted_booking_id'] != null) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            _InfoTile(
                                icon: Icons.receipt_long_rounded,
                                label: 'Booking Ref',
                                value: (d['converted_booking_id'] as String)
                                    .substring(0, 8)
                                    .toUpperCase()),
                          ]),
                        ],
                      ]),
                    ),

                    // Actions
                    if (status == 'active' || status == 'converted')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(children: [
                          if (status == 'active')
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final hostelId =
                                      d['hostel_id'] as String? ?? '';
                                  if (hostelId.isNotEmpty) {
                                    context.go('/hostels/$hostelId');
                                  }
                                },
                                icon: const Icon(Icons.arrow_forward_rounded,
                                    size: 16),
                                label: const Text('Proceed to Book'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kPrimary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(50)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          if (status == 'converted')
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final bookingId =
                                      d['converted_booking_id'] as String? ??
                                          '';
                                  if (bookingId.isNotEmpty) {
                                    context.push('/bookings/$bookingId');
                                  }
                                },
                                icon: const Icon(Icons.receipt_long_rounded,
                                    size: 16),
                                label: const Text('View Receipt'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kGreen,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(50)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                        ]),
                      ),
                  ]), // Column children (card body)
                ); // Container (card)
              }, // itemBuilder
            ), // SliverList.separated
          ); // SliverPadding
        }, // StreamBuilder builder
      ), // StreamBuilder
    ]); // CustomScrollView slivers
  } // build()
}                     // _PreBookingsTabState