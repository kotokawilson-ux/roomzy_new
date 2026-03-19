// lib/widgets/hostels_list.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:responsive_framework/responsive_framework.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';

enum _LoadState { loading, success, empty, error }

/// Returns the image URL stored in Firestore (full Cloudinary URL).
/// Falls back to a placeholder if the field is null/empty.
String buildImageUrl(String? imageUrl) {
  if (imageUrl == null || imageUrl.trim().isEmpty) {
    return 'https://placehold.co/400x300?text=No+Image';
  }
  return imageUrl.trim();
}

class HostelsList extends StatefulWidget {
  final String searchQuery;
  const HostelsList({super.key, this.searchQuery = ''});

  @override
  State<HostelsList> createState() => _HostelsListState();
}

class _HostelsListState extends State<HostelsList> {
  List<Hostel> _hostels = [];
  List<Hostel> _filtered = [];
  _LoadState _state = _LoadState.loading;

  @override
  void initState() {
    super.initState();
    _loadHostels();
  }

  @override
  void didUpdateWidget(HostelsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _applySearch(widget.searchQuery);
    }
  }

  Future<void> _loadHostels() async {
    setState(() => _state = _LoadState.loading);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('hostels')
          .orderBy('hostel_name')
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
          print('❌ Failed to parse ${doc.id}: $e');
        }
      }

      setState(() {
        _hostels = hostels;
        _filtered = hostels;
        _state = _LoadState.success;
      });

      if (widget.searchQuery.isNotEmpty) {
        _applySearch(widget.searchQuery);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  void _applySearch(String query) {
    if (query.trim().isEmpty) {
      setState(() => _filtered = _hostels);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filtered = _hostels.where((h) {
        return h.hostelName.toLowerCase().contains(q) ||
            (h.town?.toLowerCase().contains(q) ?? false) ||
            (h.address?.toLowerCase().contains(q) ?? false) ||
            (h.schoolName?.toLowerCase().contains(q) ?? false);
      }).toList();
    });
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
      child: _buildContent(theme, isDesktop),
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
        if (_filtered.isEmpty) return _buildEmpty('No results found.');
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
    final childAspectRatio = !isDesktop ? 1.1 : 0.75;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filtered.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (_, index) =>
          _HostelCard(hostel: _filtered[index], theme: theme),
    );
  }

  Widget _buildShimmer(bool isDesktop) {
    final cols = isDesktop ? 3 : 1;
    final spacing = isDesktop ? 20.0 : 16.0;
    final childAspectRatio = !isDesktop ? 1.1 : 0.75;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(16),
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
              onPressed: _loadHostels,
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
          child: Text(
            message,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
}

/// ─── Modern Hostel Card ───────────────────────

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

    final imageHeight = isMobile ? 140.0 : 200.0;
    // ignore: unused_local_variable
    final fontSmall = isMobile ? 10.0 : 12.0;
    final fontMedium = isMobile ? 12.0 : 14.0;
    final fontLarge = isMobile ? 14.0 : 16.0;
    final iconSize = isMobile ? 14.0 : 16.0;
    final padding = isMobile ? 14.0 : 18.0;

    final imageUrl = buildImageUrl(hostel.image);

    return GestureDetector(
      onTap: () => context.go('/hostels/${hostel.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Hostel image from Cloudinary ──
              Image.network(
                imageUrl,
                height: imageHeight,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      height: imageHeight,
                      width: double.infinity,
                      color: Colors.grey[300],
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  height: imageHeight,
                  color: AppColors.primary.withOpacity(0.08),
                  child: const Center(
                    child: Icon(Icons.apartment_rounded,
                        size: 48, color: AppColors.primary),
                  ),
                ),
              ),
              // Card content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
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
                            color: textPrimary),
                      ),
                      const SizedBox(height: 8),
                      if (hostel.address != null && hostel.address!.isNotEmpty)
                        _InfoRow(
                            icon: Icons.location_on,
                            text: hostel.address!,
                            color: Colors.redAccent,
                            textColor: textSecondary,
                            iconSize: iconSize),
                      if (hostel.town != null && hostel.town!.isNotEmpty)
                        _InfoRow(
                            icon: Icons.map,
                            text: '${hostel.town}, Ghana',
                            color: Colors.blueGrey,
                            textColor: textSecondary,
                            iconSize: iconSize),
                      if (hostel.schoolName != null &&
                          hostel.schoolName!.isNotEmpty)
                        _InfoRow(
                            icon: Icons.school,
                            text: hostel.schoolShortName != null
                                ? '${hostel.schoolName} (${hostel.schoolShortName})'
                                : hostel.schoolName!,
                            color: AppColors.primary,
                            textColor: AppColors.primary,
                            iconSize: iconSize),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (hostel.priceRange != null)
                            _Badge(
                                icon: Icons.monetization_on_outlined,
                                text: hostel.priceRange!,
                                color: Colors.green),
                          _Badge(
                              icon: Icons.door_front_door_outlined,
                              text: available > 0
                                  ? '$available room${available > 1 ? 's' : ''}'
                                  : 'No rooms',
                              color: available > 0
                                  ? Colors.blue
                                  : Colors.redAccent),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.go('/hostels/${hostel.id}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                vertical: isMobile ? 12 : 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50)),
                            elevation: 0,
                          ),
                          child: Text('See Details',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: fontMedium)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─── Badge Widget ───────────────────────────
class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Badge(
      // ignore: unused_element_parameter
      {required this.icon,
      required this.text,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// ─── Info Row Widget ───────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color textColor;
  final double iconSize;

  const _InfoRow(
      {required this.icon,
      required this.text,
      required this.color,
      required this.textColor,
      required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
