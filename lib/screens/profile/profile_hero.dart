// lib/profile/profile_hero.dart
// ─────────────────────────────────────────────────────────────────────────────
// ProfileHero — Advanced gradient SliverAppBar with parallax, shimmer avatar
// ring, animated stats, glassmorphic overlays, and haptic interactions.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile_constants.dart';
import 'profile_widgets.dart';
import 'profile_upload.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  ProfileHero
// ══════════════════════════════════════════════════════════════════════════════
class ProfileHero extends StatefulWidget {
  const ProfileHero({
    super.key,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.role,
    required this.bookings,
    required this.saved,
    required this.rating,
    required this.unread,
    required this.uploading,
    required this.uploadProgress,
    required this.pulseAnim,
    required this.onAvatarTap,
    required this.onNotifTap,
    required this.onShareTap,
    this.scrollController,
    this.accentColor,
    this.coverGradientColors,
    this.joinedDate,
    this.location,
    this.followersCount,
    this.isFollowing = false,
    this.onFollowTap,
    this.onEditTap,
  });

  final String name;
  final String email;
  final String? photoUrl;
  final String role;
  final int bookings;
  final int saved;
  final double rating;
  final int unread;
  final bool uploading;
  final double uploadProgress;
  final Animation<double> pulseAnim;
  final VoidCallback onAvatarTap;
  final VoidCallback onNotifTap;
  final VoidCallback onShareTap;
  final ScrollController? scrollController;
  final Color? accentColor;
  final List<Color>? coverGradientColors;
  final DateTime? joinedDate;
  final String? location;
  final int? followersCount;
  final bool isFollowing;
  final VoidCallback? onFollowTap;
  final VoidCallback? onEditTap;

  @override
  State<ProfileHero> createState() => _ProfileHeroState();
}

class _ProfileHeroState extends State<ProfileHero>
    with TickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;
  late final AnimationController _entranceCtrl;
  late final AnimationController _orbitCtrl;
  late final AnimationController _floatCtrl;

  late final Animation<double> _shimmerAnim;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  late final Animation<double> _statsReveal;
  late final Animation<double> _floatAnim;

  double _parallaxOffset = 0;

  @override
  void initState() {
    super.initState();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _shimmerAnim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOutSine),
    );

    _fadeIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.1, 0.8, curve: Curves.easeOutCubic),
    ));

    _statsReveal = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOutBack),
    );

    _floatAnim = Tween<double>(begin: -4, end: 4).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOutSine),
    );

    widget.scrollController?.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() {
      _parallaxOffset =
          (widget.scrollController!.offset * 0.35).clamp(0.0, 60.0);
    });
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _entranceCtrl.dispose();
    _orbitCtrl.dispose();
    _floatCtrl.dispose();
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  String get _ratingLabel =>
      widget.rating > 0 ? widget.rating.toStringAsFixed(1) : '—';

  ({String label, Color bg, Color border, IconData icon}) get _roleTheme {
    switch (widget.role.toLowerCase()) {
      case 'admin':
        return (
          label: 'Admin',
          bg: const Color(0xFFFFD700).withValues(alpha: .18),
          border: const Color(0xFFFFD700).withValues(alpha: .45),
          icon: Icons.workspace_premium_rounded,
        );
      case 'verified':
        return (
          label: 'Verified',
          bg: kGreen.withValues(alpha: .18),
          border: kGreen.withValues(alpha: .45),
          icon: Icons.verified_rounded,
        );
      default:
        return (
          label: widget.role,
          bg: Colors.white.withValues(alpha: .12),
          border: Colors.white.withValues(alpha: .22),
          icon: Icons.school_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: _HeroShell(
        parallaxOffset: _parallaxOffset,
        gradientColors: widget.coverGradientColors ?? kHeroGradientColors,
        child: AnimatedBuilder(
          animation: Listenable.merge(
              [_entranceCtrl, _shimmerCtrl, _orbitCtrl, _floatCtrl]),
          builder: (context, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Floating orb decorations
                _OrbDecoration(
                  orbitAnim: _orbitCtrl,
                  floatAnim: _floatAnim,
                  accentColor: widget.accentColor ?? kAccent,
                ),

                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeTransition(
                          opacity: _fadeIn,
                          child: _TopBar(
                            unread: widget.unread,
                            onNotifTap: () {
                              HapticFeedback.lightImpact();
                              widget.onNotifTap();
                            },
                            onShareTap: () {
                              HapticFeedback.lightImpact();
                              widget.onShareTap();
                            },
                          ),
                        ),
                        const SizedBox(height: 28),
                        SlideTransition(
                          position: _slideUp,
                          child: FadeTransition(
                            opacity: _fadeIn,
                            child: _AvatarAndName(
                              name: widget.name,
                              email: widget.email,
                              photoUrl: widget.photoUrl,
                              roleTheme: _roleTheme,
                              uploading: widget.uploading,
                              uploadProgress: widget.uploadProgress,
                              pulseAnim: widget.pulseAnim,
                              shimmerAnim: _shimmerAnim,
                              onAvatarTap: () {
                                HapticFeedback.mediumImpact();
                                widget.onAvatarTap();
                              },
                              location: widget.location,
                              joinedDate: widget.joinedDate,
                              isFollowing: widget.isFollowing,
                              onFollowTap: widget.onFollowTap,
                              onEditTap: widget.onEditTap,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        ScaleTransition(
                          scale: _statsReveal,
                          child: FadeTransition(
                            opacity: _statsReveal,
                            child: _StatsRow(
                              bookings: widget.bookings,
                              saved: widget.saved,
                              rating: _ratingLabel,
                              followers: widget.followersCount,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _HeroShell — parallax container with mesh gradient + noise painter
// ══════════════════════════════════════════════════════════════════════════════
class _HeroShell extends StatelessWidget {
  const _HeroShell({
    required this.child,
    required this.parallaxOffset,
    required this.gradientColors,
  });

  final Widget child;
  final double parallaxOffset;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: const [0.0, 0.45, 0.75, 1.0],
          ),
        ),
        child: CustomPaint(
          painter: _MeshNoisePainter(offset: parallaxOffset),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _MeshNoisePainter — dot grid + sweeping arc + noise overlay
// ══════════════════════════════════════════════════════════════════════════════
class _MeshNoisePainter extends CustomPainter {
  const _MeshNoisePainter({this.offset = 0});
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: .055)
      ..style = PaintingStyle.fill;

    // Dot grid with parallax
    const spacing = 28.0;
    final rows = (size.height / spacing).ceil() + 2;
    final cols = (size.width / spacing).ceil() + 2;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(c * spacing, r * spacing - offset),
          1.5,
          dotPaint,
        );
      }
    }

    // Diagonal accent stroke
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = -4; i < 12; i++) {
      final x = i * 80.0;
      canvas.drawLine(
        Offset(x - offset * 0.5, 0),
        Offset(x + size.height * 0.6 - offset * 0.5, size.height),
        strokePaint,
      );
    }

    // Radial glow at top-right
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: .12),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.88, -20),
          radius: size.height * 0.65,
        ),
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);
  }

  @override
  bool shouldRepaint(_MeshNoisePainter old) => old.offset != offset;
}

// ══════════════════════════════════════════════════════════════════════════════
//  _OrbDecoration — floating translucent orbs that orbit slowly
// ══════════════════════════════════════════════════════════════════════════════
class _OrbDecoration extends StatelessWidget {
  const _OrbDecoration({
    required this.orbitAnim,
    required this.floatAnim,
    required this.accentColor,
  });

  final Animation<double> orbitAnim;
  final Animation<double> floatAnim;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([orbitAnim, floatAnim]),
          builder: (_, __) {
            final t = orbitAnim.value * 2 * math.pi;
            return Stack(
              children: [
                // Large background orb
                Positioned(
                  right: -60 + math.sin(t * 0.4) * 18,
                  top: -40 + floatAnim.value,
                  child: _Orb(
                    size: 200,
                    color: accentColor.withValues(alpha: .12),
                    blur: 40,
                  ),
                ),
                // Medium orb
                Positioned(
                  left: -30 + math.cos(t * 0.3) * 12,
                  bottom: 60 + math.sin(t * 0.5) * 8,
                  child: _Orb(
                    size: 130,
                    color: Colors.white.withValues(alpha: .07),
                    blur: 30,
                  ),
                ),
                // Small accent orb
                Positioned(
                  right: 40 + math.cos(t * 0.6) * 10,
                  bottom: 80 + math.sin(t * 0.7) * 6,
                  child: _Orb(
                    size: 60,
                    color: accentColor.withValues(alpha: .18),
                    blur: 20,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({
    required this.size,
    required this.color,
    required this.blur,
  });

  final double size;
  final Color color;
  final double blur;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: blur, spreadRadius: blur * 0.3)
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  _TopBar — back + notification badge + share + optional edit
// ══════════════════════════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.unread,
    required this.onNotifTap,
    required this.onShareTap,
  });

  final int unread;
  final VoidCallback onNotifTap;
  final VoidCallback onShareTap;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _GlassButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.maybePop(context);
            },
          ),
          const Spacer(),
          _NotifButton(unread: unread, onTap: onNotifTap),
          const SizedBox(width: 10),
          _GlassButton(icon: Icons.ios_share_rounded, onTap: onShareTap),
        ],
      );
}

class _GlassButton extends StatefulWidget {
  const _GlassButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<_GlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1, end: 0.88)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _pressCtrl.forward(),
        onTapUp: (_) async {
          await _pressCtrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _pressCtrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .22),
                    width: 1,
                  ),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      );
}

class _NotifButton extends StatelessWidget {
  const _NotifButton({required this.unread, required this.onTap});
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          _GlassButton(icon: Icons.notifications_none_rounded, onTap: onTap),
          if (unread > 0)
            Positioned(
              top: -5,
              right: -5,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 20, minHeight: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kAccent, kAccent.withValues(alpha: .75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: kAccent.withValues(alpha: .55),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  _AvatarAndName — shimmer ring + name + meta + action buttons
// ══════════════════════════════════════════════════════════════════════════════
class _AvatarAndName extends StatelessWidget {
  const _AvatarAndName({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.roleTheme,
    required this.uploading,
    required this.uploadProgress,
    required this.pulseAnim,
    required this.shimmerAnim,
    required this.onAvatarTap,
    this.location,
    this.joinedDate,
    this.isFollowing = false,
    this.onFollowTap,
    this.onEditTap,
  });

  final String name;
  final String email;
  final String? photoUrl;
  final ({String label, Color bg, Color border, IconData icon}) roleTheme;
  final bool uploading;
  final double uploadProgress;
  final Animation<double> pulseAnim;
  final Animation<double> shimmerAnim;
  final VoidCallback onAvatarTap;
  final String? location;
  final DateTime? joinedDate;
  final bool isFollowing;
  final VoidCallback? onFollowTap;
  final VoidCallback? onEditTap;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShimmerAvatar(
            photoUrl: photoUrl,
            name: name,
            uploading: uploading,
            uploadProgress: uploadProgress,
            pulseAnim: pulseAnim,
            shimmerAnim: shimmerAnim,
            onTap: onAvatarTap,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name with verified tick if applicable
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (roleTheme.label == 'Verified') ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified_rounded, color: kGreen, size: 18),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: .65),
                    letterSpacing: 0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Role pill
                _RolePill(theme: roleTheme),
                const SizedBox(height: 10),

                // Meta row
                if (location != null || joinedDate != null)
                  _MetaRow(location: location, joinedDate: joinedDate),

                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    if (onEditTap != null)
                      _MiniActionButton(
                        label: 'Edit',
                        icon: Icons.edit_rounded,
                        onTap: onEditTap!,
                        filled: true,
                      ),
                    if (onFollowTap != null) ...[
                      if (onEditTap != null) const SizedBox(width: 8),
                      _MiniActionButton(
                        label: isFollowing ? 'Following' : 'Follow',
                        icon: isFollowing
                            ? Icons.check_rounded
                            : Icons.person_add_rounded,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          onFollowTap!();
                        },
                        filled: !isFollowing,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      );
}

class _ShimmerAvatar extends StatelessWidget {
  const _ShimmerAvatar({
    required this.photoUrl,
    required this.name,
    required this.uploading,
    required this.uploadProgress,
    required this.pulseAnim,
    required this.shimmerAnim,
    required this.onTap,
  });

  final String? photoUrl;
  final String name;
  final bool uploading;
  final double uploadProgress;
  final Animation<double> pulseAnim;
  final Animation<double> shimmerAnim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Animated shimmer ring
            AnimatedBuilder(
              animation: shimmerAnim,
              builder: (_, __) => CustomPaint(
                painter: _ShimmerRingPainter(
                  progress: shimmerAnim.value,
                  accent: kAccent,
                ),
                child: const SizedBox(width: 96, height: 96),
              ),
            ),
            // Avatar
            KAvatar(
              photoUrl: photoUrl,
              name: name,
              size: 82,
              unread: 0,
              uploading: uploading,
              uploadProgress: uploadProgress,
              pulseAnimation: pulseAnim,
              onTap: onTap,
            ),
            // Upload overlay
            if (uploading)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(41),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .35),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(uploadProgress * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            SizedBox(
                              width: 40,
                              child: LinearProgressIndicator(
                                value: uploadProgress,
                                backgroundColor: Colors.white24,
                                valueColor: AlwaysStoppedAnimation(kAccent),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Camera badge
            if (!uploading)
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: kAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: kAccent.withValues(alpha: .5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ShimmerRingPainter extends CustomPainter {
  const _ShimmerRingPainter({required this.progress, required this.accent});
  final double progress; // -2 to 2
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Base ring
    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: .15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, basePaint);

    // Shimmer arc
    final shimmerPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          accent.withValues(alpha: .6),
          Colors.white.withValues(alpha: .9),
          accent.withValues(alpha: .6),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        transform: GradientRotation(progress * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, shimmerPaint);
  }

  @override
  bool shouldRepaint(_ShimmerRingPainter old) => old.progress != progress;
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.theme});
  final ({String label, Color bg, Color border, IconData icon}) theme;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(theme.icon, size: 12, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  theme.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({this.location, this.joinedDate});
  final String? location;
  final DateTime? joinedDate;

  String _formatJoined(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          if (location != null)
            _MetaChip(
              icon: Icons.location_on_rounded,
              label: location!,
            ),
          if (joinedDate != null)
            _MetaChip(
              icon: Icons.calendar_today_rounded,
              label: 'Joined ${_formatJoined(joinedDate!)}',
            ),
        ],
      );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white.withValues(alpha: .55)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: .6),
              letterSpacing: 0.1,
            ),
          ),
        ],
      );
}

class _MiniActionButton extends StatefulWidget {
  const _MiniActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  State<_MiniActionButton> createState() => _MiniActionButtonState();
}

class _MiniActionButtonState extends State<_MiniActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.92)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _pressCtrl.forward(),
        onTapUp: (_) async {
          await _pressCtrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _pressCtrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: widget.filled
                      ? kAccent.withValues(alpha: .85)
                      : Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.filled
                        ? kAccent.withValues(alpha: .4)
                        : Colors.white.withValues(alpha: .22),
                    width: 1,
                  ),
                  boxShadow: widget.filled
                      ? [
                          BoxShadow(
                            color: kAccent.withValues(alpha: .35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  _StatsRow — animated counter tiles with glassmorphic cards
// ══════════════════════════════════════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.bookings,
    required this.saved,
    required this.rating,
    this.followers,
  });

  final int bookings;
  final int saved;
  final String rating;
  final int? followers;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (value: '$bookings', label: 'Bookings', icon: Icons.bookmark_rounded),
      (value: '$saved', label: 'Saved', icon: Icons.favorite_rounded),
      (value: rating, label: 'Rating', icon: Icons.star_rounded),
      if (followers != null)
        (
          value: _formatFollowers(followers!),
          label: 'Followers',
          icon: Icons.people_rounded
        ),
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(22),
        topRight: Radius.circular(22),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
            ),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .18)),
              left: BorderSide(color: Colors.white.withValues(alpha: .12)),
              right: BorderSide(color: Colors.white.withValues(alpha: .12)),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  Expanded(
                    child: _AnimatedStatTile(
                      value: stats[i].value,
                      label: stats[i].label,
                      icon: stats[i].icon,
                      delay: Duration(milliseconds: 100 * i),
                    ),
                  ),
                  if (i < stats.length - 1)
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      color: Colors.white.withValues(alpha: .14),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatFollowers(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _AnimatedStatTile extends StatefulWidget {
  const _AnimatedStatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.delay,
  });

  final String value;
  final String label;
  final IconData icon;
  final Duration delay;

  @override
  State<_AnimatedStatTile> createState() => _AnimatedStatTileState();
}

class _AnimatedStatTileState extends State<_AnimatedStatTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeScale;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeScale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(widget.delay, () {
      if (mounted) {
        _ctrl.forward();
        setState(() => _started = true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _fadeScale,
        child: FadeTransition(
          opacity: _fadeScale,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon,
                    size: 15, color: Colors.white.withValues(alpha: .55)),
                const SizedBox(height: 5),
                Text(
                  widget.value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: .55),
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
