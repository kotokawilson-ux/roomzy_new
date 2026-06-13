// lib/screens/hostel/hostel_detail_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/booking_storage_service.dart';
import '../../models/models.dart';
import '../../widgets/navbar.dart';
import '../../widgets/footer.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF0F766E);
const _kPrimaryDark = Color(0xFF0D5F58);
const _kAccent = Color(0xFF14B8A6);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kCard = Colors.white;
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kOrange = Color(0xFFEA580C);
const _kSurface = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE2E8F0);
const _kTextMuted = Color(0xFF64748B);
const _kTextDim = Color(0xFF94A3B8);

// ── Paystack ─────────────────────────────────────────────────────────────────
const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';
const _kTestMomoNumbers = {
  '0551234987',
  '0571234987',
  '0201234987',
  '0261234987',
};

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _generateReference() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rnd = Random().nextInt(99999).toString().padLeft(5, '0');
  return 'RZF-$ts-$rnd';
}

String _img(String? v, {int width = 800}) {
  if (v == null || v.trim().isEmpty)
    return 'https://placehold.co/600x400?text=No+Image';
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

Future<void> _logActivity({
  required String action,
  required String details,
  required String userEmail,
}) async {
  try {
    await FirebaseFirestore.instance.collection('activityLog').add({
      'action': action,
      'details': details,
      'userEmail': userEmail,
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Failed to log activity: $e');
  }
}

// ─── RoomModel ────────────────────────────────────────────────────────────────
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
        available: available && (capacity - booked) > 0,
        image: image,
        images: images,
      );
}

// ─── Screen ───────────────────────────────────────────────────────────────────
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

  StreamSubscription? _hostelSub;
  StreamSubscription? _roomsSub;
  StreamSubscription? _facilitiesSub;

  @override
  void initState() {
    super.initState();
    _startListeners();
  }

  @override
  void dispose() {
    _hostelSub?.cancel();
    _roomsSub?.cancel();
    _facilitiesSub?.cancel();
    super.dispose();
  }

  void _startListeners() {
    setState(() {
      _loading = true;
      _error = null;
    });

    _hostelSub = FirebaseFirestore.instance
        .collection('hostels')
        .doc(widget.hostelId)
        .snapshots()
        .listen(
      (doc) {
        if (!mounted) return;
        if (!doc.exists) {
          setState(() {
            _error = 'Hostel not found';
            _loading = false;
          });
          return;
        }
        final hostel = Hostel.fromJson(doc.id, doc.data()!);
        setState(() {
          _hostel = hostel;
          _loading = false;
        });
        _precacheAllImages(hostel, _rooms);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      },
    );

    _roomsSub = FirebaseFirestore.instance
        .collection('rooms')
        .where('hostel_id', isEqualTo: widget.hostelId)
        .where('available', isEqualTo: true) // ← add this line
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final rooms = snap.docs
            .map((d) => RoomModel.fromFirestore(d.id, d.data()))
            .toList();
        setState(() => _rooms = rooms);
        if (_hostel != null) _precacheAllImages(_hostel!, rooms);
      },
      onError: (e) => debugPrint('Rooms error: $e'),
    );

    _facilitiesSub = FirebaseFirestore.instance
        .collection('facilities')
        .where('hostel_id', isEqualTo: widget.hostelId)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _facilities = snap.docs
              .map((d) => (d.data()['facility_name'] ?? '') as String)
              .where((f) => f.isNotEmpty)
              .toList();
        });
      },
      onError: (e) => debugPrint('Facilities error: $e'),
    );
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: _PulseLoader()),
      );
    }
    if (_error != null)
      return _ErrorView(message: _error!, onRetry: _startListeners);
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
            _HeroSection(hostelName: hostel.hostelName, images: heroImages),
            _InfoSection(
                hostel: hostel, isWide: isWide, heroImages: heroImages),
            _RoomsSection(
              rooms: _rooms,
              hostel: hostel,
              isWide: isWide,
              onBooked: (_, __) {},
            ),
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

// ─── Pulse Loader ─────────────────────────────────────────────────────────────
class _PulseLoader extends StatefulWidget {
  const _PulseLoader();
  @override
  State<_PulseLoader> createState() => _PulseLoaderState();
}

class _PulseLoaderState extends State<_PulseLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
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
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kPrimary.withOpacity(0.1 + _anim.value * 0.2),
          border: Border.all(
              color: _kPrimary.withOpacity(0.4 + _anim.value * 0.6), width: 2),
        ),
        child: const Center(
            child:
                CircularProgressIndicator(color: _kPrimary, strokeWidth: 2.5)),
      ),
    );
  }
}

// ─── 1. HERO ──────────────────────────────────────────────────────────────────
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
    final screenH = MediaQuery.of(context).size.height;
    final heroH = (screenH * 0.42).clamp(240.0, 420.0);

    return SizedBox(
      height: heroH,
      child: Stack(fit: StackFit.expand, children: [
        // ── Carousel ────────────────────────────────────────────────────────
        widget.images.isNotEmpty
            ? CarouselSlider(
                options: CarouselOptions(
                  height: heroH,
                  viewportFraction: 1.0,
                  autoPlay: widget.images.length > 1,
                  autoPlayInterval: const Duration(seconds: 5),
                  autoPlayCurve: Curves.easeInOutCubic,
                  onPageChanged: (i, _) => setState(() => _current = i),
                ),
                items: widget.images
                    .map(
                      (img) => CachedNetworkImage(
                        imageUrl: _img(img, width: 1200),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        fadeInDuration: const Duration(milliseconds: 300),
                        placeholder: (_, __) =>
                            Container(color: _kDark.withOpacity(0.6)),
                        errorWidget: (_, __, ___) => Container(color: _kDark),
                      ),
                    )
                    .toList(),
              )
            : Container(color: _kDark),

        // ── Cinematic gradient overlay ───────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x00000000), Color(0xDD000000)],
              stops: [0.0, 0.4, 1.0],
            ),
          ),
        ),

        // ── Title block ──────────────────────────────────────────────────────
        Positioned(
          bottom: 32,
          left: 24,
          right: 24,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Hostel tag pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.9),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Text('HOSTEL / APARTMENT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
            ),
            const SizedBox(height: 10),
            Text(
              widget.hostelName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.3,
                height: 1.15,
                shadows: [Shadow(blurRadius: 20, color: Colors.black87)],
              ),
            ),
          ]),
        ),

        // ── Dot indicators ───────────────────────────────────────────────────
        if (widget.images.length > 1)
          Positioned(
            bottom: 12,
            right: 24,
            child: Row(
              children: widget.images
                  .asMap()
                  .entries
                  .map(
                    (e) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _current == e.key ? 18 : 5,
                      height: 5,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.white
                            .withOpacity(_current == e.key ? 1 : 0.4),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ]),
    );
  }
}

// ─── 2. INFO ──────────────────────────────────────────────────────────────────
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
        // Teal accent bar
        Container(
          height: 4,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_kPrimary, _kAccent]),
          ),
        ),
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: isWide ? 60 : 20, vertical: 36),
          child: isWide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 6, child: _HeroImageBox(images: heroImages)),
                  const SizedBox(width: 52),
                  Expanded(
                      flex: 5,
                      child: _DetailsBox(hostel: hostel, phones: phones)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _HeroImageBox(images: heroImages),
                  const SizedBox(height: 28),
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
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.12),
              blurRadius: 32,
              offset: const Offset(0, 12)),
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: images.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: _img(images[0], width: 1200),
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 300),
                  placeholder: (_, __) => Shimmer.fromColors(
                    baseColor: Colors.grey[200]!,
                    highlightColor: Colors.grey[50]!,
                    child: Container(color: Colors.grey[200]),
                  ),
                  errorWidget: (_, __, ___) => _ImagePlaceholder(),
                )
              : _ImagePlaceholder(),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: _kPrimary.withOpacity(0.06),
        child: const Center(
            child: Icon(Icons.apartment_rounded, size: 60, color: _kPrimary)),
      );
}

class _DetailsBox extends StatelessWidget {
  final Hostel hostel;
  final List<String> phones;
  const _DetailsBox({required this.hostel, required this.phones});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        hostel.hostelName,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: _kDark,
            height: 1.2),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child:
              const Icon(Icons.location_on_rounded, size: 14, color: _kPrimary),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${hostel.town ?? ''}, Ghana',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14, color: _kTextMuted, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (hostel.priceRange != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF16A34A), Color(0xFF15803D)]),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                  color: _kGreen.withOpacity(0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Text(
            '${hostel.priceRange!}  ·  ${hostel.durationType}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      const SizedBox(height: 10),
      if (hostel.depositType != 'none') ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Text(
            hostel.depositType == 'percent'
                ? 'Deposit: ${hostel.depositValue.toStringAsFixed(0)}% of room price'
                : 'Deposit: GHS ${hostel.depositValue.toStringAsFixed(2)} (fixed)',
            style: const TextStyle(
                color: _kOrange, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 16),
      if (hostel.description?.isNotEmpty == true) ...[
        Text(
          hostel.description!,
          style: const TextStyle(fontSize: 14, color: _kTextMuted, height: 1.7),
        ),
        const SizedBox(height: 16),
      ],
      if (hostel.schoolName?.isNotEmpty == true) ...[
        _InfoChip(
          icon: Icons.school_rounded,
          text: hostel.schoolShortName != null
              ? '${hostel.schoolName} (${hostel.schoolShortName})'
              : hostel.schoolName!,
          color: _kPrimary,
        ),
        const SizedBox(height: 14),
      ],

      // ── Phone contact block ───────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.headset_mic_rounded, size: 15, color: _kTextMuted),
            SizedBox(width: 6),
            Text(
              'For enquiries or details call:',
              style: TextStyle(
                  fontSize: 12,
                  color: _kTextMuted,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: phones
                .map((p) => GestureDetector(
                      onTap: () => launchUrl(Uri.parse('tel:$p')),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_kPrimary, _kAccent]),
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                                color: _kPrimary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.phone_rounded,
                              size: 13, color: Colors.white),
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

      // ── Warning note ──────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child:
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 15, color: _kOrange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'NOTE: Any room you book will be unavailable for others',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _kOrange),
            ),
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
              child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13, color: color, fontWeight: FontWeight.w600),
          )),
        ]),
      );
}

// ─── 3. ROOMS ─────────────────────────────────────────────────────────────────
class _RoomsSection extends StatelessWidget {
  final List<RoomModel> rooms;
  final Hostel hostel;
  final bool isWide;
  final void Function(String, int) onBooked;
  const _RoomsSection({
    required this.rooms,
    required this.hostel,
    required this.isWide,
    required this.onBooked,
  });

  @override
  Widget build(BuildContext context) {
    final hPad = isWide ? 60.0 : 20.0;
    final cols = isWide ? 3 : 1;
    final screenW = MediaQuery.of(context).size.width;
    final totalSpacing = (cols - 1) * 20.0;
    final cardW = (screenW - hPad * 2 - totalSpacing) / cols;
    const cardH = 160.0 + 250.0;

    return Container(
      color: _kBg,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 52),
      child: Column(children: [
        _SectionHeading(
            title: 'Available Rooms',
            subtitle: 'Choose a room that suits your lifestyle'),
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
                  mainAxisExtent: cardH,
                ),
                itemCount: rooms.length,
                itemBuilder: (_, i) => _RoomCard(
                  room: rooms[i],
                  hostel: hostel,
                  onBooked: onBooked,
                  cardWidth: cardW,
                ),
              ),
      ]),
    );
  }
}

class _RoomCard extends StatefulWidget {
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
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  late Animation<double> _elevation;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _elevation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rem = widget.room.remaining;
    final isAvail = widget.room.available && rem > 0;
    final isAlmostFull = rem == 1 && isAvail;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        _hoverCtrl.forward();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        _hoverCtrl.reverse();
      },
      child: AnimatedBuilder(
        animation: _elevation,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -_elevation.value * 4),
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isAlmostFull
                  ? _kRed.withOpacity(0.3)
                  : isAvail
                      ? _kBorder
                      : _kBorder,
              width: isAlmostFull ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_hovered ? 0.12 : 0.06),
                blurRadius: _hovered ? 24 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Image ──────────────────────────────────────────────────────
            SizedBox(
              height: 160,
              child: Stack(children: [
                _RoomImageSlider(
                  images: widget.room.images.isNotEmpty
                      ? widget.room.images
                      : (widget.room.image != null ? [widget.room.image!] : []),
                  height: 160,
                ),
                // Status badge
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:
                          isAvail ? (isAlmostFull ? _kOrange : _kGreen) : _kRed,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 6)
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isAvail
                            ? (isAlmostFull ? 'Almost Full' : 'Available')
                            : 'Full',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                ),
                // Price tag
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent
                        ],
                      ),
                    ),
                    child: Text(
                      'GHS ${widget.room.price.toStringAsFixed(2)} / person',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                    ),
                  ),
                ),
              ]),
            ),

            // ── Content ────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        '${widget.room.type} Room',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _kDark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Room No. ${widget.room.roomNumber}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12,
                            color: _kTextDim,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _MiniPill(
                                Icons.people_outline_rounded,
                                'Cap: ${widget.room.capacity}',
                                Colors.blueGrey),
                            const SizedBox(width: 6),
                            _MiniPill(
                              Icons.door_front_door_outlined,
                              '$rem slot${rem != 1 ? 's' : ''}',
                              isAvail ? _kGreen : _kRed,
                            ),
                          ]),
                    ]),

                    // ── Action buttons ────────────────────────────────────
                    Row(children: [
                      Expanded(
                        child: _OutlineBtn(
                          label: 'Photos',
                          icon: Icons.photo_library_outlined,
                          onTap: (widget.room.images.isNotEmpty ||
                                  widget.room.image != null)
                              ? () => _showImages(context, widget.room)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilledBtn(
                          label: isAvail ? 'Book Now' : 'Full',
                          icon: isAvail
                              ? Icons.hotel_rounded
                              : Icons.block_rounded,
                          onTap: isAvail
                              ? () => _showBooking(context, widget.room)
                              : null,
                          color: isAvail ? _kPrimary : Colors.grey[400]!,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ]),
        ),
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
      barrierColor: Colors.black87,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: _kDark,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 0),
              child: Row(children: [
                Expanded(
                    child: Text(
                  '${room.type} · Room ${room.roomNumber}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                )),
                IconButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  icon: const Icon(Icons.close, color: Colors.white60),
                ),
              ]),
            ),
            _RoomImageSlider(images: imgs, height: 320),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  void _showBooking(BuildContext ctx, RoomModel room) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (sheetCtx) => _BookingSheet(
        // ← sheetCtx, not _
        room: room,
        hostel: widget.hostel,
        onSuccess: (bookingId, slots) {
          Navigator.pop(sheetCtx); // ← close sheet with sheetCtx
          widget.onBooked(room.id, slots);
          ctx.push('/bookings/$bookingId'); // ← navigate with original ctx
        },
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniPill(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(50)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _OutlineBtn({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color:
                onTap != null ? _kPrimary.withOpacity(0.05) : Colors.grey[100],
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
                color: onTap != null
                    ? _kPrimary.withOpacity(0.4)
                    : Colors.grey[300]!),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 12, color: onTap != null ? _kPrimary : Colors.grey[400]),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: onTap != null ? _kPrimary : Colors.grey[400],
                )),
          ]),
        ),
      );
}

class _FilledBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  const _FilledBtn(
      {required this.label,
      required this.icon,
      this.onTap,
      required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(50),
            boxShadow: onTap != null
                ? [
                    BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]
                : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ]),
        ),
      );
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
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: Colors.black54, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      );
}

// ─── 4. FACILITIES ────────────────────────────────────────────────────────────
class _FacilitiesSection extends StatelessWidget {
  final List<String> facilities;
  final bool isWide;
  const _FacilitiesSection({required this.facilities, required this.isWide});

  @override
  Widget build(BuildContext context) => Container(
        color: _kCard,
        padding:
            EdgeInsets.symmetric(horizontal: isWide ? 60 : 20, vertical: 52),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionHeading(
              title: 'Facilities & Amenities',
              subtitle: 'Everything available at this hostel'),
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: facilities
                .map((f) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: _kPrimary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: _kPrimary.withOpacity(0.18)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 14, color: _kGreen),
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
          'lng': double.parse(lngMatch.group(1)!)
        };
      }
    } catch (_) {}
    return null;
  }

  String _staticMapUrl(double lat, double lng) =>
      'https://maps.geoapify.com/v1/staticmap'
      '?style=osm-bright&width=800&height=400'
      '&center=lonlat:$lng,$lat&zoom=16'
      '&marker=lonlat:$lng,$lat;color:%230f766e;size:large'
      '&apiKey=$_kGeoapifyApiKey';

  String _buildOpenUrl(double? lat, double? lng) {
    if (lat != null && lng != null)
      return 'https://www.google.com/maps?q=$lat,$lng';
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
      padding: EdgeInsets.symmetric(horizontal: isWide ? 60 : 20, vertical: 52),
      child: Column(children: [
        _SectionHeading(title: 'Our Location', subtitle: 'Find us on the map'),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse(openUrl);
            if (await canLaunchUrl(uri))
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
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
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent
                        ],
                      ),
                    ),
                    child: Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: Colors.white, size: 17),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Text(
                          'Tap to open in Google Maps',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.open_in_new_rounded,
                                  size: 12, color: _kPrimary),
                              SizedBox(width: 5),
                              Text('Open',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _kPrimary)),
                            ]),
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
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
            height: 240, width: double.infinity, color: Colors.grey[300]),
      );
}

class _MapFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 240,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_kPrimary.withOpacity(0.1), _kPrimary.withOpacity(0.04)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _kPrimary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: _kPrimary.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6))
                ],
              ),
              child: const Icon(Icons.location_on_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08), blurRadius: 8)
                ],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.touch_app_rounded, size: 12, color: _kPrimary),
                SizedBox(width: 5),
                Text(
                  'Tap to open in Google Maps',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary),
                ),
              ]),
            ),
          ]),
        ),
      );
}

// ─── Section Heading ──────────────────────────────────────────────────────────
class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kPrimary, _kAccent]),
                borderRadius: BorderRadius.circular(2),
              )),
          const SizedBox(width: 12),
          Flexible(
              child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w900, color: _kDark),
          )),
          const SizedBox(width: 12),
          Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kAccent, _kPrimary]),
                borderRadius: BorderRadius.circular(2),
              )),
        ]),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _kTextDim),
        ),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ─── BOOKING SHEET — Modern Multi-Step ────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _BookingSheet extends StatefulWidget {
  final RoomModel room;
  final Hostel hostel;
  final void Function(String bookingId, int slots) onSuccess;
  const _BookingSheet(
      {required this.room, required this.hostel, required this.onSuccess});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet>
    with TickerProviderStateMixin {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _momo = TextEditingController();
  final _school = TextEditingController();
  final _schoolId = TextEditingController();
  final _notes = TextEditingController();

  late AnimationController _stepAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _notStudent = false;
  int _slots = 1;
  String _momoProvider = 'mtn';
  bool _busy = false;
  int _step =
      0; // 0=details, 1=payment, 2=processing, 3=done(error path handled)
  String? _bookingId;
  String _payRef = _generateReference();

  bool get _isTestNumber =>
      _kTestMomoNumbers.contains(_momo.text.trim().replaceAll(' ', ''));

  double get _totalAmount => widget.room.price * _slots;
  double get _depositAmount =>
      widget.hostel.depositAmountFor(widget.room.price) * _slots;
  double get _minPayable => _depositAmount > 0 ? _depositAmount : _totalAmount;

  // payment amount state
  int _payMode = 0; // 0=deposit, 1=custom, 2=full
  double _customAmount = 0;
  final _customAmountCtrl = TextEditingController();
  String _paymentMethod = 'momo'; // 'momo' | 'manual'

  double get _amountToPay {
    if (_depositAmount == 0)
      return _totalAmount; // no deposit configured → always full
    switch (_payMode) {
      case 0:
        return _depositAmount;
      case 1:
        return _customAmount.clamp(_minPayable, _totalAmount);
      case 2:
        return _totalAmount;
      default:
        return _totalAmount;
    }
  }

  double get _balance => _totalAmount - _amountToPay;

  String get _paymentStatusLabel {
    if (_amountToPay >= _totalAmount) return 'fully_paid';
    if (_amountToPay >= _depositAmount) return 'deposit_paid';
    return 'pending';
  }

  @override
  void initState() {
    super.initState();

    // Auto-fill email from logged-in user
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      _email.text = user!.email!;
    }

    _stepAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _fadeAnim = CurvedAnimation(parent: _stepAnim, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _stepAnim, curve: Curves.easeOut));
    _stepAnim.forward();
  }

  @override
  void dispose() {
    _stepAnim.dispose();
    for (final c in [
      _name,
      _email,
      _phone,
      _momo,
      _school,
      _schoolId,
      _notes,
      _customAmountCtrl
    ]) c.dispose();
    super.dispose();
  }

  void _goToStep(int s) {
    _stepAnim.reset();
    setState(() => _step = s);
    _stepAnim.forward();
    HapticFeedback.selectionClick();
  }

  // ── Form → save pending booking ───────────────────────────────────────────
  Future<void> _proceedToPayment() async {
    if (!_key.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() => _busy = true);
    try {
      // ── Step 1: Fetch commission rate ──────────────────────────────────────
      String landlordId = '';
      double commissionRate = 5.0; // fallback default

      try {
        // Get landlord_id from hostel doc
        final hostelDoc = await FirebaseFirestore.instance
            .collection('hostels')
            .doc(widget.hostel.id)
            .get();
        landlordId = hostelDoc.data()?['landlord_id']?.toString() ?? '';

        if (landlordId.isNotEmpty) {
          // Try landlord-specific rate first
          final landlordDoc = await FirebaseFirestore.instance
              .collection('landlords')
              .doc(landlordId)
              .get();
          final landlordCustomRate =
              (landlordDoc.data()?['commission_percent'] as num?)?.toDouble();

          if (landlordCustomRate != null) {
            commissionRate = landlordCustomRate;
          } else {
            // Fall back to global platform rate
            final settingsDoc = await FirebaseFirestore.instance
                .collection('settings')
                .doc('platform')
                .get();
            commissionRate = (settingsDoc.data()?['commission_percent'] as num?)
                    ?.toDouble() ??
                5.0;
          }
        } else {
          // No landlord linked — use global rate
          final settingsDoc = await FirebaseFirestore.instance
              .collection('settings')
              .doc('platform')
              .get();
          commissionRate =
              (settingsDoc.data()?['commission_percent'] as num?)?.toDouble() ??
                  5.0;
        }
      } catch (e) {
        // Commission fetch failed — safe fallback, don't block booking
        debugPrint('Commission fetch error: $e');
        commissionRate = 5.0;
      }

      // ── Step 2: Calculate commission fields ────────────────────────────────
      final commissionOwed = _totalAmount * (commissionRate / 100);

      // ── Step 3: Save booking with all commission fields ────────────────────
      final docRef =
          await FirebaseFirestore.instance.collection('bookings').add({
        // ── Room & hostel ───────────────────────────────────────────────────
        'room_id': widget.room.id,
        'room_number': widget.room.roomNumber,
        'hostel_id': widget.hostel.id,
        'hostel_name': widget.hostel.hostelName,
        'hostel_code': widget.hostel.hostelCode,
        'hostel_phone': widget.hostel.phone,
        'landlord_id': landlordId,

        // ── Guest details ───────────────────────────────────────────────────
        // ── Guest details ───────────────────────────────────────────────────
        'user_id': FirebaseAuth.instance.currentUser?.uid ?? '',
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'momo_number': _momo.text.trim(),
        'momo_provider': _momoProvider,
        'school': _school.text.trim(),
        'school_id': _notStudent ? '' : _schoolId.text.trim(),
        'not_student': _notStudent,
        'notes': _notes.text.trim(),

        // ── Payment method ──────────────────────────────────────────────────
        'payment_method': 'Mobile Money',
        'momo_type': _momoProvider == 'mtn' ? 'MTN MoMo' : 'Vodafone Cash',

        // ── Booking amounts ─────────────────────────────────────────────────
        'slots_booked': _slots,
        'amount': _totalAmount,
        'deposit_amount': _depositAmount,
        'amount_paid': 0.0,
        'balance': _totalAmount,

        // ── Commission snapshot ─────────────────────────────────────────────
        // Locked at booking time — never changes even if rate is renegotiated
        'commission_rate': commissionRate,
        'commission_owed': commissionOwed,
        'commission_collected': 0.0,
        'commission_remaining': commissionOwed,

        // ── Payment tracking ────────────────────────────────────────────────
        'payment_count': 0, // increments with every successful payment
        'payment_status': 'pending',
        'status': 'pending',

        // ── Timestamps ──────────────────────────────────────────────────────
        'booked_at': FieldValue.serverTimestamp(),
      });

      _bookingId = docRef.id;
      _goToStep(1);
    } catch (e) {
      _showSnack('Error saving booking: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptForOtp() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Confirmation Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check the SMS sent to your phone by your mobile money provider and enter the code below.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP / Confirmation Code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // ── Initiate Paystack payment ─────────────────────────────────────────────
  Future<void> _initiatePayment() async {
    _payRef = _generateReference();
    _goToStep(2);
    setState(() => _busy = true);

    try {
      if (_isTestNumber) {
        await Future.delayed(const Duration(seconds: 2));
        await _onPaymentSuccess(_payRef);
        return;
      }

      final provider = _momoProvider == 'mtn' ? 'mtn' : 'vod';
      final chargeRes = await http.post(
        Uri.parse('$_kBackendUrl/charge-momo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': _bookingId,
          'email': _email.text.trim(),
          'amount': _amountToPay,
          'phone': _momo.text.trim(),
          'provider': provider,
          'reference': _payRef,
        }),
      );

      final chargeData = jsonDecode(chargeRes.body);
      final status = chargeData['status'];

      if (status == 'send_otp') {
        setState(() => _busy = false);
        final otp = await _promptForOtp();
        if (otp == null) {
          _goToStep(1);
          return;
        }
        setState(() => _busy = true);
        _goToStep(2);

        final otpRes = await http.post(
          Uri.parse('$_kBackendUrl/submit-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'otp': otp, 'reference': _payRef}),
        );
        final otpData = jsonDecode(otpRes.body);

        if (otpData['status'] == 'success') {
          await _onPaymentSuccess(_payRef);
        } else {
          await _pollPaymentStatus(_payRef);
        }
      } else if (status == 'pay_offline' || status == 'pending') {
        await _pollPaymentStatus(_payRef);
      } else if (status == 'success') {
        await _onPaymentSuccess(_payRef);
      } else {
        throw Exception(chargeData['message'] ?? 'Payment failed. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      _payRef = _generateReference();
      _goToStep(1);
      _showSnack('Payment error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPaymentFailedDialog(String? gatewayResponse, String? message) {
    if (!mounted) return;

    final raw = gatewayResponse ?? message ?? 'Unknown error';

    // Friendly translations for common Paystack/MTN/Vodafone codes
    final friendlyMessages = <String, String>{
      'LOW_BALANCE_OR_PAYEE_LIMIT_REACHED_OR_NOT_ALLOWED':
          'Your Mobile Money wallet doesn\'t have enough balance to complete this payment, or you\'ve reached your transaction limit. Please top up your wallet and try again.',
      'INVALID_OTP':
          'The code you entered was incorrect or has expired. Please try again with a new code.',
      'EXPIRED_OTP': 'The code has expired. Please try again to get a new one.',
      'TRANSACTION_NOT_ALLOWED_FOR_USER':
          'This transaction is not allowed for your Mobile Money account. Please contact your provider.',
      'DECLINED':
          'The payment was declined. Please try again or use a different number.',
    };

    final friendly = friendlyMessages[raw] ??
        raw.replaceAll('_', ' ').toLowerCase().replaceFirstMapped(
              RegExp(r'^.'),
              (m) => m.group(0)!.toUpperCase(),
            );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kRed.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child:
              const Icon(Icons.error_outline_rounded, color: _kRed, size: 32),
        ),
        title: const Text(
          'Payment Failed',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          friendly,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: _kTextMuted, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
            ),
            child: const Text('Try Again',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _pollPaymentStatus(String reference) async {
    for (int i = 0; i < 12; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      final res = await http.post(
        Uri.parse('$_kBackendUrl/verify-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reference': reference}),
      );
      final data = jsonDecode(res.body);
      debugPrint('verify-payment response: $data');
      final status = data['status'];
      if (status == 'success') {
        await _onPaymentSuccess(reference);
        return;
      }
      if (status == 'failed') {
        if (!mounted) return;
        _goToStep(1);
        _showPaymentFailedDialog(data['gateway_response'], data['message']);
        return;
      }
    }
    if (!mounted) return;
    _goToStep(1);
    _showSnack('Payment is taking long. Check your phone for the MoMo prompt.',
        isError: false);
  }

  Future<void> _onPaymentSuccess(String reference) async {
    final roomRef =
        FirebaseFirestore.instance.collection('rooms').doc(widget.room.id);
    final bookingRef =
        FirebaseFirestore.instance.collection('bookings').doc(_bookingId);

    try {
      // ── Step 1: Read booking doc BEFORE transaction to get commission fields
      final bookingSnap = await bookingRef.get();
      final bData = bookingSnap.data() ?? {};
      final rawRate = (bData['commission_rate'] as num?)?.toDouble() ?? 5.0;
      final commissionRateDecimal = rawRate > 1 ? rawRate / 100 : rawRate;
      final commissionOwed = (bData['commission_owed'] as num?)?.toDouble() ??
          (_totalAmount * 0.05);
      final commissionCollected =
          (bData['commission_collected'] as num?)?.toDouble() ?? 0.0;
      final commissionRemaining = commissionOwed - commissionCollected;
      final paymentCount = (bData['payment_count'] as num?)?.toInt() ?? 0;
      final amountAlreadyPaid =
          (bData['amount_paid'] as num?)?.toDouble() ?? 0.0;

      // ── Step 2: Determine payment position ────────────────────────────────
      final newTotalPaid = amountAlreadyPaid + _amountToPay;
      final isFirstPayment = paymentCount == 0;
      final isFinalPayment = newTotalPaid >= _totalAmount;

      // ── Step 3: Apply commission rule ─────────────────────────────────────
      // First + Final (full amount at once) → full commission
      // First only (deposit/partial)        → half commission
      // Final only (clears balance)         → remaining commission
      // Middle payment                      → zero commission
      double commissionThisPayment;
      if (isFirstPayment && isFinalPayment) {
        commissionThisPayment = commissionOwed;
      } else if (isFirstPayment) {
        commissionThisPayment = commissionOwed / 2;
      } else if (isFinalPayment) {
        commissionThisPayment = commissionRemaining;
      } else {
        commissionThisPayment = 0.0;
      }

      final landlordGetsThisPayment = _amountToPay - commissionThisPayment;
      final newCommissionCollected =
          commissionCollected + commissionThisPayment;
      final newCommissionRemaining = commissionOwed - newCommissionCollected;
      final newBalance = (_totalAmount - newTotalPaid).clamp(0.0, _totalAmount);

      // ── Step 4: Determine statuses ────────────────────────────────────────
      final newPaymentStatus = isFinalPayment ? 'fully_paid' : 'deposit_paid';
      final newBookingStatus =
          (_depositAmount > 0 && newTotalPaid >= _depositAmount) ||
                  isFinalPayment
              ? 'confirmed'
              : 'pending';

      // ── Step 5: Run Firestore transaction ─────────────────────────────────
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final roomSnap = await txn.get(roomRef);
        final capacity = (roomSnap.data()?['capacity'] ?? 1) as int;
        final booked = (roomSnap.data()?['booked'] ?? 0) as int;

        // Only check + increment slots on first payment
        // (slots were not reserved yet — room was just held as pending)
        if (isFirstPayment) {
          if (capacity - booked < _slots) {
            throw Exception('Not enough slots left');
          }
          txn.update(roomRef, {'booked': FieldValue.increment(_slots)});
        }

        // Update booking doc
        txn.update(bookingRef, {
          // ── Payment amounts ───────────────────────────────────────────────
          'amount_paid': newTotalPaid,
          'balance': newBalance,
          'payment_status': newPaymentStatus,
          'status': newBookingStatus,
          'payment_reference': reference,

          // ── Commission tracking ───────────────────────────────────────────
          'commission_collected': newCommissionCollected,
          'commission_remaining': newCommissionRemaining,

          // ── Payment count ─────────────────────────────────────────────────
          'payment_count': FieldValue.increment(1),

          // ── Timestamps ────────────────────────────────────────────────────
          'paid_at': FieldValue.serverTimestamp(),
          if (isFinalPayment) 'fully_paid_at': FieldValue.serverTimestamp(),
        });
      });

      // ── Step 6: Record in payments subcollection ──────────────────────────
      // Outside transaction — subcollection writes can't go inside runTransaction
      await bookingRef.collection('payments').add({
        // ── What the student paid ─────────────────────────────────────────
        'amount': _amountToPay,
        'method': 'momo',
        'provider': _momoProvider,
        'reference': reference,
        'status': 'paid',

        // ── Commission breakdown for this payment ─────────────────────────
        'commission_taken': commissionThisPayment,
        'landlord_received': landlordGetsThisPayment,
        'commission_rate_used': commissionRateDecimal,

        // ── Payment position ──────────────────────────────────────────────
        'payment_number': paymentCount + 1,
        'is_first_payment': isFirstPayment,
        'is_final_payment': isFinalPayment,

        // ── Running totals at time of this payment ────────────────────────
        'total_paid_after': newTotalPaid,
        'balance_after': newBalance,
        'commission_collected_after': newCommissionCollected,

        // ── Human-readable note ───────────────────────────────────────────
        'note': isFirstPayment && isFinalPayment
            ? 'Full payment — 100% commission taken'
            : isFirstPayment
                ? 'First payment — 50% commission taken'
                : isFinalPayment
                    ? 'Final payment — remaining commission taken'
                    : 'Partial payment — no commission taken',

        'paid_at': FieldValue.serverTimestamp(),
      });

      // ── Step 7: Log activity ──────────────────────────────────────────────
      await _logActivity(
        action: isFirstPayment && isFinalPayment
            ? 'Booking Fully Paid'
            : isFirstPayment
                ? 'Booking Deposit Paid'
                : isFinalPayment
                    ? 'Booking Balance Cleared'
                    : 'Booking Partial Payment',
        details:
            'User ${_email.text.trim()} paid GHS ${_amountToPay.toStringAsFixed(2)} '
            '(payment #${paymentCount + 1}) for ${_slots} slot(s) in Room ${widget.room.roomNumber} '
            'at ${widget.hostel.hostelName}. '
            'Commission taken: GHS ${commissionThisPayment.toStringAsFixed(2)}. '
            'Landlord received: GHS ${landlordGetsThisPayment.toStringAsFixed(2)}. '
            'Balance remaining: GHS ${newBalance.toStringAsFixed(2)}. '
            '${_isTestNumber ? "(Test mode)" : "(Live payment)"}',
        userEmail: _email.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      _goToStep(1);
      _showSnack(
        e.toString().contains('Not enough slots')
            ? 'Sorry, those slots were just taken. Choose fewer slots or a different room.'
            : 'Confirmation error: $e',
        isError: true,
      );
      return;
    }

    await BookingStorageService.saveBookingId(_bookingId!);
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    widget.onSuccess(_bookingId!, _slots);
  }

  Future<void> _confirmManualPayment() async {
    setState(() => _busy = true);
    try {
      final ref = _generateReference();
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(_bookingId)
          .update({
        'payment_status': _paymentStatusLabel,
        'status': _amountToPay >= _totalAmount ? 'confirmed' : 'pending',
        'payment_method': 'Manual',
        'amount_paid': _amountToPay,
        'balance': (_totalAmount - _amountToPay).clamp(0, _totalAmount),
        'payment_reference': ref,
        'paid_at': FieldValue.serverTimestamp(),
      });

      // Record in payments subcollection
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(_bookingId!)
          .collection('payments')
          .add({
        'amount': _amountToPay,
        'method': 'manual',
        'reference': ref,
        'status': 'pending_verification',
        'note': _payMode == 0
            ? 'Deposit payment (manual)'
            : _payMode == 1
                ? 'Partial payment (manual)'
                : 'Full payment (manual)',
        'paid_at': FieldValue.serverTimestamp(),
      });

      await _logActivity(
        action: 'Manual Booking Payment',
        details:
            'User ${_email.text.trim()} submitted manual payment of GHS ${_amountToPay.toStringAsFixed(2)} '
            'for Room ${widget.room.roomNumber} at ${widget.hostel.hostelName}.',
        userEmail: _email.text.trim(),
      );

      await BookingStorageService.saveBookingId(_bookingId!);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      widget.onSuccess(_bookingId!, _slots);
    } catch (e) {
      _showSnack('Error recording payment: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.info_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Flexible(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: isError ? _kRed : _kOrange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom;
    final keyboardH = mq.viewInsets.bottom;
    // Extra scroll clearance so the CTA button is never hidden behind the nav bar
    final scrollClearance = (bottomPad + keyboardH + 96).clamp(96.0, 240.0);

    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(children: [
          // ── Drag handle ─────────────────────────────────────────────────
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 18),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kPrimary, _kAccent]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.hotel_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.room.type} Room · ${widget.room.roomNumber}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _kDark),
                      ),
                      Text(
                        'GHS ${_totalAmount.toStringAsFixed(2)} total',
                        style:
                            const TextStyle(fontSize: 12, color: _kTextMuted),
                      ),
                    ]),
              ),
              // Close button
              Container(
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: _kTextMuted),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ),
            ]),
          ),

          // ── Step progress bar ────────────────────────────────────────────
          _ModernStepBar(currentStep: _step),
          const SizedBox(height: 4),

          // ── Divider ──────────────────────────────────────────────────────
          Container(height: 1, color: _kBorder),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  controller: ctrl,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, 20, 20, scrollClearance),
                  child: _step == 0
                      ? _buildDetailsForm()
                      : _step == 1
                          ? _buildPaymentStep()
                          : _buildProcessingStep(),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Step 0 — Details form ────────────────────────────────────────────────
  Widget _buildDetailsForm() {
    final rem = widget.room.remaining;
    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Room summary card ───────────────────────────────────────────────
        _RoomSummaryCard(room: widget.room, slots: _slots, total: _totalAmount),
        const SizedBox(height: 24),

        // ── Personal info ───────────────────────────────────────────────────
        _FormGroupLabel('Personal Information', Icons.person_outline_rounded),
        const SizedBox(height: 14),
        _ModernField(
            label: 'Full Name',
            ctrl: _name,
            icon: Icons.badge_outlined,
            validator: (v) =>
                v!.trim().isEmpty ? 'Full name is required' : null),
        _ModernField(
            label: 'Email Address',
            ctrl: _email,
            icon: Icons.alternate_email_rounded,
            kb: TextInputType.emailAddress,
            readOnly: FirebaseAuth.instance.currentUser?.email != null,
            validator: (v) => v!.trim().isEmpty ? 'Email is required' : null),
        _ModernField(
            label: 'Phone Number',
            ctrl: _phone,
            icon: Icons.phone_outlined,
            kb: TextInputType.phone,
            validator: (v) =>
                v!.trim().isEmpty ? 'Phone number is required' : null),

        const SizedBox(height: 6),
        // ── Academic info ───────────────────────────────────────────────────
        _FormGroupLabel('Academic Information', Icons.school_outlined),
        const SizedBox(height: 14),
        _ModernField(
          label: 'School / University',
          ctrl: _school,
          icon: Icons.account_balance_outlined,
          validator: (v) => _notStudent
              ? null
              : v!.trim().isEmpty
                  ? 'School name is required'
                  : null,
        ),
        if (!_notStudent)
          _ModernField(
              label: 'Student ID (optional)',
              ctrl: _schoolId,
              icon: Icons.fingerprint_rounded),
        // Not-student toggle
        GestureDetector(
          onTap: () {
            setState(() => _notStudent = !_notStudent);
            HapticFeedback.selectionClick();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: _notStudent ? _kPrimary.withOpacity(0.06) : _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _notStudent ? _kPrimary.withOpacity(0.3) : _kBorder),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _notStudent ? _kPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: _notStudent ? _kPrimary : Colors.grey[400]!,
                      width: 1.5),
                ),
                child: _notStudent
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                'I am not a student',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _notStudent ? _kPrimary : _kDark),
              ),
            ]),
          ),
        ),

        const SizedBox(height: 20),
        // ── Booking details ─────────────────────────────────────────────────
        _FormGroupLabel('Booking Details', Icons.hotel_outlined),
        const SizedBox(height: 14),

        // Slots picker
        _SlotsPicker(
          slots: _slots,
          max: rem,
          price: widget.room.price,
          onChanged: (v) {
            setState(() => _slots = v);
            HapticFeedback.selectionClick();
          },
        ),
        const SizedBox(height: 4),
        Row(children: [
          Icon(
              rem <= 2
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              size: 13,
              color: rem <= 2 ? _kRed : _kTextDim),
          const SizedBox(width: 5),
          Text(
            rem == 1 ? '🔥 Last slot! Book fast.' : '$rem slots remaining',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: rem <= 2 ? _kRed : _kTextDim),
          ),
        ]),
        const SizedBox(height: 16),
        _ModernField(
          label: 'Additional Notes (optional)',
          ctrl: _notes,
          icon: Icons.notes_rounded,
          lines: 3,
          hint: 'Special requests, move-in date, preferences…',
        ),

        const SizedBox(height: 20),
        // ── Total summary ───────────────────────────────────────────────────
        _TotalCard(
          slots: _slots,
          price: widget.room.price,
          total: _totalAmount,
          deposit: widget.hostel.depositAmountFor(widget.room.price) * _slots,
        ),
        const SizedBox(height: 20),

        // ── CTA ─────────────────────────────────────────────────────────────
        _GradientCTA(
          label: 'Continue to Payment',
          icon: Icons.arrow_forward_rounded,
          busy: _busy,
          onTap: _proceedToPayment,
        ),
      ]),
    );
  }

  // ─── Step 1 — Payment ─────────────────────────────────────────────────────
  // ─── Step 1 — Payment ─────────────────────────────────────────────────────
  Widget _buildPaymentStep() {
    final h = widget.hostel;
    final hasMomo = h.paymentMomo.isNotEmpty;
    final hasDeposit = _depositAmount > 0;
    final isTest = _isTestNumber;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Order summary ────────────────────────────────────────────────────
      _OrderBanner(room: widget.room, slots: _slots, total: _totalAmount),
      const SizedBox(height: 22),

      // ── How much do you want to pay? ─────────────────────────────────────
      if (hasDeposit) ...[
        _FormGroupLabel(
            'How much would you like to pay?', Icons.payments_outlined),
        const SizedBox(height: 14),
        _PayModeSelector(
          depositAmount: _depositAmount,
          totalAmount: _totalAmount,
          selected: _payMode,
          onChanged: (v) {
            setState(() {
              _payMode = v;
              if (v != 1) _customAmountCtrl.clear();
            });
            HapticFeedback.selectionClick();
          },
        ),
        if (_payMode == 1) ...[
          const SizedBox(height: 14),
          _ModernField(
            label: 'Enter Amount (GHS)',
            ctrl: _customAmountCtrl,
            icon: Icons.edit_rounded,
            kb: const TextInputType.numberWithOptions(decimal: true),
            hint:
                'Min: GHS ${_depositAmount.toStringAsFixed(2)}  ·  Max: GHS ${_totalAmount.toStringAsFixed(2)}',
            onChanged: (v) {
              setState(() => _customAmount = double.tryParse(v) ?? 0);
            },
            validator: (v) {
              final val = double.tryParse(v ?? '') ?? 0;
              if (val < _minPayable)
                return 'Minimum is GHS ${_minPayable.toStringAsFixed(2)}';
              if (val > _totalAmount)
                return 'Cannot exceed GHS ${_totalAmount.toStringAsFixed(2)}';
              return null;
            },
          ),
        ],
        const SizedBox(height: 6),
        // Payment summary pill
        _PaymentSummaryStrip(
          amountToPay: _amountToPay,
          balance: _balance,
          total: _totalAmount,
        ),
        const SizedBox(height: 22),
      ],

      // ── Payment method ───────────────────────────────────────────────────
      _FormGroupLabel('Payment Method', Icons.account_balance_wallet_outlined),
      const SizedBox(height: 14),
      Row(children: [
        if (hasMomo)
          Expanded(
            child: _MethodTile(
              icon: Icons.phone_android_rounded,
              label: 'Mobile Money',
              sublabel: 'Pay instantly',
              isSelected: _paymentMethod == 'momo',
              onTap: () => setState(() => _paymentMethod = 'momo'),
              color: _kPrimary,
            ),
          ),
        if (hasMomo) const SizedBox(width: 12),
        Expanded(
          child: _MethodTile(
            icon: Icons.handshake_outlined,
            label: 'Manual',
            sublabel: 'Cash / Bank',
            isSelected: _paymentMethod == 'manual',
            onTap: () => setState(() => _paymentMethod = 'manual'),
            color: _kOrange,
          ),
        ),
      ]),
      const SizedBox(height: 20),

      // ── MoMo details (only when momo selected) ───────────────────────────
      if (_paymentMethod == 'momo' && hasMomo) ...[
        _FormGroupLabel('Your Mobile Money Number', Icons.payment_rounded),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _ProviderTile(
            emoji: '🟡',
            label: 'MTN MoMo',
            isSelected: _momoProvider == 'mtn',
            onTap: () => setState(() => _momoProvider = 'mtn'),
          )),
          const SizedBox(width: 12),
          Expanded(
              child: _ProviderTile(
            emoji: '🔴',
            label: 'Vodafone Cash',
            isSelected: _momoProvider == 'vodafone',
            onTap: () => setState(() => _momoProvider = 'vodafone'),
          )),
        ]),
        const SizedBox(height: 14),
        _ModernField(
          label: 'Your MoMo Number',
          ctrl: _momo,
          icon: Icons.phone_android_rounded,
          kb: TextInputType.phone,
          hint: '024XXXXXXX or 050XXXXXXX',
          onChanged: (_) => setState(() {}),
          validator: (v) =>
              v!.trim().length < 10 ? 'Enter a valid MoMo number' : null,
        ),
        if (isTest)
          _InfoBanner(
            icon: Icons.science_rounded,
            text:
                'Test Mode: No real money deducted. Booking confirmed instantly.',
            color: _kGreen,
          )
        else
          _InfoBanner(
            icon: Icons.smartphone_rounded,
            text:
                'You\'ll receive a MoMo prompt on your phone. Approve to confirm.',
            color: _kPrimary,
          ),
        const SizedBox(height: 8),
      ],

      // ── Manual payment details ────────────────────────────────────────────
      if (_paymentMethod == 'manual') ...[
        if (h.paymentMomo.isNotEmpty)
          _PaymentDetailCard(
              icon: '📱',
              provider: 'MTN / Vodafone MoMo',
              value: h.paymentMomo,
              color: const Color(0xFFFFCC00)),
        if (h.paymentCash.isNotEmpty)
          _PaymentDetailCard(
              icon: '💵',
              provider: 'Cash Payment',
              value: h.paymentCash,
              color: _kGreen),
        if (h.paymentBank.isNotEmpty)
          _PaymentDetailCard(
              icon: '🏦',
              provider: 'Bank Transfer',
              value: h.paymentBank,
              color: const Color(0xFF2563EB)),
        if (h.paymentOther.isNotEmpty)
          _PaymentDetailCard(
              icon: '💳',
              provider: 'Other Method',
              value: h.paymentOther,
              color: const Color(0xFF7C3AED)),
        _InfoBanner(
          icon: Icons.info_outline_rounded,
          text:
              'Pay the landlord directly using the details above, then tap "Confirm" below to record your booking.',
          color: _kOrange,
        ),
        const SizedBox(height: 8),
      ],

      const SizedBox(height: 28),

      // ── CTA ──────────────────────────────────────────────────────────────
      _GradientCTA(
        label: _paymentMethod == 'manual'
            ? 'Confirm Manual Payment'
            : isTest
                ? 'Simulate Payment'
                : 'Pay GHS ${_amountToPay.toStringAsFixed(2)}',
        icon: _paymentMethod == 'manual'
            ? Icons.check_circle_rounded
            : isTest
                ? Icons.science_rounded
                : Icons.lock_rounded,
        busy: _busy,
        color: _paymentMethod == 'manual' ? _kOrange : _kPrimary,
        onTap: () {
          if (_payMode == 1) {
            final val = double.tryParse(_customAmountCtrl.text) ?? 0;
            if (val < _minPayable) {
              _showSnack(
                  'Amount must be at least GHS ${_minPayable.toStringAsFixed(2)}',
                  isError: true);
              return;
            }
          }
          _paymentMethod == 'manual'
              ? _confirmManualPayment()
              : _initiatePayment();
        },
      ),

      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: () => _goToStep(0),
          icon: const Icon(Icons.arrow_back_rounded,
              size: 15, color: _kTextMuted),
          label: const Text('Back to details',
              style: TextStyle(color: _kTextMuted, fontSize: 13)),
          style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
        ),
      ),
    ]);
  }

  // ─── Step 2 — Processing ──────────────────────────────────────────────────
  Widget _buildProcessingStep() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          // Animated ring
          _ProcessingRing(),
          const SizedBox(height: 32),
          Text(
            _isTestNumber ? 'Simulating Payment…' : 'Processing Payment…',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _kDark),
          ),
          const SizedBox(height: 12),
          Text(
            _isTestNumber
                ? 'Hang tight — confirming your booking in test mode.'
                : 'Check your ${_momoProvider == 'mtn' ? 'MTN MoMo' : 'Vodafone Cash'} phone\nand approve the payment prompt.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 14, color: _kTextMuted, height: 1.6),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _kPrimary.withOpacity(0.08),
                _kAccent.withOpacity(0.06)
              ]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kPrimary.withOpacity(0.15)),
            ),
            child: Column(children: [
              const Text('Amount to Pay',
                  style: TextStyle(fontSize: 12, color: _kTextMuted)),
              const SizedBox(height: 4),
              Text(
                'GHS ${_amountToPay.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: _kPrimary),
              ),
              Text(
                '${_slots} slot${_slots > 1 ? 's' : ''} · ${widget.room.type} Room',
                style: const TextStyle(fontSize: 12, color: _kTextDim),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          // Pulse dots
          _PulseDots(),
        ]),
      );
}

// ─── Processing Ring ──────────────────────────────────────────────────────────
class _ProcessingRing extends StatefulWidget {
  @override
  State<_ProcessingRing> createState() => _ProcessingRingState();
}

class _ProcessingRingState extends State<_ProcessingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 80,
        height: 80,
        child: Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.rotate(
              angle: _ctrl.value * 2 * pi,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [_kPrimary, _kAccent, Colors.transparent],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: const Center(
                child: Icon(Icons.lock_rounded, color: _kPrimary, size: 26)),
          ),
        ]),
      );
}

// ─── Pulse Dots ───────────────────────────────────────────────────────────────
class _PulseDots extends StatefulWidget {
  @override
  State<_PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<_PulseDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final t = ((_ctrl.value - delay) % 1.0 + 1.0) % 1.0;
            final scale = 0.6 + sin(t * pi) * 0.6;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8 * scale,
              height: 8 * scale,
              decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.4 + scale * 0.5),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      );
}

// ─── Modern Step Bar ─────────────────────────────────────────────────────────
class _ModernStepBar extends StatelessWidget {
  final int currentStep;
  const _ModernStepBar({required this.currentStep});

  static const _labels = ['Details', 'Payment', 'Processing'];
  static const _icons = [
    Icons.person_outline,
    Icons.payment,
    Icons.sync_rounded
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: List.generate(5, (i) {
          if (i.isEven) {
            final idx = i ~/ 2;
            final done = currentStep > idx;
            final active = currentStep == idx;
            return _StepDot(
              label: _labels[idx],
              icon: _icons[idx],
              done: done,
              active: active,
            );
          } else {
            final lineIdx = i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: currentStep > lineIdx
                      ? const LinearGradient(colors: [_kPrimary, _kAccent])
                      : null,
                  color: currentStep <= lineIdx ? _kBorder : null,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }
        }),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool done;
  final bool active;
  const _StepDot(
      {required this.label,
      required this.icon,
      required this.done,
      required this.active});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: (active || done)
              ? const LinearGradient(colors: [_kPrimary, _kAccent])
              : null,
          color: (active || done) ? null : _kBorder,
          boxShadow: active
              ? [
                  BoxShadow(
                      color: _kPrimary.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Center(
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Icon(icon, size: 15, color: active ? Colors.white : _kTextDim),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active
              ? _kPrimary
              : done
                  ? _kPrimary
                  : _kTextDim,
        ),
      ),
    ]);
  }
}

// ─── Room Summary Card ────────────────────────────────────────────────────────
class _RoomSummaryCard extends StatelessWidget {
  final RoomModel room;
  final int slots;
  final double total;
  const _RoomSummaryCard(
      {required this.room, required this.slots, required this.total});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_kPrimary.withOpacity(0.05), _kAccent.withOpacity(0.03)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kPrimary.withOpacity(0.15)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kPrimary, _kAccent]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bed_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  '${room.type} Room · No. ${room.roomNumber}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: _kDark),
                ),
                const SizedBox(height: 3),
                Text(
                  'GHS ${room.price.toStringAsFixed(2)} × $slots slot${slots > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12, color: _kTextMuted),
                ),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Total',
                style: TextStyle(fontSize: 11, color: _kTextDim)),
            Text(
              'GHS ${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: _kPrimary),
            ),
          ]),
        ]),
      );
}

// ─── Order Banner ─────────────────────────────────────────────────────────────
class _OrderBanner extends StatelessWidget {
  final RoomModel room;
  final int slots;
  final double total;
  const _OrderBanner(
      {required this.room, required this.slots, required this.total});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kDark,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Order Summary',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                  '${room.type} Room · ${room.roomNumber}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  '$slots slot${slots > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Pay',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            Text(
              'GHS ${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900),
            ),
          ]),
        ]),
      );
}

// ─── Slots Picker ─────────────────────────────────────────────────────────────
class _SlotsPicker extends StatelessWidget {
  final int slots;
  final int max;
  final double price;
  final void Function(int) onChanged;
  const _SlotsPicker(
      {required this.slots,
      required this.max,
      required this.price,
      required this.onChanged});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Number of Slots',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _kDark),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(max.clamp(0, 6), (i) {
            final n = i + 1;
            final selected = slots == n;
            return Expanded(
                child: GestureDetector(
              onTap: () => onChanged(n),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(right: i < max.clamp(0, 6) - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(colors: [_kPrimary, _kAccent])
                      : null,
                  color: selected ? null : _kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.transparent : _kBorder,
                    width: selected ? 0 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                              color: _kPrimary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ]
                      : [],
                ),
                child: Column(children: [
                  Text('$n',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : _kDark,
                      )),
                  const SizedBox(height: 2),
                  Text('slot${n > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 9,
                        color: selected ? Colors.white70 : _kTextDim,
                      )),
                ]),
              ),
            ));
          }),
        ),
      ]);
}

// ─── Total Card ───────────────────────────────────────────────────────────────
class _TotalCard extends StatelessWidget {
  final int slots;
  final double price;
  final double total;
  final double deposit;
  const _TotalCard(
      {required this.slots,
      required this.price,
      required this.total,
      required this.deposit});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: [_kPrimary, Color(0xFF0D9488)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: _kPrimary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
        ),
        child: Row(children: [
          const Icon(Icons.receipt_long_rounded,
              color: Colors.white70, size: 22),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  'GHS ${price.toStringAsFixed(2)} × $slots slot${slots > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (deposit > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Deposit required: GHS ${deposit.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'GHS ${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900),
                ),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Text('Total',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

// ─── Payment Detail Card ──────────────────────────────────────────────────────
class _PaymentDetailCard extends StatelessWidget {
  final String icon;
  final String provider;
  final String value;
  final Color color;
  const _PaymentDetailCard(
      {required this.icon,
      required this.provider,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(provider,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: _kDark),
                ),
              ])),
          GestureDetector(
            onTap: () {
              if (RegExp(r'^\d').hasMatch(value.trim()))
                launchUrl(Uri.parse('tel:$value'));
            },
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.phone_rounded,
                  color: Colors.white, size: 15),
            ),
          ),
        ]),
      );
}

// ─── Provider Tile ────────────────────────────────────────────────────────────
class _ProviderTile extends StatelessWidget {
  final String emoji;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _ProviderTile(
      {required this.emoji,
      required this.label,
      required this.isSelected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(colors: [
                    _kPrimary.withOpacity(0.08),
                    _kAccent.withOpacity(0.06)
                  ])
                : null,
            color: isSelected ? null : _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isSelected ? _kPrimary.withOpacity(0.5) : _kBorder,
                width: isSelected ? 1.5 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Flexible(
                child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? _kPrimary : _kTextMuted,
              ),
            )),
          ]),
        ),
      );
}

// ─── Info Banner ─────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoBanner(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 9),
          Expanded(
              child: Text(
            text,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
                height: 1.5),
          )),
        ]),
      );
}

// ─── Gradient CTA ─────────────────────────────────────────────────────────────
class _GradientCTA extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;
  final Color color;
  const _GradientCTA(
      {required this.label,
      required this.icon,
      required this.busy,
      this.onTap,
      this.color = _kPrimary});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: (busy || onTap == null) ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            gradient: (busy || onTap == null)
                ? LinearGradient(colors: [Colors.grey[350]!, Colors.grey[300]!])
                : LinearGradient(
                    colors: [color, color.withOpacity(0.85), _kAccent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: (busy || onTap == null)
                ? []
                : [
                    BoxShadow(
                        color: color.withOpacity(0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 6))
                  ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        )),
                    const SizedBox(width: 10),
                    Icon(icon, color: Colors.white, size: 18),
                  ]),
          ),
        ),
      );
}

// ─── Form helpers ─────────────────────────────────────────────────────────────
class _FormGroupLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _FormGroupLabel(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: _kPrimary),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: _kDark)),
      ]);
}

class _ModernField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final IconData? icon;
  final TextInputType? kb;
  final int lines;
  final String? hint;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool readOnly;
  const _ModernField({
    required this.label,
    required this.ctrl,
    this.icon,
    this.kb,
    this.lines = 1,
    this.hint,
    this.validator,
    this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 7),
          TextFormField(
            controller: ctrl,
            keyboardType: kb,
            maxLines: lines,
            readOnly: readOnly,
            validator: validator,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14, color: _kDark),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 13, color: _kTextDim),
              prefixIcon:
                  icon != null ? Icon(icon, size: 17, color: _kPrimary) : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              filled: true,
              fillColor: readOnly ? const Color(0xFFEEF2F6) : _kSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kRed),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kRed, width: 1.5),
              ),
            ),
          ),
        ]),
      );
}

// ─── Pay Mode Selector ────────────────────────────────────────────────────────
class _PayModeSelector extends StatelessWidget {
  final double depositAmount;
  final double totalAmount;
  final int selected;
  final void Function(int) onChanged;
  const _PayModeSelector({
    required this.depositAmount,
    required this.totalAmount,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      _PayModeOption(
        icon: Icons.lock_open_rounded,
        title: 'Pay Deposit',
        subtitle: 'GHS ${depositAmount.toStringAsFixed(2)}',
        tag: 'Minimum',
        tagColor: _kOrange,
        index: 0,
      ),
      _PayModeOption(
        icon: Icons.tune_rounded,
        title: 'Custom Amount',
        subtitle: '≥ GHS ${depositAmount.toStringAsFixed(2)}',
        tag: 'Flexible',
        tagColor: _kPrimary,
        index: 1,
      ),
      _PayModeOption(
        icon: Icons.check_circle_rounded,
        title: 'Pay in Full',
        subtitle: 'GHS ${totalAmount.toStringAsFixed(2)}',
        tag: 'Clears Balance',
        tagColor: _kGreen,
        index: 2,
      ),
    ];
    return Column(
      children: options
          .map((o) => _PayModeOptionTile(
                option: o,
                isSelected: selected == o.index,
                onTap: () => onChanged(o.index),
              ))
          .toList(),
    );
  }
}

class _PayModeOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final Color tagColor;
  final int index;
  const _PayModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.tagColor,
    required this.index,
  });
}

class _PayModeOptionTile extends StatelessWidget {
  final _PayModeOption option;
  final bool isSelected;
  final VoidCallback onTap;
  const _PayModeOptionTile(
      {required this.option, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? option.tagColor.withOpacity(0.06) : _kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? option.tagColor.withOpacity(0.5) : _kBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: isSelected
                    ? option.tagColor.withOpacity(0.12)
                    : Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(option.icon,
                  size: 18, color: isSelected ? option.tagColor : _kTextDim),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(option.title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? option.tagColor : _kDark)),
                  const SizedBox(height: 2),
                  Text(option.subtitle,
                      style: const TextStyle(fontSize: 12, color: _kTextMuted)),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: option.tagColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(option.tag,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: option.tagColor)),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? option.tagColor : Colors.transparent,
                border: Border.all(
                    color: isSelected ? option.tagColor : Colors.grey[350]!,
                    width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: Colors.white)
                  : null,
            ),
          ]),
        ),
      );
}

// ─── Payment Summary Strip ────────────────────────────────────────────────────
class _PaymentSummaryStrip extends StatelessWidget {
  final double amountToPay;
  final double balance;
  final double total;
  const _PaymentSummaryStrip({
    required this.amountToPay,
    required this.balance,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (amountToPay / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Paying now',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            Text('GHS ${amountToPay.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
          ]),
          if (balance > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Remaining balance',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('GHS ${balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ])
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, size: 13, color: _kGreen),
                SizedBox(width: 5),
                Text('Fully Paid',
                    style: TextStyle(
                        color: _kGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
        const SizedBox(height: 12),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
                balance == 0 ? _kGreen : _kAccent),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${(progress * 100).toStringAsFixed(0)}% of total',
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text('Total: GHS ${total.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }
}

// ─── Method Tile ──────────────────────────────────────────────────────────────
class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;
  const _MethodTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.07) : _kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color.withOpacity(0.5) : _kBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Icon(icon, size: 26, color: isSelected ? color : _kTextDim),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? color : _kDark)),
            const SizedBox(height: 2),
            Text(sublabel,
                style: const TextStyle(fontSize: 11, color: _kTextMuted)),
          ]),
        ),
      );
}

// ─── Error / Empty ────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _kBg,
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 44, color: _kRed),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextMuted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
              ),
            ),
          ]),
        )),
      );
}

class _EmptyBox extends StatelessWidget {
  final String message;
  const _EmptyBox({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bed_rounded, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        ]),
      );
}
