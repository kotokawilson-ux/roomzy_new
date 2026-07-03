import 'package:flutter/material.dart';

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textPrimary = theme.textTheme.bodyMedium?.color ?? Colors.black;
    final textSecondary = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final surfaceColor = theme.cardColor;
    final primaryColor = theme.colorScheme.primary;

    final features = [
      {
        'icon': Icons.home_rounded,
        'title': 'Hostels near you',
        'desc':
            'Discover comfortable and affordable hostels located close to your campus or area of study.',
      },
      {
        'icon': Icons.event_available_rounded,
        'title': 'Easy booking',
        'desc':
            'Browse, compare, and reserve your preferred hostel room with a smooth and simple booking process.',
      },
      {
        'icon': Icons.verified_user_rounded,
        'title': 'Verified landlords',
        'desc':
            'Connect directly with trusted landlords and verified hostel managers for a safe and secure stay.',
      },
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      color: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading
          Text(
            'Why choose us',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We make finding your perfect hostel simple, safe, and fast.',
            style: TextStyle(fontSize: 14, color: textSecondary),
          ),
          const SizedBox(height: 32),

          // Responsive layout using Wrap — each card sizes to its own
          // content, so there's no fixed aspect ratio to overflow.
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              int columns = width >= 1200
                  ? 3
                  : width >= 800
                      ? 2
                      : 1;

              const spacing = 16.0;
              final cardWidth = (width - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: features
                    .map((f) => SizedBox(
                          width: cardWidth,
                          child: _FeatureCard(
                            icon: f['icon'] as IconData,
                            title: f['title'] as String,
                            desc: f['desc'] as String,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            surfaceColor: surfaceColor,
                            primaryColor: primaryColor,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Color textPrimary;
  final Color textSecondary;
  final Color surfaceColor;
  final Color primaryColor;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.textPrimary,
    required this.textSecondary,
    required this.surfaceColor,
    required this.primaryColor,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: widget.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_hovering ? 0.12 : 0.06),
              blurRadius: _hovering ? 16 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // mainAxisSize.min: the card is only ever as tall as its content
        // actually needs — there is no fixed height/aspect ratio to
        // overflow, no matter how long the title/description get.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: widget.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.icon, color: widget.primaryColor, size: 28),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              widget.desc,
              style: TextStyle(
                fontSize: 14,
                color: widget.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
