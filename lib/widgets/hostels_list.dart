// lib/widgets/hostels_list.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:responsive_framework/responsive_framework.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import 'dart:async';

enum _LoadState { loading, success, empty, error }

String buildImageUrl(String? imageUrl, {int width = 800}) {
  if (imageUrl == null || imageUrl.trim().isEmpty) {
    return 'https://placehold.co/400x300?text=No+Image';
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

class HostelsList extends StatefulWidget {
  final String searchQuery;
  final double? budgetFilter;
  final String durationFilter;

  const HostelsList({
    super.key,
    this.searchQuery = '',
    this.budgetFilter,
    this.durationFilter = 'Per month',
  });

  @override
  State<HostelsList> createState() => _HostelsListState();
}

class _HostelsListState extends State<HostelsList> {
  List<Hostel> _hostels = [];
  List<Hostel> _filtered = [];
  _LoadState _state = _LoadState.loading;
  StreamSubscription? _hostelsSub;

  @override
  void initState() {
    super.initState();
    _startListener();
  }

  @override
  void dispose() {
    _hostelsSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(HostelsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final queryChanged = oldWidget.searchQuery != widget.searchQuery;
    final budgetChanged = oldWidget.budgetFilter != widget.budgetFilter;
    final durationChanged = oldWidget.durationFilter != widget.durationFilter;
    if (queryChanged || budgetChanged || durationChanged) {
      _applyFilters(widget.searchQuery, widget.budgetFilter);
    }
  }

  void _startListener() {
    setState(() => _state = _LoadState.loading);

    _hostelsSub = FirebaseFirestore.instance
        .collection('hostels')
        .orderBy('hostel_name')
        .snapshots()
        .listen(
      (snapshot) {
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
          _state = _LoadState.success;
        });

        _applyFilters(widget.searchQuery, widget.budgetFilter);
        if (mounted) _precacheImages();
      },
      onError: (e) {
        if (!mounted) return;
        debugPrint('❌ Hostels listener error: $e');
        setState(() => _state = _LoadState.error);
      },
    );
  }

  void _precacheImages() {
    for (final hostel in _hostels) {
      final url = buildImageUrl(hostel.image, width: 800);
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
    }
  }

  // ── Extract all numbers from a price string ──────────────────────────────
  // Handles: "GHS 800 - 2200", "GH₵1,200", "800", "GHS 1000-1700"
  List<double> _extractNumbers(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    final cleaned =
        raw.replaceAll(RegExp(r'[A-Za-z₵¢]'), '').replaceAll(',', '');
    final matches = RegExp(r'\d+\.?\d*').allMatches(cleaned);
    return matches
        .map((m) => double.tryParse(m.group(0)!))
        .whereType<double>()
        .toList();
  }

// ── Normalize duration strings for comparison ─────────────────────────────
// Maps all variations to a canonical key
  String _normalizeDuration(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final d = raw.toLowerCase().trim();
    if (d.contains('month')) return 'month';
    if (d.contains('semester')) return 'semester';
    if (d.contains('year') || d.contains('annual')) return 'year';
    return d;
  }

  // ── Get minimum price from range e.g. "GHS 800 - 2200" → 800.0 ──────────
  double? _getMinPrice(String? raw) {
    final nums = _extractNumbers(raw);
    if (nums.isEmpty) return null;
    nums.sort();
    return nums.first;
  }

  // ── Get maximum price from range e.g. "GHS 800 - 2200" → 2200.0 ─────────
  double? _getMaxPrice(String? raw) {
    final nums = _extractNumbers(raw);
    if (nums.isEmpty) return null;
    nums.sort();
    return nums.last; // largest number = max price
  }

  // ── Filter logic ──────────────────────────────────────────────────────────
  // Show hostel if: budget >= minPrice of hostel's range
  // Example: budget=2100, range="GHS 800-2200" → minPrice=800 → 2100>=800 ✓
  // Example: budget=500,  range="GHS 800-2200" → minPrice=800 → 500>=800  ✗
  // Example: budget=1000, range="GHS 1000-1700"→ minPrice=1000→ 1000>=1000✓
  void _applyFilters(String query, double? budget) {
    List<Hostel> results = _hostels;

    // ── 1. Search filter ────────────────────────────────────────────────────
    if (query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      results = results.where((h) {
        return h.hostelName.toLowerCase().contains(q) ||
            (h.town?.toLowerCase().contains(q) ?? false) ||
            (h.address?.toLowerCase().contains(q) ?? false) ||
            (h.schoolName?.toLowerCase().contains(q) ?? false) ||
            (h.schoolShortName?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    // ── Budget filter ────────────────────────────────────────────────────
    // ── 2. Budget + Duration filter ─────────────────────────────────────────
    if (budget != null && budget > 0) {
      final userDuration = _normalizeDuration(widget.durationFilter);

      results = results.where((h) {
        // No price listed → include (don't hide unlisted hostels)
        if (h.priceRange == null || h.priceRange!.trim().isEmpty) return true;

        // ── Duration must match ──────────────────────────────────────────────
        // e.g. user picks "Per semester", hostel is "Per year" → exclude
        final hostelDuration = _normalizeDuration(h.durationType);
        if (hostelDuration.isNotEmpty &&
            userDuration.isNotEmpty &&
            hostelDuration != userDuration) {
          return false; // duration mismatch → hide
        }

        // ── Price must be within budget ──────────────────────────────────────
        final minPrice = _getMinPrice(h.priceRange);
        if (minPrice == null) return true; // can't parse → include

        // Show hostel only if user's budget >= hostel's minimum price
        // e.g. budget=2100, range="GHS 800-2200" → minPrice=800 → 2100>=800 ✓
        // e.g. budget=500,  range="GHS 800-2200" → minPrice=800 → 500>=800  ✗
        // e.g. budget=50000 but duration mismatch → already excluded above
        return budget >= minPrice;
      }).toList();
    }

    setState(() => _filtered = results);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = ResponsiveBreakpoints.of(context).largerThan(TABLET);

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 40,
        horizontal: isDesktop ? 48 : 20,
      ),
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_state == _LoadState.success) ...[
            _ResultsHeader(
              count: _filtered.length,
              budget: widget.budgetFilter,
              duration: widget.durationFilter,
              query: widget.searchQuery,
            ),
            const SizedBox(height: 24),
          ],
          _buildContent(theme, isDesktop),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDesktop) {
    switch (_state) {
      case _LoadState.loading:
        return _buildShimmer(isDesktop);
      case _LoadState.error:
        return _buildError();
      case _LoadState.empty:
        return _buildEmpty('No hostels found.');
      case _LoadState.success:
        if (_filtered.isEmpty) {
          return _buildEmpty(
            widget.budgetFilter != null
                ? 'No hostels found within GH₵${widget.budgetFilter!.toStringAsFixed(0)} ${widget.durationFilter.toLowerCase()}.\nTry a higher budget or different duration.'
                : 'No results found.',
          );
        }
        return _buildGrid(theme, isDesktop);
    }
  }

  Widget _buildGrid(ThemeData theme, bool isDesktop) {
    final crossAxisCount = !isDesktop
        ? 1
        : ResponsiveBreakpoints.of(context).largerThan(DESKTOP)
            ? 4
            : 3;
    final spacing = !isDesktop
        ? 16.0
        : ResponsiveBreakpoints.of(context).largerThan(DESKTOP)
            ? 24.0
            : 20.0;

    if (!isDesktop) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: (_, index) =>
            _HostelCard(hostel: _filtered[index], theme: theme),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filtered.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (_, index) =>
          _HostelCard(hostel: _filtered[index], theme: theme),
    );
  }

  Widget _buildShimmer(bool isDesktop) {
    final cols = isDesktop ? 3 : 1;
    final spacing = isDesktop ? 20.0 : 16.0;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: isDesktop ? 0.75 : 1.3,
      ),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48),
            const SizedBox(height: 12),
            const Text('Could not load hostels',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _startListener,
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _buildEmpty(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 52, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
}

// ─── Results Header ───────────────────────────────────────────────────────────
class _ResultsHeader extends StatelessWidget {
  final int count;
  final double? budget;
  final String duration;
  final String query;

  const _ResultsHeader({
    required this.count,
    required this.budget,
    required this.duration,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count hostel${count != 1 ? 's' : ''} found',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _buildSubtitle(),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
        if (budget != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(50),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Budget: GH₵${budget!.toStringAsFixed(0)} / $duration',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    if (query.trim().isNotEmpty) parts.add('matching "$query"');
    if (budget != null) {
      parts.add('budget GH₵${budget!.toStringAsFixed(0)} · $duration');
    }
    return parts.isEmpty ? 'All available hostels' : parts.join(' · ');
  }
}

// ─── Modern Hostel Card ───────────────────────────────────────────────────────
class _HostelCard extends StatelessWidget {
  final Hostel hostel;
  final ThemeData theme;

  const _HostelCard({required this.hostel, required this.theme});

  @override
  Widget build(BuildContext context) {
    final textPrimary = theme.textTheme.bodyMedium?.color ?? Colors.black;
    final textSecondary = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final surfaceColor = theme.cardColor;
    final available = hostel.roomsAvailable;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final imageHeight = isMobile ? 180.0 : 200.0;
    final fontMedium = isMobile ? 12.0 : 14.0;
    final fontLarge = isMobile ? 14.0 : 16.0;
    final iconSize = isMobile ? 14.0 : 16.0;
    final padding = isMobile ? 14.0 : 18.0;

    final imageUrl = buildImageUrl(hostel.image, width: 800);

    return GestureDetector(
      onTap: () => context.push('/hostels/${hostel.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                height: imageHeight,
                width: double.infinity,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                fadeOutDuration: const Duration(milliseconds: 100),
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: imageHeight,
                    width: double.infinity,
                    color: Colors.grey[300],
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: imageHeight,
                  color: AppColors.primary.withValues(alpha: 0.08),
                  child: const Center(
                    child: Icon(Icons.apartment_rounded,
                        size: 48, color: AppColors.primary),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      hostel.hostelName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontLarge,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (hostel.address != null && hostel.address!.isNotEmpty)
                      _InfoRow(
                        icon: Icons.location_on,
                        text: hostel.address!,
                        color: Colors.redAccent,
                        textColor: textSecondary,
                        iconSize: iconSize,
                      ),
                    if (hostel.town != null && hostel.town!.isNotEmpty)
                      _InfoRow(
                        icon: Icons.map,
                        text: '${hostel.town}, Ghana',
                        color: Colors.blueGrey,
                        textColor: textSecondary,
                        iconSize: iconSize,
                      ),
                    if (hostel.schoolName != null &&
                        hostel.schoolName!.isNotEmpty)
                      _InfoRow(
                        icon: Icons.school,
                        text: hostel.schoolShortName != null
                            ? '${hostel.schoolName} (${hostel.schoolShortName})'
                            : hostel.schoolName!,
                        color: AppColors.primary,
                        textColor: AppColors.primary,
                        iconSize: iconSize,
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (hostel.priceRange != null)
                          _Badge(
                            icon: Icons.monetization_on_outlined,
                            text: hostel.priceRange!,
                            color: Colors.green,
                          ),
                        _Badge(
                          icon: Icons.door_front_door_outlined,
                          text: available > 0
                              ? '$available room${available > 1 ? 's' : ''}'
                              : 'No rooms',
                          color: available > 0 ? Colors.blue : Colors.redAccent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.push('/hostels/${hostel.id}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'See Details',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: fontMedium,
                          ),
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
    );
  }
}

// ─── Badge Widget ─────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Badge({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Row Widget ──────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color textColor;
  final double iconSize;

  const _InfoRow({
    required this.icon,
    required this.text,
    required this.color,
    required this.textColor,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
