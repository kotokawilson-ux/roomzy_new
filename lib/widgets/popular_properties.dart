// lib/widgets/popular_properties.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';

/// Builds an optimized Cloudinary URL for fast loading.
/// - f_auto      → serves WebP/AVIF automatically (smaller file)
/// - q_auto:good → best quality/size balance
/// - w_800       → caps width at 800px (enough for cards)
/// - c_fill      → crops smartly to fill the frame
String buildImageUrl(String? imageUrl,
    {String seed = 'hostel', int width = 800}) {
  if (imageUrl == null || imageUrl.trim().isEmpty) {
    return 'https://placehold.co/600x400?text=No+Image';
  }
  final url = imageUrl.trim();

  if (url.contains('cloudinary.com') && url.contains('/upload/')) {
    return url.replaceFirst(
      '/upload/',
      '/upload/f_auto,q_auto:good,w_$width,c_fill/',
    );
  }
  return url;
}

enum _LoadState { loading, success, empty, error }

class PopularProperties extends StatefulWidget {
  const PopularProperties({super.key});

  @override
  State<PopularProperties> createState() => _PopularPropertiesState();
}

class _PopularPropertiesState extends State<PopularProperties> {
  final CarouselSliderController _controller = CarouselSliderController();

  List<Hostel> _hostels = [];
  _LoadState _state = _LoadState.loading;

  @override
  void initState() {
    super.initState();
    _loadHostels();
  }

  Future<void> _loadHostels() async {
    setState(() => _state = _LoadState.loading);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('hostels')
          .orderBy('hostel_name')
          .limit(10)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        setState(() => _state = _LoadState.empty);
        return;
      }

      final hostels = <Hostel>[];
      for (final doc in snapshot.docs) {
        try {
          hostels.add(Hostel.fromJson(doc.id, doc.data()));
        } catch (e) {
          debugPrint('❌ Failed to parse ${doc.id}: $e');
        }
      }

      setState(() {
        _hostels = hostels;
        _state = hostels.isEmpty ? _LoadState.empty : _LoadState.success;
      });

      // Warm image cache immediately after data loads
      if (mounted) _precacheImages();
    } catch (e) {
      debugPrint('❌ Firestore error: $e');
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  /// Downloads all carousel images into cache in the background.
  /// By the time the carousel renders, images are ready — no shimmer needed.
  void _precacheImages() {
    for (final hostel in _hostels) {
      final url =
          buildImageUrl(hostel.image, seed: hostel.hostelCode, width: 800);
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final surfaceColor = theme.cardColor;

    double cardWidth;
    if (screenWidth < 600) {
      cardWidth = screenWidth * 0.8;
    } else if (screenWidth < 1200) {
      cardWidth = screenWidth * 0.45;
    } else {
      cardWidth = screenWidth * 0.3;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      color: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Hostels / Apartments',
                style: TextStyle(
                  fontSize: screenWidth < 600 ? 22 : 28,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            'Browse student hostels and apartments near your school',
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodySmall?.color ?? Colors.grey,
            ),
          ),

          const SizedBox(height: 40),

          // ── Content ─────────────────────────
          _buildContent(screenWidth, cardWidth, surfaceColor, theme),
        ],
      ),
    );
  }

  Widget _buildContent(
    double screenWidth,
    double cardWidth,
    Color surfaceColor,
    ThemeData theme,
  ) {
    switch (_state) {
      case _LoadState.loading:
        return _buildShimmer(cardWidth, surfaceColor);
      case _LoadState.error:
        return _buildError();
      case _LoadState.empty:
        return _buildEmpty();
      case _LoadState.success:
        return _buildCarousel(screenWidth, cardWidth, surfaceColor, theme);
    }
  }

  Widget _buildCarousel(
    double screenWidth,
    double cardWidth,
    Color surfaceColor,
    ThemeData theme,
  ) {
    return CarouselSlider(
      carouselController: _controller,
      options: CarouselOptions(
        height: 460,
        viewportFraction: cardWidth / screenWidth,
        autoPlay: true,
        autoPlayInterval: const Duration(seconds: 4),
        enlargeCenterPage: true,
        enableInfiniteScroll: true,
        clipBehavior: Clip.none,
      ),
      items: _hostels
          .map(
            (hostel) => _HostelCard(
              hostel: hostel,
              textPrimary: theme.textTheme.bodyMedium?.color ?? Colors.black,
              textSecondary: theme.textTheme.bodySmall?.color ?? Colors.grey,
              surfaceColor: surfaceColor,
              width: cardWidth,
            ),
          )
          .toList(),
    );
  }

  Widget _buildShimmer(double cardWidth, Color surfaceColor) {
    return SizedBox(
      height: 460,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: cardWidth,
              height: 460,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 48),
          const SizedBox(height: 12),
          const Text('Could not load hostels', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadHostels,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(child: Text('No hostels available yet'));
  }
}

// ─── Individual hostel card ────────────────────────────────────
class _HostelCard extends StatelessWidget {
  final Hostel hostel;
  final Color textPrimary;
  final Color textSecondary;
  final Color surfaceColor;
  final double width;

  const _HostelCard({
    required this.hostel,
    required this.textPrimary,
    required this.textSecondary,
    required this.surfaceColor,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    // Optimized Cloudinary URL — WebP/AVIF, compressed, resized
    final imageUrl =
        buildImageUrl(hostel.image, seed: hostel.hostelCode, width: 800);
    final available = hostel.roomsAvailable;

    return GestureDetector(
      onTap: () => context.go('/hostels/${hostel.id}'),
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cached image — instant after first load ──
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  fadeOutDuration: const Duration(milliseconds: 100),
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(height: 160, color: surfaceColor),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 160,
                    color: AppColors.primary.withOpacity(0.08),
                    child: const Center(
                      child: Icon(Icons.apartment_rounded,
                          size: 40, color: AppColors.primary),
                    ),
                  ),
                ),

                // ── Details ────────────────────
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hostel name
                      Text(
                        hostel.hostelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Price range
                      if (hostel.priceRange != null)
                        Text(
                          hostel.priceRange!,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),

                      const SizedBox(height: 4),

                      // Address
                      if (hostel.address != null && hostel.address!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                hostel.address!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: textSecondary, fontSize: 11),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 4),

                      // Town, Ghana
                      if (hostel.town != null && hostel.town!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.location_city_outlined,
                                size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${hostel.town}, Ghana',
                              style:
                                  TextStyle(color: textSecondary, fontSize: 11),
                            ),
                          ],
                        ),

                      const SizedBox(height: 4),

                      // School name
                      if (hostel.schoolName != null &&
                          hostel.schoolName!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.school_outlined,
                                size: 12, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                hostel.schoolShortName != null
                                    ? '${hostel.schoolName} (${hostel.schoolShortName})'
                                    : hostel.schoolName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 6),

                      // Rooms available
                      Row(
                        children: [
                          const Icon(Icons.door_front_door_outlined,
                              size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            available > 0
                                ? '$available room${available > 1 ? 's' : ''} available'
                                : 'No rooms available yet',
                            style: TextStyle(
                              fontSize: 11,
                              color: available > 0
                                  ? Colors.green
                                  : Colors.redAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // See details button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.go('/hostels/${hostel.id}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'See Details',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Public HostelCard (used by other screens) ─────────────────
class HostelCard extends StatelessWidget {
  final Hostel hostel;
  final bool isDark;

  const HostelCard({required this.hostel, required this.isDark, super.key});

  @override
  Widget build(BuildContext context) {
    return _HostelCard(
      hostel: hostel,
      textPrimary:
          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      textSecondary:
          isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      surfaceColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
      width: 250,
    );
  }
}
