// lib/profile/profile_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets — redesigned: spring physics, glassmorphic surfaces,
// shimmer skeletons, token-driven theming, micro-interaction polish.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens
// ─────────────────────────────────────────────────────────────────────────────
const _kRadius = 18.0;
const _kRadiusSm = 12.0;
const _kRadiusXs = 8.0;
const _kDuration100 = Duration(milliseconds: 100);
const _kDuration200 = Duration(milliseconds: 200);
const _kDuration300 = Duration(milliseconds: 300);

BoxDecoration _surfaceDecoration({
  Color? borderColor,
  double radius = _kRadius,
  Color? background,
}) =>
    BoxDecoration(
      color: background ?? Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? const Color(0xFFEDF0F4),
        width: 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x06000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );

// ══════════════════════════════════════════════════════════════════════════════
//  KCard — floating surface card
// ══════════════════════════════════════════════════════════════════════════════
class KCard extends StatelessWidget {
  const KCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(20),
        decoration: _surfaceDecoration(borderColor: borderColor),
        child: child,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KRowDivider — hairline divider
// ══════════════════════════════════════════════════════════════════════════════
class KRowDivider extends StatelessWidget {
  const KRowDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 72,
        color: Color(0xFFF1F4F8),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSectionTitle
// ══════════════════════════════════════════════════════════════════════════════
class KSectionTitle extends StatelessWidget {
  const KSectionTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: KText.sectionTitle,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KButton — spring-press button with loading state + destructive variant
// ══════════════════════════════════════════════════════════════════════════════
class KButton extends StatefulWidget {
  const KButton({
    super.key,
    required this.label,
    required this.onTap,
    this.small = false,
    this.loading = false,
    this.destructive = false,
    this.outlined = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool small;
  final bool loading;
  final bool destructive;
  final bool outlined;
  final IconData? icon;

  @override
  State<KButton> createState() => _KButtonState();
}

class _KButtonState extends State<KButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 250),
      lowerBound: 0,
      upperBound: 1,
    );
    _scale = Tween(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || widget.onTap == null;
    final baseColor = widget.destructive ? kRed : kTeal;

    Color bg;
    Color fg;
    Border? border;

    if (widget.outlined) {
      bg = Colors.transparent;
      fg = baseColor;
      border = Border.all(color: baseColor.withValues(alpha: .4), width: 1.5);
    } else {
      bg = disabled ? baseColor.withValues(alpha: .45) : baseColor;
      fg = Colors.white;
      border = null;
    }

    return GestureDetector(
      onTapDown: disabled ? null : (_) => _ctrl.forward(),
      onTapUp: disabled
          ? null
          : (_) {
              _ctrl.reverse();
              HapticFeedback.lightImpact();
              widget.onTap?.call();
            },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: _kDuration200,
          width: widget.small ? null : double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: widget.small ? 11 : 15,
            horizontal: widget.small ? 24 : 0,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_kRadius),
            border: border,
          ),
          child: widget.loading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 17, color: fg),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: widget.small ? 13 : 15,
                        color: fg,
                        letterSpacing: .2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KToggle — pill switch with spring thumb
// ══════════════════════════════════════════════════════════════════════════════
class KToggle extends StatefulWidget {
  const KToggle(this.value, this.onChanged, {super.key});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<KToggle> createState() => _KToggleState();
}

class _KToggleState extends State<KToggle> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _thumb;
  late final Animation<Color?> _track;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _kDuration300,
      value: widget.value ? 1 : 0,
    );
    _thumb = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _track = ColorTween(
      begin: const Color(0xFFD4DCE8),
      end: kTeal,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(KToggle old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      widget.value ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.value ? 'Enabled' : 'Disabled',
        toggled: widget.value,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onChanged(!widget.value);
          },
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Container(
              width: 50,
              height: 28,
              decoration: BoxDecoration(
                color: _track.value,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Align(
                  alignment: Alignment.lerp(
                    Alignment.centerLeft,
                    Alignment.centerRight,
                    _thumb.value,
                  )!,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KArrow
// ══════════════════════════════════════════════════════════════════════════════
class KArrow extends StatelessWidget {
  const KArrow({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6FA),
          borderRadius: BorderRadius.circular(_kRadiusSm),
        ),
        child: const Icon(
          Icons.chevron_right_rounded,
          color: kTextTertiary,
          size: 17,
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KStatusPill — icon-prefixed status chip with shimmer on pending
// ══════════════════════════════════════════════════════════════════════════════
enum KPillStatus { verified, pending, danger }

class KStatusPill extends StatefulWidget {
  const KStatusPill(this.label, {super.key, required this.status});
  const KStatusPill.ok(this.label, {super.key, required bool ok})
      : status = ok ? KPillStatus.verified : KPillStatus.pending;

  final String label;
  final KPillStatus status;

  @override
  State<KStatusPill> createState() => _KStatusPillState();
}

class _KStatusPillState extends State<KStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.status == KPillStatus.pending) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (widget.status) {
      KPillStatus.verified => (
          const Color(0xFFE6F9F4),
          kGreen,
          Icons.verified_rounded,
        ),
      KPillStatus.pending => (
          const Color(0xFFFFF3E0),
          const Color(0xFFE65100),
          Icons.schedule_rounded,
        ),
      KPillStatus.danger => (
          const Color(0xFFFFEBEE),
          kRed,
          Icons.report_rounded,
        ),
    };

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: .15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
          Text(
            widget.label,
            style: KText.labelXS.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );

    if (widget.status != KPillStatus.pending) return pill;

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, child) => ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .35),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, .5, 1],
          begin: Alignment(-2 + _shimmer.value * 4, 0),
          end: Alignment(-1 + _shimmer.value * 4, 0),
        ).createShader(bounds),
        blendMode: BlendMode.srcATop,
        child: child,
      ),
      child: pill,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KPill — generic role / category badge
// ══════════════════════════════════════════════════════════════════════════════
class KPill extends StatelessWidget {
  const KPill(
    this.label, {
    super.key,
    required this.background,
    required this.textColor,
    this.icon,
  });

  final String label;
  final Color background;
  final Color textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: textColor.withValues(alpha: .12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: textColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: KText.labelSm.copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KNavButton — frosted circular nav button
// ══════════════════════════════════════════════════════════════════════════════
class KNavButton extends StatefulWidget {
  const KNavButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<KNavButton> createState() => _KNavButtonState();
}

class _KNavButtonState extends State<KNavButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: _kDuration100,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _pressed
                  ? Colors.white.withValues(alpha: .3)
                  : Colors.white.withValues(alpha: .18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .3),
              ),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 18),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KStatWidget — animated counter stat
// ══════════════════════════════════════════════════════════════════════════════
class KStatWidget extends StatelessWidget {
  const KStatWidget(this.value, this.label, {super.key, this.onDark = false});

  final String value;
  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (onDark) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: KText.onDarkValue),
          const SizedBox(height: 2),
          Text(label, style: KText.onDarkCaption),
        ],
      );
    }
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kTextPrimary,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(label, style: KText.caption),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KDivider — vertical divider for stat rows
// ══════════════════════════════════════════════════════════════════════════════
class KDivider extends StatelessWidget {
  const KDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 0.5,
        height: 32,
        color: kBorder,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KAvatar — with pulse ring, inline upload progress, unread badge, camera tap
// ══════════════════════════════════════════════════════════════════════════════
class KAvatar extends StatelessWidget {
  const KAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.size,
    required this.unread,
    required this.uploading,
    required this.uploadProgress,
    required this.pulseAnimation,
    required this.onTap,
  });

  final String? photoUrl;
  final String name;
  final double size;
  final int unread;
  final bool uploading;
  final double uploadProgress;
  final Animation<double> pulseAnimation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Pulse ring
            Positioned.fill(
              child: AnimatedBuilder(
                animation: pulseAnimation,
                builder: (_, __) => Transform.scale(
                  scale: pulseAnimation.value,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kTeal.withValues(alpha: .30),
                          blurRadius: 28,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Avatar circle
            Semantics(
              label: 'Profile photo, tap to change',
              button: true,
              child: GestureDetector(
                onTap: uploading ? null : onTap,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [kAccent, kTeal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: kTeal.withValues(alpha: .20),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: photoUrl?.isNotEmpty == true
                        ? Image.network(
                            photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _initials(initial),
                          )
                        : _initials(initial),
                  ),
                ),
              ),
            ),

            // Unread badge
            if (unread > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(
                      color: kAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Camera button — spring press
            Positioned(
              bottom: 2,
              right: 2,
              child: _CameraButton(uploading: uploading, onTap: onTap),
            ),
          ],
        ),

        // Upload progress bar
        AnimatedSize(
          duration: _kDuration300,
          curve: Curves.easeOut,
          child: uploading
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: size,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: uploadProgress,
                            minHeight: 4,
                            backgroundColor: kBorder,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(kTeal),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Uploading… ${(uploadProgress * 100).round()}%',
                          style: KText.caption,
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _initials(String letter) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A6B5A), kTealDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
              fontSize: size * .36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
}

class _CameraButton extends StatefulWidget {
  const _CameraButton({required this.uploading, required this.onTap});
  final bool uploading;
  final VoidCallback onTap;

  @override
  State<_CameraButton> createState() => _CameraButtonState();
}

class _CameraButtonState extends State<_CameraButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: _kDuration200,
    );
    _scale = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: widget.uploading ? null : (_) => _ctrl.forward(),
        onTapUp: widget.uploading
            ? null
            : (_) {
                _ctrl.reverse();
                HapticFeedback.mediumImpact();
                widget.onTap();
              },
        onTapCancel: () => _ctrl.reverse(),
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: widget.uploading ? kTextTertiary : kAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: kAccent.withValues(alpha: .35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KInputField — focus-animated text field
// ══════════════════════════════════════════════════════════════════════════════
class KInputField extends StatefulWidget {
  const KInputField(
    this.controller,
    this.label,
    this.icon, {
    super.key,
    this.keyboardType,
    this.obscureText = false,
    this.onChanged,
    this.errorText,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final Widget? suffixIcon;

  @override
  State<KInputField> createState() => _KInputFieldState();
}

class _KInputFieldState extends State<KInputField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AnimatedContainer(
          duration: _kDuration200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kRadius),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: kTeal.withValues(alpha: .12),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: TextField(
            focusNode: _focus,
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            onChanged: widget.onChanged,
            style: KText.body,
            decoration: InputDecoration(
              labelText: widget.label,
              labelStyle: KText.bodyS,
              errorText: widget.errorText,
              prefixIcon: AnimatedContainer(
                duration: _kDuration200,
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: _focused ? kTeal : kTextSecond,
                ),
              ),
              suffixIcon: widget.suffixIcon,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_kRadius),
                borderSide: const BorderSide(color: Color(0xFFE8EDF3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_kRadius),
                borderSide: const BorderSide(color: Color(0xFFE8EDF3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_kRadius),
                borderSide: const BorderSide(color: kTeal, width: 1.8),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_kRadius),
                borderSide: BorderSide(color: kRed.withValues(alpha: .7)),
              ),
              filled: true,
              fillColor: _focused ? Colors.white : const Color(0xFFF7F9FC),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSheetRow — tappable bottom-sheet row
// ══════════════════════════════════════════════════════════════════════════════
class KSheetRow extends StatefulWidget {
  const KSheetRow(this.icon, this.color, this.label, this.onTap, {super.key});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  State<KSheetRow> createState() => _KSheetRowState();
}

class _KSheetRowState extends State<KSheetRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: _kDuration100,
            decoration: BoxDecoration(
              color: _pressed
                  ? widget.color.withValues(alpha: .05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(_kRadiusSm),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(_kRadiusSm),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(width: 14),
                Text(widget.label, style: KText.labelLg),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: widget.color.withValues(alpha: .5),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSettingsRow — icon + label + subtitle + trailing + badge dot
// ══════════════════════════════════════════════════════════════════════════════
class KSettingsRow extends StatefulWidget {
  const KSettingsRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    this.labelColor,
    this.subtitle,
    this.trailing,
    this.badge = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color? labelColor;
  final String? subtitle;
  final Widget? trailing;
  final bool badge;
  final VoidCallback? onTap;

  @override
  State<KSettingsRow> createState() => _KSettingsRowState();
}

class _KSettingsRowState extends State<KSettingsRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
      reverseDuration: _kDuration200,
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trailingWidget =
        widget.trailing ?? (widget.onTap != null ? const KArrow() : null);

    return Semantics(
      button: widget.onTap != null,
      label: widget.label,
      hint: widget.subtitle,
      child: GestureDetector(
        onTapDown: widget.onTap == null ? null : (_) => _ctrl.forward(),
        onTapUp: widget.onTap == null
            ? null
            : (_) {
                _ctrl.reverse();
                HapticFeedback.selectionClick();
                widget.onTap?.call();
              },
        onTapCancel: () => _ctrl.reverse(),
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                // Icon with badge dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.iconBg,
                        borderRadius: BorderRadius.circular(_kRadiusSm),
                        boxShadow: [
                          BoxShadow(
                            color: widget.iconColor.withValues(alpha: .12),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child:
                          Icon(widget.icon, color: widget.iconColor, size: 20),
                    ),
                    if (widget.badge)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: kAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: KText.labelMd.copyWith(
                          color: widget.labelColor,
                        ),
                      ),
                      if (widget.subtitle?.isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(widget.subtitle!, style: KText.caption),
                      ],
                    ],
                  ),
                ),

                if (trailingWidget != null) trailingWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSettingsCard — groups KSettingsRows with dividers
// ══════════════════════════════════════════════════════════════════════════════
class KSettingsCard extends StatelessWidget {
  const KSettingsCard({super.key, required this.rows});
  final List<KSettingsRow> rows;

  @override
  Widget build(BuildContext context) => Container(
        decoration: _surfaceDecoration(),
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 74,
                  color: Color(0xFFF1F4F8),
                ),
            ],
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KQuickActionCard — spring-press grid card with badge bubble
// ══════════════════════════════════════════════════════════════════════════════
class KQuickActionCard extends StatefulWidget {
  const KQuickActionCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<KQuickActionCard> createState() => _KQuickActionCardState();
}

class _KQuickActionCardState extends State<KQuickActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _border;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: _kDuration300,
    );
    _scale = Tween(begin: 1.0, end: 0.91).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _border = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        hint: widget.subtitle,
        child: GestureDetector(
          onTapDown: (_) => _ctrl.forward(),
          onTapUp: (_) {
            _ctrl.reverse();
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          onTapCancel: () => _ctrl.reverse(),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.scale(
              scale: _scale.value,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_kRadius),
                  border: Border.all(
                    color: Color.lerp(
                      const Color(0xFFEDF0F4),
                      kTeal.withValues(alpha: .5),
                      _border.value,
                    )!,
                    width: 1 + _border.value * 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color.lerp(
                        const Color(0x06000000),
                        kTeal.withValues(alpha: .08),
                        _border.value,
                      )!,
                      blurRadius: 12 + _border.value * 4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: widget.iconBackground,
                            borderRadius: BorderRadius.circular(_kRadiusSm),
                            boxShadow: [
                              BoxShadow(
                                color: widget.iconColor.withValues(alpha: .15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(widget.icon,
                              color: widget.iconColor, size: 22),
                        ),
                        if ((widget.badge ?? 0) > 0)
                          Positioned(
                            top: -5,
                            right: -5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: kAccent,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Text(
                                widget.badge! > 99 ? '99+' : '${widget.badge}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.label,
                      style: KText.labelMd.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: KText.caption),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KShimmerCard — skeleton placeholder while data loads
// ══════════════════════════════════════════════════════════════════════════════
class KShimmerCard extends StatefulWidget {
  const KShimmerCard({
    super.key,
    this.height = 80,
    this.showAvatar = false,
  });

  final double height;
  final bool showAvatar;

  @override
  State<KShimmerCard> createState() => _KShimmerCardState();
}

class _KShimmerCardState extends State<KShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final shimmer = LinearGradient(
            colors: const [
              Color(0xFFF0F3F7),
              Color(0xFFE4E8EF),
              Color(0xFFF0F3F7),
            ],
            stops: const [0, .5, 1],
            begin: Alignment(-2 + _ctrl.value * 4, 0),
            end: Alignment(-1 + _ctrl.value * 4, 0),
          );

          return Container(
            height: widget.height,
            padding: const EdgeInsets.all(16),
            decoration: _surfaceDecoration(),
            child: Row(
              children: [
                if (widget.showAvatar) ...[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: shimmer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: shimmer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 11,
                        width: 120,
                        decoration: BoxDecoration(
                          gradient: shimmer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  KToast — lightweight overlay message (success / error / info)
// ══════════════════════════════════════════════════════════════════════════════
enum KToastType { success, error, info }

class KToast extends StatefulWidget {
  const KToast({
    super.key,
    required this.message,
    this.type = KToastType.success,
    this.duration = const Duration(seconds: 3),
    this.onDismissed,
  });

  final String message;
  final KToastType type;
  final Duration duration;
  final VoidCallback? onDismissed;

  static void show(
    BuildContext context,
    String message, {
    KToastType type = KToastType.success,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        child: KToast(
          message: message,
          type: type,
          onDismissed: () => entry.remove(),
        ),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<KToast> createState() => _KToastState();
}

class _KToastState extends State<KToast> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _kDuration300);
    _slide = Tween(begin: 40.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    _ctrl.forward();
    Future.delayed(widget.duration, () async {
      if (mounted) {
        await _ctrl.reverse();
        widget.onDismissed?.call();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (bg, icon, color) = switch (widget.type) {
      KToastType.success => (
          const Color(0xFF1D9E75),
          Icons.check_circle_rounded,
          Colors.white,
        ),
      KToastType.error => (
          kRed,
          Icons.error_rounded,
          Colors.white,
        ),
      KToastType.info => (
          kTeal,
          Icons.info_rounded,
          Colors.white,
        ),
    };

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _slide.value),
        child: Opacity(opacity: _opacity.value, child: child),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_kRadius),
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: .3),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
