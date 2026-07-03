import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:roomzy_find/core/theme/app_theme.dart';
import 'package:roomzy_find/core/constants/app_constants.dart';

/// Responsive breakpoints used throughout the footer.
/// - mobile:  < 640
/// - tablet:  640 – 1024
/// - desktop: >= 1024
class _Breakpoints {
  static const double mobile = 640;
  static const double tablet = 1024;

  static bool isMobile(double w) => w < mobile;
  static bool isTablet(double w) => w >= mobile && w < tablet;
  static bool isDesktop(double w) => w >= tablet;
}

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF14141F),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Decorative blurred blobs — purely visual, never affect layout.
          const Positioned(
            top: -60,
            left: -40,
            child: _Blob(size: 220, opacity: 0.22),
          ),
          const Positioned(
            top: 120,
            right: -60,
            child: _Blob(size: 260, opacity: 0.14),
          ),

          Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final horizontalPad = _Breakpoints.isMobile(width)
                      ? 20.0
                      : _Breakpoints.isTablet(width)
                          ? 32.0
                          : 24.0;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                        horizontalPad, 40, horizontalPad, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: const _NewsletterCard(),
                      ),
                    ),
                  );
                },
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final horizontalPad = _Breakpoints.isMobile(width)
                      ? 20.0
                      : _Breakpoints.isTablet(width)
                          ? 32.0
                          : 24.0;

                  return Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: 48, horizontal: horizontalPad),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: _buildMainContent(context, width),
                      ),
                    ),
                  );
                },
              ),
              Container(height: 1, color: Colors.white.withOpacity(0.08)),
              const _BottomBar(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, double width) {
    if (_Breakpoints.isMobile(width)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrand(context, compact: true),
          const SizedBox(height: 28),
          _buildPaymentBadges(),
          const SizedBox(height: 28),
          _CollapsibleSection(
            title: 'Quick Links',
            child: _buildLinksContent(context),
          ),
          _CollapsibleSection(
            title: 'Legal & Support',
            child: _buildLegalContent(context),
          ),
          _CollapsibleSection(
            title: 'Contact Us',
            child: _buildContactContent(),
          ),
        ],
      );
    }

    if (_Breakpoints.isTablet(width)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrand(context, compact: false),
          const SizedBox(height: 24),
          _buildPaymentBadges(),
          const SizedBox(height: 36),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildLinks(context)),
              Expanded(child: _buildLegal(context)),
              Expanded(child: _buildContact()),
            ],
          ),
        ],
      );
    }

    // Desktop
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBrand(context, compact: false),
              const SizedBox(height: 24),
              _buildPaymentBadges(),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: _buildLinks(context)),
        Expanded(flex: 2, child: _buildLegal(context)),
        Expanded(flex: 3, child: _buildContact()),
      ],
    );
  }

  Widget _buildBrand(BuildContext context, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.home_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                AppConstants.appName,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: compact ? double.infinity : 320),
          child: const Text(
            'Find your perfect student home near your campus. Browse, book, and '
            'move in with ease — verified hostels, transparent pricing, zero stress.',
            style:
                TextStyle(color: Colors.white54, fontSize: 13.5, height: 1.7),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SocialIcon(icon: Icons.facebook_rounded, onTap: () {}),
            _SocialIcon(icon: Icons.camera_alt_rounded, onTap: () {}),
            _SocialIcon(icon: Icons.alternate_email_rounded, onTap: () {}),
            _SocialIcon(icon: Icons.chat_bubble_rounded, onTap: () {}),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentBadges() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'We accept',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _PaymentBadge(label: 'MTN MoMo'),
            _PaymentBadge(label: 'Vodafone Cash'),
            _PaymentBadge(label: 'Paystack'),
            _PaymentBadge(label: 'Visa / Mastercard'),
          ],
        ),
      ],
    );
  }

  Widget _buildLinks(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Quick Links'),
        const SizedBox(height: 18),
        _buildLinksContent(context),
      ],
    );
  }

  Widget _buildLinksContent(BuildContext context) {
    final links = [
      {'label': 'Home', 'route': '/home'},
      {'label': 'Hostels / Apartments', 'route': '/hostels'},
      {'label': 'About', 'route': '/about'},
      {'label': 'Contact', 'route': '/contact'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: links
          .map((l) => _FooterLink(
                label: l['label']!,
                onTap: () => context.go(l['route']!),
              ))
          .toList(),
    );
  }

  Widget _buildLegal(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Legal & Support'),
        const SizedBox(height: 18),
        _buildLegalContent(context),
      ],
    );
  }

  Widget _buildLegalContent(BuildContext context) {
    final links = [
      {'label': 'Privacy Policy', 'route': '/privacy'},
      {'label': 'Terms of Service', 'route': '/terms'},
      {'label': 'FAQs', 'route': '/faq'},
      {'label': 'Support', 'route': '/support'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: links
          .map((l) => _FooterLink(
                label: l['label']!,
                onTap: () => context.go(l['route']!),
              ))
          .toList(),
    );
  }

  Widget _buildContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Contact Us'),
        const SizedBox(height: 18),
        _buildContactContent(),
      ],
    );
  }

  Widget _buildContactContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _contactItem(Icons.email_rounded, 'roomzyfind@roomzyfind.com'),
        _contactItem(Icons.phone_rounded, '+233 25 721 9035'),
        _contactItem(Icons.location_on_rounded, 'Ghana'),
      ],
    );
  }

  Widget _sectionHeading(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _contactItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 14),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Decorative soft-focus blob — purely visual, IgnorePointer, never
// participates in layout sizing of real content.
// ─────────────────────────────────────────────────────────────
class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Glassmorphic newsletter card — three responsive layouts:
// stacked (very narrow), stacked-but-wide-form (mobile), and
// side-by-side (tablet/desktop). Always flows normally, never
// assumes a fixed height.
// ─────────────────────────────────────────────────────────────
class _NewsletterCard extends StatefulWidget {
  const _NewsletterCard();

  @override
  State<_NewsletterCard> createState() => _NewsletterCardState();
}

class _NewsletterCardState extends State<_NewsletterCard> {
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _handleSubscribe() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }
    // TODO: wire up to actual newsletter signup (Firestore / backend endpoint)
    _emailController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subscribed! Watch your inbox 🎉')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isNarrow = width < 380;
              final isMobile = _Breakpoints.isMobile(width);

              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Stay in the loop',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'New listings, move-in tips, and exclusive deals — '
                    'straight to your inbox.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              );

              final emailField = TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'you@email.com',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.14)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.14)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              );

              final subscribeButton = ElevatedButton(
                onPressed: _handleSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Subscribe',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              );

              // Very narrow phones: everything stacked, full-width button.
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    text,
                    const SizedBox(height: 20),
                    emailField,
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: subscribeButton),
                  ],
                );
              }

              // Mobile: stacked text + inline form.
              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    text,
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: emailField),
                        const SizedBox(width: 10),
                        subscribeButton,
                      ],
                    ),
                  ],
                );
              }

              // Tablet / desktop: side by side.
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(flex: 3, child: text),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 220, child: emailField),
                        const SizedBox(width: 10),
                        subscribeButton,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Collapsible section — used on mobile to keep the footer shorter and
// give it a more "app-like", interactive feel.
// ─────────────────────────────────────────────────────────────
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final Widget child;
  const _CollapsibleSection({required this.title, required this.child});

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _expanded ? 0.5 : 0,
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54, size: 22),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: widget.child,
            ),
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Animated footer link with hover slide + accent dot
// ─────────────────────────────────────────────────────────────
class _FooterLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 180),
            offset: _hovering ? const Offset(0.04, 0) : Offset.zero,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _hovering ? 6 : 0,
                  height: 6,
                  margin: EdgeInsets.only(right: _hovering ? 8 : 0),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Flexible(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: _hovering ? Colors.white : Colors.white54,
                      fontSize: 13,
                      fontWeight: _hovering ? FontWeight.w600 : FontWeight.w400,
                    ),
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

// ─────────────────────────────────────────────────────────────
// Circular social icon button with hover glow
// ─────────────────────────────────────────────────────────────
class _SocialIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SocialIcon({required this.icon, required this.onTap});

  @override
  State<_SocialIcon> createState() => _SocialIconState();
}

class _SocialIconState extends State<_SocialIcon> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          scale: _hovering ? 1.12 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hovering
                  ? AppColors.primary
                  : Colors.white.withOpacity(0.08),
              shape: BoxShape.circle,
              boxShadow: _hovering
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Icon(widget.icon,
                size: 16, color: _hovering ? Colors.white : Colors.white54),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small payment-method chip
// ─────────────────────────────────────────────────────────────
class _PaymentBadge extends StatelessWidget {
  final String label;
  const _PaymentBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom bar — fully responsive:
//   • Desktop/tablet: copyright, "made in Ghana", and back-to-top
//     all sit in one row.
//   • Narrow phones: "made in Ghana" is small and wraps neatly under
//     the copyright line, with back-to-top on its own line if needed.
// Uses Wrap throughout so it can never overflow horizontally.
// ─────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isNarrow = width < 480;

        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: 20,
            horizontal: isNarrow ? 16 : 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _copyrightText(compact: true),
                          const _MadeInGhana(compact: true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _BackToTopButton(),
                    ],
                  )
                : Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: const [
                      _CopyrightGhanaGroup(),
                      _BackToTopButton(),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Copyright + "Made in Ghana" grouped so they travel together in the
/// Wrap on tablet/desktop widths.
class _CopyrightGhanaGroup extends StatelessWidget {
  const _CopyrightGhanaGroup();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: const [
        _CopyrightText(compact: false),
        _MadeInGhana(compact: false),
      ],
    );
  }
}

Widget _copyrightText({required bool compact}) =>
    _CopyrightText(compact: compact);

class _CopyrightText extends StatelessWidget {
  final bool compact;
  const _CopyrightText({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Text(
      '© ${DateTime.now().year} ${AppConstants.appName}. All rights reserved.',
      style: TextStyle(
        color: Colors.white38,
        fontSize: compact ? 11 : 12.5,
      ),
    );
  }
}

/// Small "Made with ❤️ in Ghana" note — deliberately kept compact so it
/// never crowds the back-to-top button or forces awkward wraps.
class _MadeInGhana extends StatelessWidget {
  final bool compact;
  const _MadeInGhana({required this.compact});

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 10.0 : 11.5;
    final iconSize = compact ? 9.0 : 11.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Made with',
            style: TextStyle(color: Colors.white38, fontSize: fontSize)),
        const SizedBox(width: 4),
        Icon(Icons.favorite_rounded, size: iconSize, color: AppColors.primary),
        const SizedBox(width: 4),
        Text('in Ghana',
            style: TextStyle(color: Colors.white38, fontSize: fontSize)),
      ],
    );
  }
}

class _BackToTopButton extends StatefulWidget {
  const _BackToTopButton();

  @override
  State<_BackToTopButton> createState() => _BackToTopButtonState();
}

class _BackToTopButtonState extends State<_BackToTopButton> {
  bool _hovering = false;

  void _scrollToTop() {
    final scrollable = Scrollable.maybeOf(context);
    scrollable?.position.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: _scrollToTop,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                _hovering ? AppColors.primary : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovering
                  ? AppColors.primary
                  : Colors.white.withOpacity(0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_upward_rounded,
                  size: 14, color: _hovering ? Colors.white : Colors.white54),
              const SizedBox(width: 6),
              Text(
                'Back to top',
                style: TextStyle(
                  color: _hovering ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
