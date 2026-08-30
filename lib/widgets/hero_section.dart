import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

class HeroSection extends StatefulWidget {
  const HeroSection({super.key});

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  // Bundled fallback — used until the settings/site_images doc loads, and
  // whenever it's missing or its home_hero_images field is empty, so the
  // carousel never shows a blank frame.
  static const List<String> _defaultImages = [
    'https://i.ibb.co/hJph6Xyc/h1.jpg',
    'https://i.ibb.co/fzcNGgwq/hostel.jpg',
  ];

  // The admin-editable Site Images card in settings writes here — this
  // stream keeps the carousel in sync with it live, no redeploy needed.
  List<String> _images = _defaultImages;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('settings')
        .doc('site_images')
        .snapshots()
        .listen((snap) {
      final raw = snap.data()?['hero_images'];
      if (raw is List && raw.isNotEmpty) {
        final urls = raw.map((e) => e.toString()).toList();
        for (final url in urls) {
          CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
        }
        if (mounted) setState(() => _images = urls);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache whatever we currently have (defaults, until/unless the
    // Firestore listener above replaces them) as soon as the widget mounts
    // so by the time the carousel starts they're already in memory.
    for (final url in _images) {
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final headlineSize = screenWidth < 600
        ? 20.0
        : screenWidth < 900
            ? 26.0
            : 32.0;
    final taglineSize = screenWidth < 600
        ? 12.0
        : screenWidth < 900
            ? 14.0
            : 16.0;

    return SizedBox(
      height: screenHeight * 0.85,
      child: Stack(
        children: [
          // ── Background Carousel — cached + optimized
          CarouselSlider(
            options: CarouselOptions(
              height: screenHeight * 0.85,
              viewportFraction: 1,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 5),
              autoPlayAnimationDuration: const Duration(milliseconds: 900),
              autoPlayCurve: Curves.easeInOut,
            ),
            items: _images.map((url) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // CachedNetworkImage — instant after first load
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 300),
                    // Dark placeholder while loading — matches the overlay
                    placeholder: (_, __) => Container(color: Colors.black87),
                    errorWidget: (_, __, ___) => Container(color: Colors.black),
                  ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),

          // ── Hero Content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth < 600 ? 20 : 36,
                    vertical: screenWidth < 600 ? 30 : 60,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.black.withOpacity(0.45),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Animated Headline
                      AnimatedTextKit(
                        repeatForever: true,
                        pause: const Duration(milliseconds: 1500),
                        animatedTexts: [
                          TypewriterAnimatedText(
                            'Find perfect hostel/apartment near you.',
                            speed: const Duration(milliseconds: 70),
                            cursor: '|',
                            textStyle: TextStyle(
                              fontSize: headlineSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.3,
                              shadows: const [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ── Tagline
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'Book easily • Pay securely • Live comfortably',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: taglineSize,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFFFEFCF),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
