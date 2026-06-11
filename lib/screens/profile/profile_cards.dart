// lib/profile/profile_cards.dart
// ─────────────────────────────────────────────────────────────────────────────
// ProfileCompletionCard  — animated ring + missing-field checklist
// ProfileLoyaltyCard     — shimmer gradient card with tier + progress bar
// ProfileQuickActions    — 2×2 tappable grid (bookings, saved, payments, support)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'profile_constants.dart';
import 'profile_upload.dart'; // RingPainter
import 'profile_widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  ProfileCompletionCard
// ══════════════════════════════════════════════════════════════════════════════
class ProfileCompletionCard extends StatelessWidget {
  const ProfileCompletionCard({
    super.key,
    required this.data,
    required this.email,
    required this.progressAnim,
    required this.completionTarget,
    required this.onEditTap,
  });

  final Map<String, dynamic> data;
  final String email;
  final Animation<double> progressAnim;
  final double completionTarget;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    // Fix #4a: compute once in build, not inside AnimatedBuilder.
    // completionCount and kCompletionLabels.length are pure/cheap but there's
    // no reason to recompute them on every animation tick.
    final count = completionCount(data, email);
    final total = kCompletionLabels.length;
    final pct = ((count / total) * 100).round();
    final isDone = count == total;

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            children: [
              // Animated ring — only the painter rebuilds on tick
              SizedBox(
                width: 72,
                height: 72,
                child: AnimatedBuilder(
                  animation: progressAnim,
                  builder: (_, __) {
                    final animated =
                        (progressAnim.value * completionTarget).clamp(0.0, 1.0);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          painter: RingPainter(
                            progress: animated,
                            foreground: isDone ? kGreen : kTeal,
                            background: kBorder,
                          ),
                          child: const SizedBox.expand(),
                        ),
                        // Fix #4b: these Text widgets don't depend on the
                        // animation value — pull them out of the builder so
                        // they don't rebuild on every tick.
                        _RingLabel(pct: pct, count: count, total: total),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),

              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDone ? 'Profile Complete! 🎉' : 'Complete Your Profile',
                      style: KText.labelLg,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDone
                          ? "You're all set — enjoy full access."
                          : 'Fill in the missing fields to unlock all features.',
                      style: KText.bodyXS,
                    ),
                    const SizedBox(height: 10),
                    KButton(
                      label: isDone ? 'View Profile' : 'Complete Now',
                      onTap: onEditTap,
                      small: true,
                      icon: isDone
                          ? Icons.check_circle_outline_rounded
                          : Icons.edit_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Missing fields checklist ─────────────────────────────────────
          if (!isDone) ...[
            const SizedBox(height: 20),
            const Divider(height: 1, color: kBorder),
            const SizedBox(height: 16),
            _MissingFieldsList(data: data, email: email),
          ],
        ],
      ),
    );
  }
}

// Fix #4b: static label widget — zero rebuilds from the animation ticker.
class _RingLabel extends StatelessWidget {
  const _RingLabel({
    required this.pct,
    required this.count,
    required this.total,
  });

  final int pct;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$pct%',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: kTextPrimary,
            ),
          ),
          Text('$count/$total', style: KText.caption),
        ],
      );
}

// ── Missing fields checklist ────────────────────────────────────────────────
class _MissingFieldsList extends StatelessWidget {
  const _MissingFieldsList({
    required this.data,
    required this.email,
  });

  final Map<String, dynamic> data;
  final String email;

  // Fix #4c: use a method rather than a getter so the linter doesn't
  // flag a potentially-expensive getter on an immutable widget.
  List<bool> _filled() => [
        (data['email'] as String? ?? email).isNotEmpty,
        (data['phone'] as String? ?? '').isNotEmpty,
        (data['photoUrl'] as String? ?? '').isNotEmpty,
        (data['studentId'] as String? ?? '').isNotEmpty,
        (data['emergencyContact'] as String? ?? '').isNotEmpty,
        (data['university'] as String? ?? '').isNotEmpty,
      ];

  static const _icons = [
    Icons.email_outlined,
    Icons.phone_outlined,
    Icons.photo_camera_outlined,
    Icons.badge_outlined,
    Icons.emergency_outlined,
    Icons.school_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final filled = _filled();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(kCompletionLabels.length, (i) {
        final done = filled[i];
        return Opacity(
          opacity: done ? .45 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: done ? kGreenBg : kTealLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: done
                    ? kGreen.withValues(alpha: .3)
                    : kTeal.withValues(alpha: .3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.check_circle_rounded : _icons[i],
                  size: 14,
                  color: done ? kGreen : kTeal,
                ),
                const SizedBox(width: 5),
                Text(
                  kCompletionLabels[i],
                  style: KText.labelXS.copyWith(
                    color: done ? kGreen : kTeal,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ProfileLoyaltyCard
// ══════════════════════════════════════════════════════════════════════════════
class ProfileLoyaltyCard extends StatelessWidget {
  const ProfileLoyaltyCard({
    super.key,
    required this.points,
    required this.shimmerAnim,
  });

  final int points;
  final Animation<double> shimmerAnim;

  // Fix #4d: pure helpers moved to static so they can't accidentally
  // capture instance state and are trivially unit-testable.
  static LoyaltyTier? _nextTier(LoyaltyTier current) {
    final idx = kTiers.indexOf(current);
    return (idx >= 0 && idx < kTiers.length - 1) ? kTiers[idx + 1] : null;
  }

  static double _progress(LoyaltyTier tier, int pts) {
    if (tier.min == tier.max) return 1.0; // Platinum — already maxed
    return ((pts - tier.min) / (tier.max - tier.min)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Fix #4e: compute tier/progress once in build, not inside
    // _ShimmerBar's AnimatedBuilder (which fires on every shimmer tick).
    final tier = tierFor(points);
    final nextTier = _nextTier(tier);
    final progress = _progress(tier, points);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: kLoyaltyGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: kTealDark.withValues(alpha: .35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: tier badge + points ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loyalty Rewards', style: KText.onDarkCaption),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: tier.color.withValues(alpha: .25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: tier.color.withValues(alpha: .5),
                          ),
                        ),
                        child: Text(
                          tier.label,
                          style: KText.labelSm.copyWith(color: tier.color),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(tier.label, style: KText.onDarkSub),
                    ],
                  ),
                ],
              ),
              // Points counter
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$points', style: KText.onDarkValue),
                  Text('points', style: KText.onDarkCaption),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Shimmer progress bar ──────────────────────────────────────
          _ShimmerBar(
            progress: progress,
            shimmerAnim: shimmerAnim,
          ),

          const SizedBox(height: 10),

          // ── Labels: current tier ↔ next tier ─────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tier.label,
                style: KText.onDarkCaption.copyWith(fontSize: 10),
              ),
              if (nextTier != null)
                Text(
                  '${nextTier.min - points} pts to ${nextTier.label}',
                  style: KText.onDarkCaption,
                )
              else
                Text('🏆 Max tier reached!', style: KText.onDarkCaption),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shimmer progress bar ────────────────────────────────────────────────────
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({
    required this.progress,
    required this.shimmerAnim,
  });

  final double progress;
  final Animation<double> shimmerAnim;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: shimmerAnim,
        // Fix #4f: pass the static track as the child so it isn't rebuilt
        // on every shimmer tick — only the fill gradient needs to repaint.
        child: Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        builder: (_, track) => LayoutBuilder(
          builder: (_, constraints) {
            final fillWidth = constraints.maxWidth * progress;
            final sv = shimmerAnim.value;

            return Stack(
              children: [
                track!, // static track — no rebuild
                Container(
                  height: 8,
                  width: fillWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: const [kGold, Colors.white, kGold],
                      stops: [
                        (sv - .35).clamp(0.0, 1.0),
                        sv.clamp(0.0, 1.0),
                        (sv + .35).clamp(0.0, 1.0),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  ProfileQuickActions  — 2 × 2 grid
// ══════════════════════════════════════════════════════════════════════════════
class ProfileQuickActions extends StatelessWidget {
  const ProfileQuickActions({super.key, required this.onTap});

  final void Function(String route) onTap;

  static const _actions = [
    _Action(
      icon: Icons.calendar_month_rounded,
      iconColor: kBlue,
      iconBg: kBlueBg,
      label: 'My Bookings',
      subtitle: 'View & manage',
      route: KRoutes.bookings,
    ),
    _Action(
      icon: Icons.favorite_rounded,
      iconColor: kAccent,
      iconBg: kAccentBg,
      label: 'Saved',
      subtitle: 'Wishlist items',
      route: KRoutes.saved,
    ),
    _Action(
      icon: Icons.account_balance_wallet_rounded,
      iconColor: kGreen,
      iconBg: kGreenBg,
      label: 'Payments',
      subtitle: 'History & methods',
      route: KRoutes.payments,
    ),
    _Action(
      icon: Icons.headset_mic_rounded,
      iconColor: kPurple,
      iconBg: kPurpleBg,
      label: 'Support',
      subtitle: 'Get help',
      route: KRoutes.support,
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KSectionTitle('Quick Actions'),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.35,
            children: _actions
                .map((a) => KQuickActionCard(
                      icon: a.icon,
                      iconColor: a.iconColor,
                      iconBackground: a.iconBg,
                      label: a.label,
                      subtitle: a.subtitle,
                      onTap: () => onTap(a.route),
                    ))
                .toList(),
          ),
        ],
      );
}

// Data class for a quick-action entry
class _Action {
  const _Action({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String subtitle;
  final String route;
}
