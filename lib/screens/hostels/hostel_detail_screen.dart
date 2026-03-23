// lib/screens/hostel/hostel_detail_screen.dart

import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../services/booking_storage_service.dart';
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
const _kOrange = Color(0xFFEA580C);

// ── Paystack secret key ───────────────────────────────────────────────────────
const _kPaystackSecretKey = 'sk_test_6350329ac171a2de1a9b7e6309865e837b163d12';
const _kPaystackBaseUrl = 'https://api.paystack.co';

// ─── Unique reference generator ──────────────────────────────────────────────
String _generateReference() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final random = Random().nextInt(99999).toString().padLeft(5, '0');
  return 'RZF-$timestamp-$random';
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _img(String? v, {int width = 800}) {
  if (v == null || v.trim().isEmpty) {
    return 'https://placehold.co/600x400?text=No+Image';
  }
  final url = v.trim();
  if (url.contains('cloudinary.com') && url.contains('/upload/')) {
    return url.replaceFirst(
        '/upload/', '/upload/f_auto,q_auto:good,w_$width,c_fill/');
  }
  return url;
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
  });

  factory RoomModel.fromFirestore(String id, Map<String, dynamic> d) =>
      RoomModel(
        id: id,
        roomNumber: d['room_number'] ?? '',
        type: d['type'] ?? 'Room',
        capacity: _toInt(d['capacity'], 1),
        price: (d['price'] ?? 0).toDouble(),
        booked: _toInt(d['booked'], 0),
        available: d['available'] == true || d['available'] == 1,
        image: d['image'],
        images: _splitImages(d['images']),
      );

  static int _toInt(dynamic v, int fallback) =>
      v is int ? v : int.tryParse('$v') ?? fallback;

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

      final hostel = Hostel.fromJson(doc.id, doc.data()!);
      final rooms = roomsSnap.docs
          .map((d) => RoomModel.fromFirestore(d.id, d.data()))
          .toList();

      setState(() {
        _hostel = hostel;
        _rooms = rooms;
        _facilities = facSnap.docs
            .map((d) => (d.data()['facility_name'] ?? '') as String)
            .where((f) => f.isNotEmpty)
            .toList();
        _loading = false;
      });

      if (mounted) _precacheAllImages(hostel, rooms);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _precacheAllImages(Hostel hostel, List<RoomModel> rooms) {
    for (final img in [
      if (hostel.image?.isNotEmpty == true) hostel.image!,
      ..._splitImages(hostel.images),
    ]) {
      CachedNetworkImageProvider(_img(img, width: 1200))
          .resolve(const ImageConfiguration());
    }
    for (final room in rooms) {
      for (final img in room.images.isNotEmpty
          ? room.images
          : (room.image != null ? [room.image!] : <String>[])) {
        CachedNetworkImageProvider(_img(img, width: 800))
            .resolve(const ImageConfiguration());
      }
    }
  }

  void _onBooked(String roomId, int slots) {
    setState(() {
      final i = _rooms.indexWhere((r) => r.id == roomId);
      if (i != -1) {
        _rooms[i] = _rooms[i].copyWith(booked: _rooms[i].booked + slots);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: _kPrimary)));
    }
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
    if (_hostel == null) {
      return const Scaffold(body: Center(child: Text('Hostel not found')));
    }

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
            _HeroSection(hostelName: hostel.hostelName, images: heroImages),
            _InfoSection(
                hostel: hostel, isWide: isWide, heroImages: heroImages),
            _RoomsSection(
                rooms: _rooms,
                hostel: hostel,
                isWide: isWide,
                onBooked: _onBooked),
            if (_facilities.isNotEmpty)
              _FacilitiesSection(facilities: _facilities, isWide: isWide),
            if (mapSrc.isNotEmpty)
              _LocationSection(mapSrc: mapSrc, isWide: isWide),
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
    // Responsive hero height: shorter on small screens
    final screenH = MediaQuery.of(context).size.height;
    final heroH = (screenH * 0.38).clamp(220.0, 380.0);

    return SizedBox(
      height: heroH,
      child: Stack(fit: StackFit.expand, children: [
        widget.images.isNotEmpty
            ? CarouselSlider(
                options: CarouselOptions(
                  height: heroH,
                  viewportFraction: 1.0,
                  autoPlay: widget.images.length > 1,
                  autoPlayInterval: const Duration(seconds: 5),
                  onPageChanged: (i, _) => setState(() => _current = i),
                ),
                items: widget.images
                    .map((img) => CachedNetworkImage(
                          imageUrl: _img(img, width: 1200),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          fadeInDuration: const Duration(milliseconds: 200),
                          placeholder: (_, __) =>
                              Container(color: _kDark.withOpacity(0.6)),
                          errorWidget: (_, __, ___) => Container(color: _kDark),
                        ))
                    .toList(),
              )
            : Container(color: _kDark),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x55000000), Color(0xCC000000)],
            ),
          ),
        ),
        // Use LayoutBuilder so text never overflows horizontally
        LayoutBuilder(builder: (ctx, constraints) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  widget.hostelName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // Scale font slightly on very narrow screens
                    fontSize: (constraints.maxWidth < 340) ? 26 : 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    shadows: const [
                      Shadow(blurRadius: 12, color: Colors.black87)
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Breadcrumb — wrap so it never overflows on tiny screens
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    _crumb('Home'),
                    _sep(),
                    _crumb('Hostels / Apartments', bold: true),
                    _sep(),
                    _crumb(widget.hostelName, dim: true),
                  ],
                ),
              ),
            ],
          );
        }),
        if (widget.images.length > 1)
          Positioned(
            bottom: 14,
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
      ]),
    );
  }

  Widget _crumb(String t, {bool bold = false, bool dim = false}) => Text(t,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: dim ? Colors.white54 : Colors.white,
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ));

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text('/', style: TextStyle(color: Colors.white38, fontSize: 12)),
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
      child: Column(children: [
        Container(height: 4, color: _kPrimary),
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: isWide ? 60 : 16, vertical: 32),
          child: isWide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 6, child: _HeroImageBox(images: heroImages)),
                  const SizedBox(width: 48),
                  Expanded(
                      flex: 5,
                      child: _DetailsBox(hostel: hostel, phones: phones)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _HeroImageBox(images: heroImages),
                  const SizedBox(height: 24),
                  _DetailsBox(hostel: hostel, phones: phones),
                ]),
        ),
      ]),
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
              offset: const Offset(0, 8))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: images.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: _img(images[0], width: 1200),
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (_, __) => Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(color: Colors.grey[300]),
                  ),
                  errorWidget: (_, __, ___) => Container(
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Hostel name — never overflows
      Text(hostel.hostelName,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _kDark,
              height: 1.2)),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.location_on_rounded, size: 16, color: _kPrimary),
        const SizedBox(width: 4),
        Flexible(
          child: Text('${hostel.town ?? ''}, Ghana',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
      const SizedBox(height: 14),
      // Price badge — uses FittedBox so it never overflows on narrow screens
      if (hostel.priceRange != null)
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Container(
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
              '${hostel.priceRange!}  ·  ${hostel.durationType}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
        ),
      const SizedBox(height: 14),
      if (hostel.description?.isNotEmpty == true) ...[
        Text(hostel.description!,
            style: const TextStyle(
                fontSize: 14, color: Colors.black54, height: 1.65)),
        const SizedBox(height: 14),
      ],
      if (hostel.schoolName?.isNotEmpty == true)
        _InfoChip(
          icon: Icons.school_rounded,
          text: hostel.schoolShortName != null
              ? '${hostel.schoolName} (${hostel.schoolShortName})'
              : hostel.schoolName!,
          color: _kPrimary,
        ),
      const SizedBox(height: 12),
      // Phone box
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kPrimary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kPrimary.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            horizontal: 12, vertical: 8),
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
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
      ),
      const SizedBox(height: 12),
      // Note banner
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Color(0xFFEA580C)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
                'NOTE: Any room you book will be unavailable for others',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEA580C))),
          ),
        ]),
      ),
    ]);
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
                overflow: TextOverflow.ellipsis,
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
    final screenW = MediaQuery.of(context).size.width;
    final hPad = isWide ? 60.0 : 16.0;

    // ── Dynamically compute card height based on available width ──────────
    // On wide screens: 3 columns. On narrow: 1 column.
    // Card width = (available width - spacing) / columns
    final cols = isWide ? 3 : 1;
    final totalSpacing = (cols - 1) * 20.0; // gap between cards
    final cardW = (screenW - hPad * 2 - totalSpacing) / cols;

    // Image takes 160px, content area needs ~230px minimum
    // Add 30px buffer so "Almost Full" badge never pushes over
    final cardH = 160.0 + 240.0;

    return Container(
      color: _kBg,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 48),
      child: Column(children: [
        _SectionHeading(
            title: 'Available Rooms', subtitle: 'Choose a room that suits you'),
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
                  // Fixed pixel height — never overflows regardless of screen
                  mainAxisExtent: cardH,
                ),
                itemCount: rooms.length,
                itemBuilder: (_, i) => _RoomCard(
                    room: rooms[i],
                    hostel: hostel,
                    onBooked: onBooked,
                    cardWidth: cardW),
              ),
      ]),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final Hostel hostel;
  final void Function(String, int) onBooked;
  final double cardWidth;
  const _RoomCard(
      {required this.room,
      required this.hostel,
      required this.onBooked,
      required this.cardWidth});

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
      // Column with fixed image + flexible content
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Image area ────────────────────────────────────────────────
          SizedBox(
            height: 160,
            child: Stack(children: [
              _RoomImageSlider(
                images: room.images.isNotEmpty
                    ? room.images
                    : (room.image != null ? [room.image!] : []),
                height: 160,
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            ]),
          ),
          // ── Content area — Expanded so it fills remaining card height ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top info block
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${room.type} Room',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _kDark)),
                      const SizedBox(height: 3),
                      // Room number
                      RichText(
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
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
                      // Capacity & slots pills — wrap so they never overflow
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _StatPill(
                              icon: Icons.people_outline_rounded,
                              label: 'Cap: ${room.capacity}',
                              color: Colors.blueGrey),
                          _StatPill(
                              icon: Icons.door_front_door_outlined,
                              label: '$rem slot${rem != 1 ? 's' : ''}',
                              color: isAvail ? _kGreen : _kRed),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Price badge — FittedBox prevents right overflow
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                              color: _kGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50)),
                          child: Text(
                              'GHS ${room.price.toStringAsFixed(2)} / person',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _kGreen)),
                        ),
                      ),
                      // "Almost Full" badge — only shown when rem == 1
                      if (rem == 1) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                              color: _kRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50)),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🔥', style: TextStyle(fontSize: 11)),
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
                  // Bottom buttons
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
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                      overflow: TextOverflow.ellipsis,
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
        onSuccess: (bookingId, slots) {
          Navigator.pop(ctx);
          onBooked(room.id, slots);
          ctx.go('/book/$bookingId');
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(50)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ─── Room Image Slider ────────────────────────────────────────────────────────

class _RoomImageSlider extends StatefulWidget {
  final List<String> images;
  final double height;
  const _RoomImageSlider({required this.images, this.height = 160});

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
            .map((img) => CachedNetworkImage(
                  imageUrl: _img(img, width: 800),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: widget.height,
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (_, __) => Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                        height: widget.height, color: Colors.grey[300]),
                  ),
                  errorWidget: (_, __, ___) => Container(
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
                            widget.images.length)))),
        Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
                child: _ArrowBtn(Icons.chevron_right,
                    onTap: () => setState(
                        () => _cur = (_cur + 1) % widget.images.length)))),
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
        width: 26,
        height: 26,
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, color: Colors.white, size: 16),
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
      padding: EdgeInsets.symmetric(horizontal: isWide ? 60 : 16, vertical: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeading(
            title: 'Facilities & Amenities',
            subtitle: 'Everything available at this hostel'),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: facilities
              .map((f) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: _kPrimary.withOpacity(0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 15, color: _kGreen),
                      const SizedBox(width: 7),
                      Text(f,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kDark)),
                    ]),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}

// ─── 5. LOCATION ─────────────────────────────────────────────────────────────

const _kGeoapifyApiKey = '1f447c87da1949b48571d28867d1f6a6';

class _LocationSection extends StatelessWidget {
  final String mapSrc;
  final bool isWide;
  const _LocationSection({required this.mapSrc, required this.isWide});

  Map<String, double>? _extractCoords() {
    try {
      final uri = Uri.parse(mapSrc);
      final pb = uri.queryParameters['pb'] ?? '';
      final lngMatch = RegExp(r'!2d(-?\d+\.?\d*)').firstMatch(pb);
      final latMatch = RegExp(r'!3d(-?\d+\.?\d*)').firstMatch(pb);
      if (latMatch != null && lngMatch != null) {
        return {
          'lat': double.parse(latMatch.group(1)!),
          'lng': double.parse(lngMatch.group(1)!),
        };
      }
    } catch (_) {}
    return null;
  }

  String _staticMapUrl(double lat, double lng) {
    return 'https://maps.geoapify.com/v1/staticmap'
        '?style=osm-bright'
        '&width=800'
        '&height=400'
        '&center=lonlat:$lng,$lat'
        '&zoom=16'
        '&marker=lonlat:$lng,$lat;color:%230f766e;size:large'
        '&apiKey=$_kGeoapifyApiKey';
  }

  String _buildOpenUrl(double? lat, double? lng) {
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps?q=$lat,$lng';
    }
    try {
      if (!mapSrc.contains('/embed')) return mapSrc;
    } catch (_) {}
    return 'https://maps.google.com';
  }

  @override
  Widget build(BuildContext context) {
    final coords = _extractCoords();
    final lat = coords?['lat'];
    final lng = coords?['lng'];
    final openUrl = _buildOpenUrl(lat, lng);
    final staticUrl =
        (lat != null && lng != null) ? _staticMapUrl(lat, lng) : null;

    return Container(
      color: _kBg,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 60 : 16, vertical: 48),
      child: Column(children: [
        _SectionHeading(title: 'Our Location', subtitle: 'Find us on the map'),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse(openUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                if (staticUrl != null)
                  CachedNetworkImage(
                    imageUrl: staticUrl,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _MapShimmer(),
                    errorWidget: (_, __, ___) => _MapFallback(),
                  )
                else
                  _MapFallback(),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.65),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('Tap to open in Google Maps',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new_rounded,
                                size: 13, color: _kPrimary),
                            SizedBox(width: 4),
                            Text('Open',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _kPrimary)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MapShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
          height: 240, width: double.infinity, color: Colors.grey[300]),
    );
  }
}

class _MapFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPrimary.withOpacity(0.12),
            _kPrimary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(children: [
        CustomPaint(
          size: const Size(double.infinity, 240),
          painter: _MapGridPainter(),
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _kPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: _kPrimary.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1), blurRadius: 8),
                  ],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.touch_app_rounded, size: 13, color: _kPrimary),
                  SizedBox(width: 5),
                  Text('Tap to open in Google Maps',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kPrimary)),
                ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF0F766E).withOpacity(0.08)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    final roadPaint = Paint()
      ..color = const Color(0xFF0F766E).withOpacity(0.18)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height * 0.55),
        Offset(size.width, size.height * 0.38), roadPaint);
    canvas.drawLine(Offset(size.width * 0.35, 0),
        Offset(size.width * 0.55, size.height), roadPaint);
    final blockPaint = Paint()
      ..color = const Color(0xFF0F766E).withOpacity(0.07)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.05, size.height * 0.1, 55, 36),
        blockPaint);
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.65, size.height * 0.15, 48, 32),
        blockPaint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.1, size.height * 0.65, 42, 28),
        blockPaint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.72, size.height * 0.6, 52, 34),
        blockPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Section Heading ──────────────────────────────────────────────────────────

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
                color: _kPrimary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: _kDark)),
        ),
        const SizedBox(width: 10),
        Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
                color: _kPrimary, borderRadius: BorderRadius.circular(2))),
      ]),
      const SizedBox(height: 6),
      Text(subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black45)),
    ]);
  }
}

// ─── Booking Sheet ────────────────────────────────────────────────────────────

class _BookingSheet extends StatefulWidget {
  final RoomModel room;
  final Hostel hostel;
  final void Function(String bookingId, int slots) onSuccess;
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
  final _momoNumber = TextEditingController();
  final _school = TextEditingController();
  final _schoolId = TextEditingController();
  final _notes = TextEditingController();

  bool _notStudent = false;
  int _slots = 1;
  String _momoProvider = 'mtn';
  bool _busy = false;
  int _step = 0;
  String? _bookingId;
  String _paymentReference = _generateReference();

  void _refreshReference() => _paymentReference = _generateReference();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _momoNumber.dispose();
    _school.dispose();
    _schoolId.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _totalAmount => widget.room.price * _slots;

  Future<void> _proceedToPayment() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final r = widget.room;
      final h = widget.hostel;
      final docRef =
          await FirebaseFirestore.instance.collection('bookings').add({
        'room_id': r.id,
        'room_number': r.roomNumber,
        'hostel_id': h.id,
        'hostel_name': h.hostelName,
        'hostel_code': h.hostelCode,
        'hostel_phone': h.phone,
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'momo_number': _momoNumber.text.trim(),
        'momo_provider': _momoProvider,
        'school': _school.text.trim(),
        'school_id': _notStudent ? '' : _schoolId.text.trim(),
        'not_student': _notStudent,
        'notes': _notes.text.trim(),
        'payment_method': 'Mobile Money',
        'momo_type': _momoProvider == 'mtn' ? 'MTN MoMo' : 'Vodafone Cash',
        'slots_booked': _slots,
        'amount': _totalAmount,
        'status': 'pending',
        'payment_status': 'pending',
        'booked_at': FieldValue.serverTimestamp(),
      });
      _bookingId = docRef.id;
      setState(() {
        _step = 1;
        _busy = false;
      });
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _kRed));
      }
    }
  }

  Future<void> _initiatePayment() async {
    _refreshReference();
    setState(() {
      _step = 2;
      _busy = true;
    });
    try {
      final provider = _momoProvider == 'mtn' ? 'mtn' : 'vod';
      final amountInPesewas = (_totalAmount * 100).toInt();
      final chargeRes = await http.post(
        Uri.parse('$_kPaystackBaseUrl/charge'),
        headers: {
          'Authorization': 'Bearer $_kPaystackSecretKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': _email.text.trim(),
          'amount': amountInPesewas,
          'currency': 'GHS',
          'mobile_money': {
            'phone': _momoNumber.text.trim(),
            'provider': provider,
          },
          'reference': _paymentReference,
          'metadata': {
            'booking_id': _bookingId,
            'hostel_name': widget.hostel.hostelName,
            'room_number': widget.room.roomNumber,
            'slots': _slots,
          },
        }),
      );
      final chargeData = jsonDecode(chargeRes.body);
      final status = chargeData['data']?['status'];
      if (status == 'pay_offline' ||
          status == 'pending' ||
          status == 'send_otp') {
        await _pollPaymentStatus(_paymentReference);
      } else if (status == 'success') {
        await _onPaymentSuccess(_paymentReference);
      } else {
        throw Exception(chargeData['message'] ?? 'Payment failed. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      _refreshReference();
      setState(() {
        _step = 1;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment error: $e'), backgroundColor: _kRed));
    }
  }

  Future<void> _pollPaymentStatus(String reference) async {
    for (int i = 0; i < 12; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      final res = await http.get(
        Uri.parse('$_kPaystackBaseUrl/transaction/verify/$reference'),
        headers: {'Authorization': 'Bearer $_kPaystackSecretKey'},
      );
      final data = jsonDecode(res.body);
      final status = data['data']?['status'];
      debugPrint('🔁 Poll $i — status: $status');
      if (status == 'success') {
        await _onPaymentSuccess(reference);
        return;
      } else if (status == 'failed') {
        if (!mounted) return;
        _refreshReference();
        setState(() {
          _step = 1;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment declined. Please try again.'),
            backgroundColor: _kRed));
        return;
      }
    }
    if (!mounted) return;
    _refreshReference();
    setState(() {
      _step = 1;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:
          Text('Payment is taking long. Check your phone for the MoMo prompt.'),
      backgroundColor: _kOrange,
      duration: Duration(seconds: 5),
    ));
  }

  Future<void> _onPaymentSuccess(String reference) async {
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(_bookingId)
        .update({
      'payment_status': 'paid',
      'status': 'confirmed',
      'payment_reference': reference,
      'paid_at': FieldValue.serverTimestamp(),
    });
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.room.id)
        .update({'booked': FieldValue.increment(_slots)});
    await BookingStorageService.saveBookingId(_bookingId!);
    if (!mounted) return;
    widget.onSuccess(_bookingId!, _slots);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kPrimary, Color(0xFF0D9488)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(children: [
              const Icon(Icons.hotel_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        'Book ${widget.room.type} Room — ${widget.room.roomNumber}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    Text('GHS ${_totalAmount.toStringAsFixed(2)} total',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8))),
                  ])),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          _StepIndicator(currentStep: _step),
          Expanded(
              child: SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: _step == 0
                ? _buildForm()
                : _step == 1
                    ? _buildPaymentStep()
                    : _buildProcessingStep(),
          )),
        ]),
      ),
    );
  }

  Widget _buildForm() {
    final rem = widget.room.remaining;
    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Personal Information', Icons.person_rounded),
        const SizedBox(height: 12),
        _FF(
            label: 'Full Name',
            ctrl: _name,
            icon: Icons.person_outline,
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        _FF(
            label: 'Email Address',
            ctrl: _email,
            icon: Icons.email_outlined,
            kb: TextInputType.emailAddress,
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        _FF(
            label: 'Phone Number',
            ctrl: _phone,
            icon: Icons.phone_outlined,
            kb: TextInputType.phone,
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 8),
        _sectionLabel('Academic Information', Icons.school_rounded),
        const SizedBox(height: 12),
        _FF(
            label: 'School Name',
            ctrl: _school,
            icon: Icons.school_outlined,
            validator: (v) => _notStudent
                ? null
                : v!.trim().isEmpty
                    ? 'Required'
                    : null),
        if (!_notStudent)
          _FF(
              label: 'School ID (optional)',
              ctrl: _schoolId,
              icon: Icons.badge_outlined),
        Row(children: [
          Checkbox(
              value: _notStudent,
              onChanged: (v) => setState(() => _notStudent = v ?? false),
              activeColor: _kPrimary),
          const Flexible(
            child: Text('I am not a student',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        _sectionLabel('Booking Details', Icons.hotel_rounded),
        const SizedBox(height: 12),
        const Text('Number of Slots',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(12)),
          child: DropdownButton<int>(
            isExpanded: true,
            underline: const SizedBox(),
            value: _slots,
            items: List.generate(
                rem,
                (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                          '${i + 1} slot${i + 1 > 1 ? 's' : ''} — GHS ${((i + 1) * widget.room.price).toStringAsFixed(2)}'),
                    )),
            onChanged: (v) => setState(() => _slots = v ?? 1),
          ),
        ),
        const SizedBox(height: 6),
        Text(rem == 1 ? '🔥 Only 1 slot left!' : '$rem slots remaining',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: rem == 1 ? _kRed : _kGreen)),
        const SizedBox(height: 14),
        _FF(
            label: 'Additional Notes (optional)',
            ctrl: _notes,
            icon: Icons.notes_rounded,
            lines: 3,
            hint: 'Special requests, move-in date, questions…'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF0D9488)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Total Amount',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('GHS ${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 20)),
                ])),
            Text('$_slots slot${_slots > 1 ? 's' : ''}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _proceedToPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 3,
              shadowColor: _kPrimary.withOpacity(0.4),
            ),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Text('Continue to Payment',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded),
                      ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildPaymentStep() {
    final momoNumber = widget.hostel.paymentMomo;
    final cashPayment = widget.hostel.paymentCash;
    final bankPayment = widget.hostel.paymentBank;
    final otherPayment = widget.hostel.paymentOther;
    final hasMomo = momoNumber.isNotEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(
          'Landlord\'s Payment Details', Icons.account_balance_wallet_rounded),
      const SizedBox(height: 12),
      if (momoNumber.isNotEmpty)
        _MomoNumberCard(
            provider: 'MTN / Vodafone MoMo',
            number: momoNumber,
            color: const Color(0xFFFFCC00),
            icon: '📱'),
      if (cashPayment.isNotEmpty)
        _MomoNumberCard(
            provider: 'Cash Payment',
            number: cashPayment,
            color: const Color(0xFF16A34A),
            icon: '💵'),
      if (bankPayment.isNotEmpty)
        _MomoNumberCard(
            provider: 'Bank Payment',
            number: bankPayment,
            color: const Color(0xFF2563EB),
            icon: '🏦'),
      if (otherPayment.isNotEmpty)
        _MomoNumberCard(
            provider: 'Other Payment',
            number: otherPayment,
            color: const Color(0xFF7C3AED),
            icon: '💳'),
      if (momoNumber.isEmpty &&
          cashPayment.isEmpty &&
          bankPayment.isEmpty &&
          otherPayment.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: _kOrange),
            SizedBox(width: 8),
            Flexible(
                child: Text('Contact the hostel directly for payment details.',
                    style: TextStyle(
                        fontSize: 13,
                        color: _kOrange,
                        fontWeight: FontWeight.w500))),
          ]),
        ),
      const SizedBox(height: 20),
      if (hasMomo) ...[
        _sectionLabel('Your MoMo Details', Icons.payment_rounded),
        const SizedBox(height: 12),
        const Text('Select Provider',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black54)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _ProviderBtn(
                  label: 'MTN MoMo',
                  color: const Color(0xFFFFCC00),
                  isSelected: _momoProvider == 'mtn',
                  onTap: () => setState(() => _momoProvider = 'mtn'))),
          const SizedBox(width: 12),
          Expanded(
              child: _ProviderBtn(
                  label: 'Vodafone Cash',
                  color: const Color(0xFFE60000),
                  isSelected: _momoProvider == 'vodafone',
                  onTap: () => setState(() => _momoProvider = 'vodafone'))),
        ]),
        const SizedBox(height: 16),
        _FF(
            label: 'Your MoMo Number',
            ctrl: _momoNumber,
            icon: Icons.phone_android_rounded,
            kb: TextInputType.phone,
            hint: '024XXXXXXX or 050XXXXXXX',
            validator: (v) =>
                v!.trim().length < 10 ? 'Enter a valid MoMo number' : null),
        const SizedBox(height: 16),
      ],
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kGreen.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kGreen.withOpacity(0.3)),
        ),
        child: Column(children: [
          _SummaryRow(
              label: 'Room',
              value: '${widget.room.type} — ${widget.room.roomNumber}'),
          _SummaryRow(label: 'Slots', value: '$_slots'),
          _SummaryRow(
              label: 'Price/slot',
              value: 'GHS ${widget.room.price.toStringAsFixed(2)}'),
          const Divider(height: 20),
          _SummaryRow(
              label: 'Total',
              value: 'GHS ${_totalAmount.toStringAsFixed(2)}',
              bold: true),
        ]),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA))),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: _kOrange),
          const SizedBox(width: 8),
          Flexible(
              child: Text(
            hasMomo
                ? 'You will receive a MoMo prompt on your phone to approve the payment.'
                : 'Please pay using one of the methods above and contact the hostel to confirm.',
            style: const TextStyle(
                fontSize: 12, color: _kOrange, fontWeight: FontWeight.w500),
          )),
        ]),
      ),
      const SizedBox(height: 20),
      if (hasMomo)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _initiatePayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 3,
              shadowColor: _kGreen.withOpacity(0.4),
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Pay Now',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
          ),
        ),
      if (!hasMomo)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await FirebaseFirestore.instance
                        .collection('bookings')
                        .doc(_bookingId)
                        .update({
                      'status': 'pending',
                      'payment_status': 'pending',
                    });
                    await BookingStorageService.saveBookingId(_bookingId!);
                    if (!mounted) return;
                    widget.onSuccess(_bookingId!, _slots);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 3,
            ),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(Icons.check_circle_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Confirm Booking',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                      ]),
          ),
        ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => setState(() => _step = 0),
          child: const Text('← Back to Form',
              style: TextStyle(color: Colors.black45)),
        ),
      ),
    ]);
  }

  Widget _buildProcessingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: _kPrimary, strokeWidth: 3),
          const SizedBox(height: 24),
          const Text('Processing Payment…',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 12),
          Text(
              'Check your ${_momoProvider == 'mtn' ? 'MTN MoMo' : 'Vodafone Cash'} phone for a payment prompt.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: Colors.black45, height: 1.5)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kPrimary.withOpacity(0.2)),
            ),
            child: Text('Amount: GHS ${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _kPrimary)),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon) {
    return Row(children: [
      Icon(icon, size: 18, color: _kPrimary),
      const SizedBox(width: 8),
      Flexible(
        child: Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: _kDark)),
      ),
    ]);
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(children: [
        _Step(
            number: 1,
            label: 'Details',
            isActive: currentStep >= 0,
            isDone: currentStep > 0),
        _StepLine(isActive: currentStep > 0),
        _Step(
            number: 2,
            label: 'Payment',
            isActive: currentStep >= 1,
            isDone: currentStep > 1),
        _StepLine(isActive: currentStep > 1),
        _Step(
            number: 3,
            label: 'Processing',
            isActive: currentStep >= 2,
            isDone: false),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String label;
  final bool isActive;
  final bool isDone;
  const _Step(
      {required this.number,
      required this.label,
      required this.isActive,
      required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: isActive ? _kPrimary : Colors.grey[200],
            shape: BoxShape.circle),
        child: Center(
          child: isDone
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text('$number',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : Colors.grey)),
        ),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isActive ? _kPrimary : Colors.grey)),
    ]);
  }
}

class _StepLine extends StatelessWidget {
  final bool isActive;
  const _StepLine({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: isActive ? _kPrimary : Colors.grey[200],
    ));
  }
}

// ─── MoMo / Payment Number Card ──────────────────────────────────────────────

class _MomoNumberCard extends StatelessWidget {
  final String provider;
  final String number;
  final Color color;
  final String icon;
  const _MomoNumberCard(
      {required this.provider,
      required this.number,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(provider,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          Text(number,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: _kDark)),
        ])),
        GestureDetector(
          onTap: () {
            final isPhone = RegExp(r'^\d').hasMatch(number.trim());
            if (isPhone) launchUrl(Uri.parse('tel:$number'));
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(8)),
            child:
                const Icon(Icons.phone_rounded, color: Colors.white, size: 16),
          ),
        ),
      ]),
    );
  }
}

// ─── Provider Button ─────────────────────────────────────────────────────────

class _ProviderBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  const _ProviderBtn(
      {required this.label,
      required this.color,
      required this.isSelected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1),
        ),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color:
                        isSelected ? color.withOpacity(0.85) : Colors.grey))),
      ),
    );
  }
}

// ─── Summary Row ─────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _SummaryRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
        Flexible(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  color: bold ? _kGreen : _kDark,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Form Field helper ────────────────────────────────────────────────────────

class _FF extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final IconData? icon;
  final TextInputType? kb;
  final int lines;
  final String? hint;
  final String? Function(String?)? validator;
  const _FF(
      {required this.label,
      required this.ctrl,
      this.icon,
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
                fontSize: 13,
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
            prefixIcon:
                icon != null ? Icon(icon, size: 18, color: _kPrimary) : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black12)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black12)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kRed)),
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
            child: const Text('Try Again')),
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
