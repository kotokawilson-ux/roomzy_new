import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();

    // Use the 2s splash window to warm ALL image caches
    // so the home screen loads instantly on arrival
    _initAndNavigate();
  }

  Future<void> _initAndNavigate() async {
    // Run the minimum splash timer AND image precaching in parallel.
    // Navigation only happens after BOTH are done — but since precaching
    // is fast (fire-and-forget HTTP), the 2s timer is usually the bottleneck.
    await Future.wait([
      Future.delayed(const Duration(seconds: 2)),
      _precacheEverything(),
    ]);

    if (!mounted) return;
    context.go('/home');
  }

  /// Fetches hostel data and warms the CachedNetworkImage disk cache
  /// for all images the home screen will display.
  Future<void> _precacheEverything() async {
    try {
      // Hero section background images (Unsplash — static)
      const heroImages = [
        'https://images.unsplash.com/photo-1555854877-bab0e564b8d5?w=1600&q=80&fm=webp&fit=crop',
        'https://images.unsplash.com/photo-1562664377-709f2c337eb2?w=1600&q=80&fm=webp&fit=crop',
      ];
      for (final url in heroImages) {
        CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      }

      // Hostel images from Firestore (carousel + list)
      final snapshot = await FirebaseFirestore.instance
          .collection('hostels')
          .orderBy('hostel_name')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Main image
        final image = data['image'] as String?;
        if (image != null && image.trim().isNotEmpty) {
          final url = _optimizedUrl(image.trim());
          CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
        }

        // Extra images (comma-separated)
        final images = data['images'] as String?;
        if (images != null && images.trim().isNotEmpty) {
          for (final img in images.split(',')) {
            final trimmed = img.trim();
            if (trimmed.isNotEmpty) {
              CachedNetworkImageProvider(_optimizedUrl(trimmed))
                  .resolve(const ImageConfiguration());
            }
          }
        }
      }
    } catch (e) {
      // Precaching is best-effort — never block navigation on failure
      debugPrint('Precache error: $e');
    }
  }

  /// Injects Cloudinary optimization params into the URL
  String _optimizedUrl(String url) {
    if (url.contains('cloudinary.com') && url.contains('/upload/')) {
      return url.replaceFirst(
        '/upload/',
        '/upload/f_auto,q_auto:good,w_800,c_fill/',
      );
    }
    return url;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.home_rounded,
                      size: 56,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    AppConstants.appName,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    AppConstants.appTagline,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
