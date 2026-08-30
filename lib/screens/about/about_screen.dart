// lib/screens/about/about_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _kPrimary = Color(0xFF0F766E);
const _kAccent = Color(0xFF14B8A6);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kCard = Colors.white;
const _kSurface = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE2E8F0);
const _kTextMuted = Color(0xFF64748B);
const _kTextDim = Color(0xFF94A3B8);

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appVersion = '1.0.0';

  static const _features = [
    (
      'Verified Listings',
      Icons.verified_rounded,
      'Every hostel is reviewed before it appears in search results.'
    ),
    (
      'Secure Mobile Money',
      Icons.lock_rounded,
      'Pay deposits and balances safely with MTN MoMo and Vodafone Cash.'
    ),
    (
      'Pre-Booking Visits',
      Icons.event_available_rounded,
      'Schedule a visit before committing to a room.'
    ),
    (
      'Direct Support Chat',
      Icons.headset_mic_rounded,
      'Reach our team in-app for quick help, any time.'
    ),
  ];

  static const _steps = [
    (
      Icons.search_rounded,
      'Search Hostels',
      'Browse verified hostels near your school, filter by price, room type, and amenities.'
    ),
    (
      Icons.bookmark_add_rounded,
      'Pre-Book Your Room',
      'Reserve it instantly so no one else takes your spot while you decide.'
    ),
    (
      Icons.payments_rounded,
      'Confirm & Pay Securely',
      'Complete your booking with MTN MoMo or Vodafone Cash. Every transaction is protected.'
    ),
    (
      Icons.verified_rounded,
      'Secure Your Spot',
      'Get instant confirmation and booking details. The room is officially yours.'
    ),
    (
      Icons.home_work_rounded,
      'Move In & Settle',
      'Show up on move-in day with everything sorted. Support is there if you need it.'
    ),
  ];

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _kDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('About',
            style: TextStyle(
                color: _kDark, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          // ── App logo & name ────────────────────────────────────────────
          Center(
            child: Column(children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kPrimary, _kAccent]),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                        color: _kPrimary.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.home_work_rounded,
                    color: Colors.white, size: 38),
              ),
              const SizedBox(height: 16),
              const Text('RoomzyFind',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _kDark)),
              const SizedBox(height: 4),
              Text('Version $_appVersion',
                  style: const TextStyle(fontSize: 13, color: _kTextDim)),
            ]),
          ),
          const SizedBox(height: 28),

          // ── Description ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorder),
            ),
            child: const Text(
              'RoomzyFind helps students find and book verified hostels and '
              'student apartments near their school, with transparent pricing, '
              'secure mobile money payments, and support at every step — from '
              'browsing rooms to moving in.',
              style: TextStyle(fontSize: 14, color: _kTextMuted, height: 1.7),
            ),
          ),
          const SizedBox(height: 28),

          // ── How it works ───────────────────────────────────────────────
          const Text('How it works',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kTextMuted,
                  letterSpacing: 0.4)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 4),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: List.generate(_steps.length, (i) {
                final step = _steps[i];
                final isLast = i == _steps.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 16 : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _kPrimary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(step.$1, color: _kPrimary, size: 18),
                          ),
                          if (!isLast)
                            Container(
                              width: 2,
                              height: 44,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: _kBorder,
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(step.$2,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: _kDark)),
                              const SizedBox(height: 3),
                              Text(step.$3,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: _kTextMuted,
                                      height: 1.45)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 28),

          const Text('What you can do',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kTextMuted,
                  letterSpacing: 0.4)),
          const SizedBox(height: 12),

          ..._features.map((f) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(f.$2, color: _kPrimary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.$1,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _kDark)),
                        const SizedBox(height: 2),
                        Text(f.$3,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: _kTextMuted,
                                height: 1.4)),
                      ],
                    ),
                  ),
                ]),
              )),

          const SizedBox(height: 16),

          // ── Legal links ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorder),
            ),
            child: Column(children: [
              _LinkRow(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: () => _openUrl('https://roomzyfind.com/terms'),
              ),
              Divider(height: 1, indent: 58, color: _kBorder),
              _LinkRow(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => _openUrl('https://roomzyfind.com/privacy'),
              ),
              Divider(height: 1, indent: 58, color: _kBorder),
              _LinkRow(
                icon: Icons.star_outline_rounded,
                label: 'Rate the App',
                onTap: () => _openUrl('https://roomzyfind.com'),
              ),
            ]),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text('© ${DateTime.now().year} RoomzyFind',
                style: const TextStyle(fontSize: 12, color: _kTextDim)),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: _kPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _kDark)),
            ),
            const Icon(Icons.open_in_new_rounded, color: _kTextDim, size: 16),
          ]),
        ),
      );
}
