import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';

class TestimonialsSection extends StatefulWidget {
  const TestimonialsSection({super.key});

  @override
  State<TestimonialsSection> createState() => _TestimonialsSectionState();
}

class _TestimonialsSectionState extends State<TestimonialsSection> {
  final CarouselSliderController _controller = CarouselSliderController();

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
          Text(
            'Customer Says',
            style: TextStyle(
              fontSize: screenWidth < 600 ? 22 : 28,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),

          const SizedBox(height: 40),

          // ── Carousel ───────────────────────
          CarouselSlider(
            carouselController: _controller,
            options: CarouselOptions(
              height: 280,
              viewportFraction: cardWidth / screenWidth,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 5),
              enlargeCenterPage: true,
              enableInfiniteScroll: true,
              clipBehavior: Clip.none,
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
                    width: cardWidth,
                  ),
                )
                .toList(),
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
  final double width;

  const _TestimonialCard({
    required this.name,
    required this.role,
    required this.image,
    required this.quote,
    required this.textPrimary,
    required this.textSecondary,
    required this.surfaceColor,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      // ← ClipRRect + SingleChildScrollView fixes overflow stripes
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 32,
                  backgroundImage: NetworkImage(image),
                  onBackgroundImageError: (_, __) {},
                  backgroundColor: Colors.grey[200],
                ),

                const SizedBox(height: 12),

                // Stars
                Row(
                  children: List.generate(
                    5,
                    (i) => const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 18),
                  ),
                ),

                const SizedBox(height: 8),

                // Name
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                // Quote
                Text(
                  '"$quote"',
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.6,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Role
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 11,
                    color: textSecondary.withOpacity(0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
