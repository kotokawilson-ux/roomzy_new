import 'package:cloud_firestore/cloud_firestore.dart';
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
                    const SizedBox(height: 56),
                    const _HowItWorksBlock(),
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
                    const SizedBox(height: 72),
                    const _HowItWorksBlock(),
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
        'https://i.ibb.co/fYBrypcy/Screenshot-20260514-084851.jpg',
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

  // ── Stats ──────────────────────────────────────────────────────────────
  // Reads settings/site_stats.stats (an array of 4 {number,label} maps) live
  // from Firestore so numbers set in the admin panel's "Site Stats" card
  // show up here immediately, with no redeploy. Falls back to the original
  // hardcoded values while loading or if the doc/field is missing/malformed,
  // so the layout never flashes empty or breaks shape.
  static const _defaultStats = [
    {'number': '120', 'label': 'Rooms Available'},
    {'number': '75', 'label': 'Happy Residents'},
    {'number': '5', 'label': 'Years of Service'},
    {'number': '20', 'label': 'Staff Members'},
  ];

  Widget _buildStats(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('site_stats')
          .snapshots(),
      builder: (context, snapshot) {
        final raw = snapshot.data?.data()?['stats'];
        final stats = (raw is List && raw.length == 4)
            ? raw.cast<Map<String, dynamic>>()
            : _defaultStats;
        return _StatsGrid(stats: stats);
      },
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<Map<String, dynamic>> stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      stat['number'].toString(),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stat['label'].toString(),
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

// ---------------------------------------------------------------------------
// "How It Works" block — walks a visitor through the journey from
// searching a hostel to securing their spot. Sits directly after the
// stats row inside AboutSection.
// ---------------------------------------------------------------------------

class _HowItWorksBlock extends StatelessWidget {
  const _HowItWorksBlock();

  static final List<_StepData> _steps = [
    _StepData(
      icon: Icons.search_rounded,
      title: 'Search Hostels',
      desc:
          'Browse verified hostels near your school, filter by price, room type, and amenities to find your perfect match.',
    ),
    _StepData(
      icon: Icons.bookmark_add_rounded,
      title: 'Pre-Book Your Room',
      desc:
          'Found the one? Reserve it instantly with a pre-booking so no one else takes your spot while you decide.',
    ),
    _StepData(
      icon: Icons.payments_rounded,
      title: 'Confirm & Pay Securely',
      desc:
          'Complete your booking with a trusted local payment option. Every transaction is encrypted and protected.',
    ),
    _StepData(
      icon: Icons.verified_rounded,
      title: 'Secure Your Spot',
      desc:
          'Receive instant confirmation and booking details. Your room is officially yours — no back and forth needed.',
    ),
    _StepData(
      icon: Icons.home_work_rounded,
      title: 'Move In & Settle',
      desc:
          'Show up on move-in day with everything sorted. Reach 24/7 support anytime you need a hand.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;
        final isTablet =
            constraints.maxWidth >= 800 && constraints.maxWidth < 1100;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 48),
            isMobile
                ? _buildVerticalSteps()
                : _buildHorizontalSteps(compact: isTablet),
          ],
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'THE PROCESS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'How RoomzyFind Works',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 520,
          child: Text(
            'From your first search to moving in — here\'s the whole journey, made simple.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalSteps() {
    return Column(
      children: List.generate(_steps.length, (i) {
        final isLast = i == _steps.length - 1;
        return _AnimatedStep(
          index: i,
          step: _steps[i],
          isLast: isLast,
          axis: Axis.vertical,
        );
      }),
    );
  }

  Widget _buildHorizontalSteps({required bool compact}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_steps.length, (i) {
          final isLast = i == _steps.length - 1;
          return Expanded(
            child: _AnimatedStep(
              index: i,
              step: _steps[i],
              isLast: isLast,
              axis: Axis.horizontal,
              compact: compact,
            ),
          );
        }),
      ),
    );
  }
}

class _StepData {
  final IconData icon;
  final String title;
  final String desc;

  const _StepData(
      {required this.icon, required this.title, required this.desc});
}

/// A single step that fades + slides into place on entrance (staggered by
/// [index]) and gently lifts / glows on hover for pointer devices.
class _AnimatedStep extends StatefulWidget {
  final int index;
  final _StepData step;
  final bool isLast;
  final Axis axis;
  final bool compact;

  const _AnimatedStep({
    required this.index,
    required this.step,
    required this.isLast,
    required this.axis,
    this.compact = false,
  });

  @override
  State<_AnimatedStep> createState() => _AnimatedStepState();
}

class _AnimatedStepState extends State<_AnimatedStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: widget.axis == Axis.vertical
          ? const Offset(0, 0.15)
          : const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Staggered entrance — each step waits its turn before animating in.
    Future.delayed(Duration(milliseconds: 120 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconCircle = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _hovering ? AppColors.primary : AppColors.primaryLight,
            shape: BoxShape.circle,
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                widget.step.icon,
                color: _hovering ? Colors.white : AppColors.primary,
                size: 28,
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 1.4),
                  ),
                  child: Text(
                    '${widget.index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final textBlock = Column(
      crossAxisAlignment: widget.axis == Axis.vertical
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          widget.step.title,
          textAlign:
              widget.axis == Axis.vertical ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.step.desc,
          textAlign:
              widget.axis == Axis.vertical ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
          ),
        ),
      ],
    );

    final content = widget.axis == Axis.vertical
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  iconCircle,
                  if (!widget.isLast)
                    Container(
                      width: 2,
                      height: 46,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.primary.withOpacity(0.4),
                            AppColors.primary.withOpacity(0.05),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 32),
                  child: textBlock,
                ),
              ),
            ],
          )
        : Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 8 : 14,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: widget.index == 0
                          ? const SizedBox()
                          : Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withOpacity(0.05),
                                    AppColors.primary.withOpacity(0.4),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    iconCircle,
                    Expanded(
                      child: widget.isLast
                          ? const SizedBox()
                          : Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withOpacity(0.4),
                                    AppColors.primary.withOpacity(0.05),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                textBlock,
              ],
            ),
          );

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: content,
      ),
    );
  }
}
