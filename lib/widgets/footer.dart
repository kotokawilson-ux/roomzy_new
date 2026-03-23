import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:roomzy_find/core/theme/app_theme.dart';
import 'package:roomzy_find/core/constants/app_constants.dart';

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          // ── Top Row ───────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 700;
              return isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBrand(context),
                        const SizedBox(height: 32),
                        _buildLinks(context),
                        const SizedBox(height: 32),
                        _buildContact(),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildBrand(context)),
                        Expanded(child: _buildLinks(context)),
                        Expanded(child: _buildContact()),
                      ],
                    );
            },
          ),

          const SizedBox(height: 40),
          const Divider(color: Colors.white24),
          const SizedBox(height: 20),

          // ── Bottom Row ────────────────────────────────────
          Text(
            '© ${DateTime.now().year} ${AppConstants.appName}. All rights reserved.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.home_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              AppConstants.appName,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Find your perfect student home near your campus. Browse, book, and move in with ease.',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 13,
            height: 1.7,
          ),
        ),
      ],
    );
  }

  Widget _buildLinks(BuildContext context) {
    final links = [
      {'label': 'Home', 'route': '/home'},
      {'label': 'Hostels / Apartments', 'route': '/hostels'},
      {'label': 'About', 'route': '/about'},
      {'label': 'Contact', 'route': '/contact'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Links',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ...links.map((link) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => context.go(link['route']!),
                child: Text(
                  link['label']!,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Us',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _contactItem(Icons.email_rounded, 'kotokawilson@roomzyfind.com'),
        _contactItem(Icons.phone_rounded, '+233 25 721 9035'),
        _contactItem(Icons.location_on_rounded, 'Ghana'),
      ],
    );
  }

  Widget _contactItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
