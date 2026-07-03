import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';

class TestimonialsSection extends StatefulWidget {
  const TestimonialsSection({super.key});

  @override
  State<TestimonialsSection> createState() => _TestimonialsSectionState();
}

class _TestimonialsSectionState extends State<TestimonialsSection> {
  final CarouselSliderController _controller = CarouselSliderController();
  int _activeIndex = 0;

  final List<Map<String, String>> _testimonials = [
    {
      'name': 'James Smith',
      'role': 'Student, Technical University (HTU)',
      'image': 'https://picsum.photos/seed/james/150/150',
      'quote':
          'Far far away, behind the word mountains, far from the countries Vokalia and Consonantia, there live the blind texts.',
    },
    {
      'name': 'Mike Houston',
      'role': 'Student, University of Health and Allied Sciences (UHAS)',
      'image': 'https://picsum.photos/seed/mike/150/150',
      'quote':
          'Separated they live in Bookmarksgrove right at the coast of the Semantics, a large language ocean.',
    },
    {
      'name': 'Cameron Webster',
      'role': 'Lecturer, Ho Technical University',
      'image': 'https://picsum.photos/seed/cameron/150/150',
      'quote':
          'Far far away, behind the word mountains, far from the countries Vokalia and Consonantia.',
    },
    {
      'name': 'Dave Smith',
      'role': 'Student, Technical University (HTU)',
      'image': 'https://picsum.photos/seed/dave/150/150',
      'quote':
          'Separated they live in Bookmarksgrove right at the coast of the Semantics, a large language ocean.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final textPrimary = theme.textTheme.bodyMedium?.color ?? Colors.black;
    final textSecondary = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final surfaceColor = theme.cardColor;
    final primaryColor = theme.colorScheme.primary;

    double cardWidth;
    if (screenWidth < 600) {
      cardWidth = screenWidth * 0.82;
    } else if (screenWidth < 1200) {
      cardWidth = screenWidth * 0.45;
    } else {
      cardWidth = screenWidth * 0.3;
    }

    // Fixed height tall enough for avatar + stars + name + a 4-line quote +
    // role + padding, with margin to spare — no clipping needed.
    const cardHeight = 320.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      color: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'What students say',
                style: TextStyle(
                  fontSize: screenWidth < 600 ? 22 : 28,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Real experiences from students who found their home through us.',
            style: TextStyle(fontSize: 14, color: textSecondary),
          ),

          const SizedBox(height: 40),

          // ── Carousel ───────────────────────
          CarouselSlider(
            carouselController: _controller,
            options: CarouselOptions(
              height: cardHeight,
              viewportFraction: (cardWidth / screenWidth).clamp(0.3, 0.95),
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 5),
              enlargeCenterPage: true,
              enableInfiniteScroll: true,
              clipBehavior: Clip.none,
              onPageChanged: (index, reason) {
                setState(() => _activeIndex = index);
              },
            ),
            items: _testimonials
                .map(
                  (t) => _TestimonialCard(
                    name: t['name']!,
                    role: t['role']!,
                    image: t['image']!,
                    quote: t['quote']!,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    surfaceColor: surfaceColor,
                    primaryColor: primaryColor,
                    width: cardWidth,
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),

          // ── Dot indicators ─────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _testimonials.asMap().entries.map((entry) {
              final isActive = _activeIndex == entry.key;
              return GestureDetector(
                onTap: () => _controller.animateToPage(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? primaryColor
                        : primaryColor.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Individual testimonial card
class _TestimonialCard extends StatelessWidget {
  final String name;
  final String role;
  final String image;
  final String quote;
  final Color textPrimary;
  final Color textSecondary;
  final Color surfaceColor;
  final Color primaryColor;
  final double width;

  const _TestimonialCard({
    required this.name,
    required this.role,
    required this.image,
    required this.quote,
    required this.textPrimary,
    required this.textSecondary,
    required this.surfaceColor,
    required this.primaryColor,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // No fixed inner height and no scroll-to-hide-overflow trick — the
      // outer CarouselOptions.height (320) already gives this column
      // enough room for every element below, including a 4-line quote.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: primaryColor.withOpacity(0.25), width: 2),
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  radius: 26,
                  backgroundImage: NetworkImage(image),
                  onBackgroundImageError: (_, __) {},
                  backgroundColor: Colors.grey[200],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      role,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: textSecondary.withOpacity(0.75),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.format_quote_rounded,
                  color: primaryColor.withOpacity(0.25), size: 30),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(
              5,
              (i) =>
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            quote,
            style: TextStyle(
              fontSize: 13,
              color: textSecondary,
              height: 1.65,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
