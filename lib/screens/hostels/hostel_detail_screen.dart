// lib/screens/hostel/hostel_detail_screen.dart

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import '../../models/models.dart';
import '../../widgets/navbar.dart';
import '../../widgets/footer.dart';

// ─── Constants ───────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF0F766E);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kCard = Colors.white;
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _img(String? v) {
  if (v == null || v.trim().isEmpty)
    return 'https://placehold.co/600x400?text=No+Image';
  return v.trim();
}

List<String> _splitImages(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

List<String> _splitPhone(String? raw) {
  if (raw == null || raw.trim().isEmpty) return ['0200000000'];
  final p = raw
      .split(RegExp(r'[,\s/]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  return p.isEmpty ? ['0200000000'] : p;
}

String _mapSrc(String? iframe) {
  if (iframe == null) return '';
  final cleaned = iframe.replaceAll(r'\"', '"').replaceAll('&amp;', '&');
  return RegExp(r'src="([^"]+)"').firstMatch(cleaned)?.group(1) ?? '';
}

// ─── RoomModel ───────────────────────────────────────────────────────────────

class RoomModel {
  final String id;
  final String roomNumber;
  final String type;
  final int capacity;
  final double price;
  final int booked;
  final bool available;
  final String? image;
  final List<String> images;
  final String? paymentBank;
  final String? paymentMomo;
  final String? paymentCash;
  final String? paymentOther;

  int get remaining => (capacity - booked).clamp(0, capacity);

  RoomModel({
    required this.id,
    required this.roomNumber,
    required this.type,
    required this.capacity,
    required this.price,
    required this.booked,
    required this.available,
    this.image,
    required this.images,
    this.paymentBank,
    this.paymentMomo,
    this.paymentCash,
    this.paymentOther,
  });

  factory RoomModel.fromFirestore(String id, Map<String, dynamic> d) =>
      RoomModel(
        id: id,
        roomNumber: d['room_number'] ?? '',
        type: d['type'] ?? 'Room',
        capacity: _toInt(d['capacity'], 1),
        price: (d['price'] ?? 0).toDouble(),
        booked: _toInt(d['booked'], 0),
        available: (d['available'] ?? 1) == 1,
        image: d['image'],
        images: _splitImages(d['images']),
        paymentBank: d['payment_bank'],
        paymentMomo: d['payment_momo'],
        paymentCash: d['payment_cash'],
        paymentOther: d['payment_other'],
      );

  static int _toInt(dynamic v, int fallback) =>
      v is int ? v : int.tryParse('$v') ?? fallback;

  Map<String, String> get paymentOptions {
    final m = <String, String>{};
    if (paymentBank?.isNotEmpty == true) m['Bank'] = paymentBank!;
    if (paymentMomo?.isNotEmpty == true) m['MoMo'] = paymentMomo!;
    if (paymentCash?.isNotEmpty == true) m['Cash'] = paymentCash!;
    if (paymentOther?.isNotEmpty == true) m['Other'] = paymentOther!;
    return m;
  }

  RoomModel copyWith({required int booked}) => RoomModel(
        id: id,
        roomNumber: roomNumber,
        type: type,
        capacity: capacity,
        price: price,
        booked: booked,
        available: (capacity - booked) > 0,
        image: image,
        images: images,
        paymentBank: paymentBank,
        paymentMomo: paymentMomo,
        paymentCash: paymentCash,
        paymentOther: paymentOther,
      );
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class HostelDetailScreen extends StatefulWidget {
  final String hostelId;
  const HostelDetailScreen({super.key, required this.hostelId});

  @override
  State<HostelDetailScreen> createState() => _HostelDetailScreenState();
}

class _HostelDetailScreenState extends State<HostelDetailScreen> {
  Hostel? _hostel;
  List<RoomModel> _rooms = [];
  List<String> _facilities = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('hostels')
          .doc(widget.hostelId)
          .get();
      if (!doc.exists) throw Exception('Hostel not found');

      final roomsSnap = await FirebaseFirestore.instance
          .collection('rooms')
          .where('hostel_id', isEqualTo: widget.hostelId)
          .get();

      final facSnap = await FirebaseFirestore.instance
          .collection('facilities')
          .where('hostel_id', isEqualTo: widget.hostelId)
          .get();

      if (!mounted) return;
      setState(() {
        _hostel = Hostel.fromJson(doc.id, doc.data()!);
        _rooms = roomsSnap.docs
            .map((d) => RoomModel.fromFirestore(d.id, d.data()))
            .toList();
        _facilities = facSnap.docs
            .map((d) => (d.data()['facility_name'] ?? '') as String)
            .where((f) => f.isNotEmpty)
            .toList();
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

  void _onBooked(String roomId, int slots) {
    setState(() {
      final i = _rooms.indexWhere((r) => r.id == roomId);
      if (i != -1)
        _rooms[i] = _rooms[i].copyWith(booked: _rooms[i].booked + slots);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: _kPrimary)));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
    if (_hostel == null)
      return const Scaffold(body: Center(child: Text('Hostel not found')));

    final hostel = _hostel!;
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 900;
    final heroImages = [
      if (hostel.image?.isNotEmpty == true) hostel.image!,
      ..._splitImages(hostel.images),
    ];
    final mapSrc = _mapSrc(hostel.googleMap);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: const Navbar(),
      endDrawer: const NavbarDrawer(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. HERO ────────────────────────────────────────────────
            _HeroSection(hostelName: hostel.hostelName, images: heroImages),

            // ── 2. INFO ────────────────────────────────────────────────
            _InfoSection(
                hostel: hostel, isWide: isWide, heroImages: heroImages),

            // ── 3. ROOMS ───────────────────────────────────────────────
            _RoomsSection(
                rooms: _rooms,
                hostel: hostel,
                isWide: isWide,
                onBooked: _onBooked),

            // ── 4. FACILITIES ──────────────────────────────────────────
            if (_facilities.isNotEmpty)
              _FacilitiesSection(facilities: _facilities, isWide: isWide),

            // ── 5. LOCATION / MAP ──────────────────────────────────────
            if (mapSrc.isNotEmpty)
              _LocationSection(mapSrc: mapSrc, isWide: isWide),

            // ── 6. FOOTER ──────────────────────────────────────────────
            // ── 6. FOOTER ──────────────────────────────────────────────
            const Footer(),
          ],
        ),
      ),
    );
  }
}

// ─── 1. HERO ─────────────────────────────────────────────────────────────────

class _HeroSection extends StatefulWidget {
  final String hostelName;
  final List<String> images;
  const _HeroSection({required this.hostelName, required this.images});

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          widget.images.isNotEmpty
              ? CarouselSlider(
                  options: CarouselOptions(
                    height: 360,
                    viewportFraction: 1.0,
                    autoPlay: widget.images.length > 1,
                    autoPlayInterval: const Duration(seconds: 5),
                    onPageChanged: (i, _) => setState(() => _current = i),
                  ),
                  items: widget.images
                      .map((img) => Image.network(
                            _img(img),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) =>
                                Container(color: _kDark),
                          ))
                      .toList(),
                )
              : Container(color: _kDark),

          // Gradient overlay — stronger at bottom for text legibility
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x55000000),
                  Color(0xCC000000),
                ],
              ),
            ),
          ),

          // Content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Badge

              const SizedBox(height: 14),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.hostelName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    shadows: [Shadow(blurRadius: 12, color: Colors.black87)],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Breadcrumb
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _breadcrumb('Home', isActive: false),
                  _sep(),
                  _breadcrumb('Hostels / Apartments',
                      isActive: false, isBold: true),
                  _sep(),
                  _breadcrumb(widget.hostelName, isActive: true),
                ],
              ),
            ],
          ),

          // Image dots
          if (widget.images.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: widget.images
                    .asMap()
                    .entries
                    .map((e) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: _current == e.key ? 20 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: Colors.white
                                .withOpacity(_current == e.key ? 1 : 0.4),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _breadcrumb(String t, {required bool isActive, bool isBold = false}) =>
      Text(t,
          style: TextStyle(
            color: isActive ? Colors.white54 : Colors.white,
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ));

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('/', style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
}

// ─── 2. INFO ─────────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final Hostel hostel;
  final bool isWide;
  final List<String> heroImages;
  const _InfoSection(
      {required this.hostel, required this.isWide, required this.heroImages});

  @override
  Widget build(BuildContext context) {
    final phones = _splitPhone(hostel.phone);

    return Container(
      color: _kCard,
      child: Column(
        children: [
          // Top accent strip
          Container(height: 4, color: _kPrimary),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: isWide ? 60 : 20, vertical: 40),
            child: isWide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 6, child: _HeroImageBox(images: heroImages)),
                    const SizedBox(width: 48),
                    Expanded(
                        flex: 5,
                        child: _DetailsBox(hostel: hostel, phones: phones)),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        _HeroImageBox(images: heroImages),
                        const SizedBox(height: 28),
                        _DetailsBox(hostel: hostel, phones: phones),
                      ]),
          ),
        ],
      ),
    );
  }
}

class _HeroImageBox extends StatelessWidget {
  final List<String> images;
  const _HeroImageBox({required this.images});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: images.isNotEmpty
              ? Image.network(
                  _img(images[0]),
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) {
                    if (p == null) return child;
                    return Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(color: Colors.grey[300]),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: _kPrimary.withOpacity(0.08),
                    child: const Center(
                        child: Icon(Icons.apartment_rounded,
                            size: 60, color: _kPrimary)),
                  ),
                )
              : Container(
                  color: _kPrimary.withOpacity(0.08),
                  child: const Center(
                      child: Icon(Icons.apartment_rounded,
                          size: 60, color: _kPrimary)),
                ),
        ),
      ),
    );
  }
}

class _DetailsBox extends StatelessWidget {
  final Hostel hostel;
  final List<String> phones;
  const _DetailsBox({required this.hostel, required this.phones});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name
        Text(hostel.hostelName,
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _kDark,
                height: 1.2)),
        const SizedBox(height: 8),

        // Location row
        Row(children: [
          const Icon(Icons.location_on_rounded, size: 16, color: _kPrimary),
          const SizedBox(width: 4),
          Text('${hostel.town ?? ''}, Ghana',
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 16),

        // Price pill
        if (hostel.priceRange != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF16A34A), Color(0xFF15803D)]),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                    color: _kGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Text(
              '${hostel.priceRange!}  ·  ${hostel.durationType ?? 'per year'}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),

        const SizedBox(height: 16),

        // Description
        if (hostel.description?.isNotEmpty == true) ...[
          Text(hostel.description!,
              style: const TextStyle(
                  fontSize: 14, color: Colors.black54, height: 1.65)),
          const SizedBox(height: 16),
        ],

        // School
        if (hostel.schoolName?.isNotEmpty == true)
          _InfoChip(
            icon: Icons.school_rounded,
            text: hostel.schoolShortName != null
                ? '${hostel.schoolName} (${hostel.schoolShortName})'
                : hostel.schoolName!,
            color: _kPrimary,
          ),

        const SizedBox(height: 12),

        // Phone enquiry
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kPrimary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPrimary.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('For enquiries or details call:',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: phones
                    .map((p) => GestureDetector(
                          onTap: () => launchUrl(Uri.parse('tel:$p')),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kPrimary,
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                    color: _kPrimary.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.phone_rounded,
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(p,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ]),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Note
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 16, color: Color(0xFFEA580C)),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'NOTE: Any room you book will be unavailable for others',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEA580C)),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoChip(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ─── 3. ROOMS ─────────────────────────────────────────────────────────────────

class _RoomsSection extends StatelessWidget {
  final List<RoomModel> rooms;
  final Hostel hostel;
  final bool isWide;
  final void Function(String, int) onBooked;
  const _RoomsSection(
      {required this.rooms,
      required this.hostel,
      required this.isWide,
      required this.onBooked});

  @override
  Widget build(BuildContext context) {
    final cols = isWide ? 3 : 1;
    return Container(
      color: _kBg,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 60 : 20, vertical: 48),
      child: Column(
        children: [
          // Section heading
          _SectionHeading(
              title: 'Available Rooms',
              subtitle: 'Choose a room that suits you'),
          const SizedBox(height: 32),

          rooms.isEmpty
              ? _EmptyBox(message: 'No rooms found for this hostel.')
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: isWide ? 0.68 : 0.85,
                  ),
                  itemCount: rooms.length,
                  itemBuilder: (_, i) => _RoomCard(
                    room: rooms[i],
                    hostel: hostel,
                    onBooked: onBooked,
                  ),
                ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final Hostel hostel;
  final void Function(String, int) onBooked;
  const _RoomCard(
      {required this.room, required this.hostel, required this.onBooked});

  @override
  Widget build(BuildContext context) {
    final rem = room.remaining;
    final isAvail = rem > 0;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // Image with availability badge overlay
          Stack(
            children: [
              _RoomImageSlider(
                images: room.images.isNotEmpty
                    ? room.images
                    : (room.image != null ? [room.image!] : []),
                height: 175,
              ),
              // Availability badge
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isAvail ? _kGreen : _kRed,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2), blurRadius: 4)
                    ],
                  ),
                  child: Text(isAvail ? 'Available' : 'Full',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),

          // Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      // Room type
                      Text('${room.type} Room',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _kDark)),
                      const SizedBox(height: 4),

                      // Room number
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black54),
                          children: [
                            const TextSpan(text: 'Room No: '),
                            TextSpan(
                                text: room.roomNumber,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _kDark)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Stats row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _StatPill(
                              icon: Icons.people_outline_rounded,
                              label: 'Cap: ${room.capacity}',
                              color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          _StatPill(
                            icon: Icons.door_front_door_outlined,
                            label: '$rem slot${rem != 1 ? 's' : ''}',
                            color: isAvail ? _kGreen : _kRed,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Price
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _kGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          'GHS ${room.price.toStringAsFixed(2)} / person',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _kGreen),
                        ),
                      ),

                      // Almost full warning
                      if (rem == 1) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kRed.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🔥', style: TextStyle(fontSize: 12)),
                                SizedBox(width: 4),
                                Text('Almost Full!',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _kRed,
                                        fontWeight: FontWeight.w700)),
                              ]),
                        ),
                      ],
                    ],
                  ),

                  // Buttons
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            (room.images.isNotEmpty || room.image != null)
                                ? () => _showImages(context, room)
                                : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPrimary,
                          side: const BorderSide(color: _kPrimary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text('Images',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            isAvail ? () => _showBooking(context, room) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isAvail ? _kPrimary : Colors.grey[400],
                          foregroundColor: Colors.white,
                          elevation: isAvail ? 3 : 0,
                          shadowColor: _kPrimary.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(isAvail ? 'Book Now' : 'Full',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImages(BuildContext ctx, RoomModel room) {
    final imgs = room.images.isNotEmpty
        ? room.images
        : (room.image != null ? [room.image!] : <String>[]);
    if (imgs.isEmpty) return;
    showDialog(
      context: ctx,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(children: [
              Expanded(
                  child: Text('${room.type} Room — ${room.roomNumber}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700))),
              IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          _RoomImageSlider(images: imgs, height: 300),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  void _showBooking(BuildContext ctx, RoomModel room) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingSheet(
        room: room,
        hostel: hostel,
        onSuccess: (slots) {
          Navigator.pop(ctx);
          onBooked(room.id, slots);
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('🎉 Booking successful!'),
            backgroundColor: _kGreen,
          ));
        },
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ─── Room Image Slider ────────────────────────────────────────────────────────

class _RoomImageSlider extends StatefulWidget {
  final List<String> images;
  final double height;
  const _RoomImageSlider({required this.images, this.height = 180});

  @override
  State<_RoomImageSlider> createState() => _RoomImageSliderState();
}

class _RoomImageSliderState extends State<_RoomImageSlider> {
  int _cur = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        height: widget.height,
        color: _kPrimary.withOpacity(0.08),
        child: const Center(
            child: Icon(Icons.bed_rounded, size: 44, color: _kPrimary)),
      );
    }
    return Stack(children: [
      CarouselSlider(
        options: CarouselOptions(
          height: widget.height,
          viewportFraction: 1.0,
          enableInfiniteScroll: widget.images.length > 1,
          onPageChanged: (i, _) => setState(() => _cur = i),
        ),
        items: widget.images
            .map((img) => Image.network(
                  _img(img),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: widget.height,
                  loadingBuilder: (_, child, p) {
                    if (p == null) return child;
                    return Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(
                          height: widget.height, color: Colors.grey[300]),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    height: widget.height,
                    color: _kPrimary.withOpacity(0.08),
                    child: const Center(
                        child: Icon(Icons.bed_rounded,
                            size: 44, color: _kPrimary)),
                  ),
                ))
            .toList(),
      ),
      if (widget.images.length > 1) ...[
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Center(
              child: _ArrowBtn(Icons.chevron_left,
                  onTap: () => setState(() => _cur =
                      (_cur - 1 + widget.images.length) %
                          widget.images.length))),
        ),
        Positioned(
          right: 6,
          top: 0,
          bottom: 0,
          child: Center(
              child: _ArrowBtn(Icons.chevron_right,
                  onTap: () => setState(
                      () => _cur = (_cur + 1) % widget.images.length))),
        ),
      ],
    ]);
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ArrowBtn(this.icon, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ─── 4. FACILITIES ────────────────────────────────────────────────────────────

class _FacilitiesSection extends StatelessWidget {
  final List<String> facilities;
  final bool isWide;
  const _FacilitiesSection({required this.facilities, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kCard,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 60 : 20, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
              title: 'Facilities & Amenities',
              subtitle: 'Everything available at this hostel'),
          const SizedBox(height: 28),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: facilities
                .map((f) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: _kPrimary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: _kPrimary.withOpacity(0.2)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 16, color: _kGreen),
                        const SizedBox(width: 8),
                        Text(f,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _kDark)),
                      ]),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// for kIsWeb
// ignore: avoid_web_libraries_in_flutter

class _LocationSection extends StatelessWidget {
  final String mapSrc;
  final bool isWide;

  const _LocationSection({
    required this.mapSrc,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 60 : 20,
        vertical: 48,
      ),
      child: Column(
        children: [
          _SectionHeading(
            title: 'Our Location',
            subtitle: 'Find us on the map',
          ),
          const SizedBox(height: 24),
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.grey[200],
            ),
            child: const Center(
              child: Icon(Icons.map, size: 60, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(mapSrc);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.location_on),
            label: const Text('Open in Google Maps'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ─── Section Heading ──────────────────────────────────────────────────────────

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                    color: _kPrimary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: _kDark)),
            const SizedBox(width: 12),
            Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                    color: _kPrimary, borderRadius: BorderRadius.circular(2))),
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black45)),
      ],
    );
  }
}

// ─── Booking Sheet ────────────────────────────────────────────────────────────

class _BookingSheet extends StatefulWidget {
  final RoomModel room;
  final Hostel hostel;
  final void Function(int) onSuccess;
  const _BookingSheet(
      {required this.room, required this.hostel, required this.onSuccess});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _school = TextEditingController();
  final _schoolId = TextEditingController();
  final _notes = TextEditingController();
  bool _notStudent = false;
  int _slots = 1;
  String? _payment;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _school.dispose();
    _schoolId.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    if (_payment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a payment method')));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = widget.room;
      final h = widget.hostel;
      await FirebaseFirestore.instance.collection('bookings').add({
        'room_id': r.id,
        'room_number': r.roomNumber,
        'hostel_id': h.id,
        'hostel_name': h.hostelName,
        'hostel_code': h.hostelCode,
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'school': _school.text.trim(),
        'school_id': _notStudent ? '' : _schoolId.text.trim(),
        'not_student': _notStudent,
        'notes': _notes.text.trim(),
        'payment_method': _payment,
        'slots_booked': _slots,
        'status': 'booked',
        'booked_at': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(r.id)
          .update({'booked': FieldValue.increment(_slots)});
      if (!mounted) return;
      widget.onSuccess(_slots);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Booking failed: $e'), backgroundColor: _kRed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final rem = room.remaining;
    final opts = room.paymentOptions;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kPrimary, Color(0xFF0D9488)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              const Icon(Icons.hotel_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Book ${room.type} Room — ${room.roomNumber}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white))),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          // Form
          Expanded(
            child: SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Form(
                key: _key,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FF(
                          label: 'Full Name',
                          ctrl: _name,
                          validator: (v) => v!.isEmpty ? 'Required' : null),
                      _FF(
                          label: 'Email',
                          ctrl: _email,
                          kb: TextInputType.emailAddress,
                          validator: (v) => v!.isEmpty ? 'Required' : null),
                      _FF(
                          label: 'Phone Number',
                          ctrl: _phone,
                          kb: TextInputType.phone,
                          validator: (v) => v!.isEmpty ? 'Required' : null),
                      _FF(
                          label: 'School Name',
                          ctrl: _school,
                          validator: (v) => v!.isEmpty ? 'Required' : null),
                      if (!_notStudent)
                        _FF(label: 'School ID (optional)', ctrl: _schoolId),
                      Row(children: [
                        Checkbox(
                            value: _notStudent,
                            onChanged: (v) =>
                                setState(() => _notStudent = v ?? false),
                            activeColor: _kPrimary),
                        const Text('I am not a student',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      _FF(
                          label: 'Additional Notes',
                          ctrl: _notes,
                          lines: 3,
                          hint:
                              'Amount paying, special requests, move-in date…'),
                      const SizedBox(height: 6),

                      // Slots
                      const Text('Number of Slots',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                            borderRadius: BorderRadius.circular(10)),
                        child: DropdownButton<int>(
                          isExpanded: true,
                          underline: const SizedBox(),
                          value: _slots,
                          items: List.generate(
                              rem,
                              (i) => DropdownMenuItem(
                                  value: i + 1,
                                  child: Text(
                                      '${i + 1} slot${i + 1 > 1 ? 's' : ''}'))),
                          onChanged: (v) => setState(() => _slots = v ?? 1),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rem == 1
                            ? '🔥 Only 1 slot left!'
                            : '$rem slots remaining',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: rem == 1 ? _kRed : _kGreen),
                      ),
                      const SizedBox(height: 18),

                      // Payment
                      const Text('Payment Method',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...opts.entries.map((e) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.key,
                                style: const TextStyle(fontSize: 14)),
                            subtitle: _payment == e.key
                                ? Text('Pay to: ${e.value}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey))
                                : null,
                            value: e.key,
                            groupValue: _payment,
                            activeColor: _kPrimary,
                            onChanged: (v) => setState(() => _payment = v),
                          )),
                      const SizedBox(height: 20),

                      // Submit
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 3,
                            shadowColor: _kGreen.withOpacity(0.4),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Confirm Booking',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Form Field helper ────────────────────────────────────────────────────────

class _FF extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final TextInputType? kb;
  final int lines;
  final String? hint;
  final String? Function(String?)? validator;
  const _FF(
      {required this.label,
      required this.ctrl,
      this.kb,
      this.lines = 1,
      this.hint,
      this.validator});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: kb,
          maxLines: lines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.black26)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.black26)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          ),
        ),
      ]),
    );
  }
}

// ─── Error / Empty helpers ───────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 52, color: _kRed),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
          child: const Text('Try Again'),
        ),
      ]),
    )));
  }
}

class _EmptyBox extends StatelessWidget {
  final String message;
  const _EmptyBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bed_rounded, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ]),
    ));
  }
}
