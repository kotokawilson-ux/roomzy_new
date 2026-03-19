import 'package:flutter/material.dart';
import 'package:roomzy_find/core/theme/app_theme.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      color: theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;
          return isMobile
              ? Column(
                  children: [
                    _buildImage(),
                    const SizedBox(height: 40),
                    _buildFeatures(context),
                    const SizedBox(height: 40),
                    _buildStats(context),
                  ],
                )
              : Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: _buildFeatures(context)),
                        const SizedBox(width: 40),
                        Expanded(flex: 3, child: _buildImage()),
                      ],
                    ),
                    const SizedBox(height: 60),
                    _buildStats(context),
                  ],
                );
        },
      ),
    );
  }

  Widget _buildImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.network(
        'https://images.unsplash.com/photo-1555854877-bab0e564b8d5?w=800',
        fit: BoxFit.cover,
        height: 350,
        width: double.infinity,
      ),
    );
  }

  Widget _buildFeatures(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      {
        'icon': Icons.rate_review_rounded,
        'title': 'Student Reviews',
        'desc':
            'Read honest reviews from students who have stayed in these hostels to help you make better choices.',
      },
      {
        'icon': Icons.security_rounded,
        'title': 'Secure Payments',
        'desc':
            'Pay for your booking with trusted local payment options. Your transactions are safe and protected.',
      },
      {
        'icon': Icons.support_agent_rounded,
        'title': '24/7 Support',
        'desc':
            'Need help? Our support team is available around the clock to assist you with bookings or hostel inquiries.',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item['icon'] as IconData,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] as String,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item['desc'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStats(BuildContext context) {
    final theme = Theme.of(context);
    final stats = [
      {'number': '120', 'label': 'Rooms Available'},
      {'number': '75', 'label': 'Happy Residents'},
      {'number': '5', 'label': 'Years of Service'},
      {'number': '20', 'label': 'Staff Members'},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: stats.map((stat) {
            return SizedBox(
              width: constraints.maxWidth < 600
                  ? (constraints.maxWidth / 2) - 12
                  : (constraints.maxWidth / 4) - 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      stat['number']!,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stat['label']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
