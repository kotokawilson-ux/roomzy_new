// lib/core/router/app_shell.dart
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  APP SHELL  —  Advanced 2025 Layout
//
//  FAB placement:
//   • floatingActionButtonLocation → endFloat (not endDocked)
//   • FAB sits 16px above the floating pill nav  (nav = 68 + 10 margin + safe)
//   • Speed-dial grows upward from the FAB via an Overlay so it can never
//     push the FAB down or overlap the send button in chat screens
// ─────────────────────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  // ── Brand ──────────────────────────────────────────────────────────────────
  static const _teal = Color(0xFF00897B);
  static const _accent = Color(0xFFE8845A);

  // ── Nav (4 tabs) ───────────────────────────────────────────────────────────
  static const _routes = ['/home', '/hostels', '/bookings', '/profile'];
  static const _icons = [
    Icons.home_outlined,
    Icons.apartment_outlined,
    Icons.event_note_outlined,
    Icons.person_outline_rounded
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.apartment_rounded,
    Icons.event_note_rounded,
    Icons.person_rounded
  ];
  static const _labels = ['Home', 'Hostels', 'Bookings', 'Profile'];

  int _currentIndex = 0;

  // ── Chat FAB ───────────────────────────────────────────────────────────────
  late AnimationController _chatFabCtrl;
  late Animation<double> _chatFabScale;

  // ── Speed-dial ─────────────────────────────────────────────────────────────
  bool _speedDialOpen = false;
  late AnimationController _speedDialCtrl;

  // ── FAB GlobalKey so we can position the speed-dial overlay above it ───────
  final _fabKey = GlobalKey();

  OverlayEntry? _speedDialOverlay;

  @override
  void initState() {
    super.initState();

    _chatFabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _chatFabScale =
        CurvedAnimation(parent: _chatFabCtrl, curve: Curves.elasticOut);

    _speedDialCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _chatFabCtrl.forward();
  }

  @override
  void dispose() {
    _removeSpeedDial();
    _chatFabCtrl.dispose();
    _speedDialCtrl.dispose();
    super.dispose();
  }

  int _indexFromRoute(String location) {
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  // ── Speed-dial via Overlay (never interferes with page content) ────────────
  void _showSpeedDial(BuildContext context, String uid) {
    _removeSpeedDial();
    final box = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final fabPos = box.localToGlobal(Offset.zero);
    final fabSize = box.size;

    _speedDialOverlay = OverlayEntry(
      builder: (_) => _SpeedDialOverlay(
        fabBottom: MediaQuery.of(context).size.height - fabPos.dy,
        fabRight: MediaQuery.of(context).size.width - fabPos.dx - fabSize.width,
        controller: _speedDialCtrl,
        teal: _teal,
        accent: _accent,
        onClose: _removeSpeedDial,
        onChat: () {
          _removeSpeedDial();
          context.push('/chat');
        },
        onCall: () {
          _removeSpeedDial();
          ScaffoldMessenger.of(context).showSnackBar(
              _snack('Calling support…', const Color(0xFF43A047)));
        },
        onFaq: () {
          _removeSpeedDial();
          context.push('/about');
        },
      ),
    );

    Overlay.of(context).insert(_speedDialOverlay!);
    setState(() => _speedDialOpen = true);
    _speedDialCtrl.forward(from: 0);
  }

  void _removeSpeedDial() {
    _speedDialOverlay?.remove();
    _speedDialOverlay = null;
    _speedDialCtrl.reverse();
    if (mounted) setState(() => _speedDialOpen = false);
  }

  void _toggleSpeedDial(BuildContext context, String uid) {
    HapticFeedback.mediumImpact();
    _speedDialOpen ? _removeSpeedDial() : _showSpeedDial(context, uid);
  }

  void _openChat(BuildContext context) {
    HapticFeedback.lightImpact();
    _removeSpeedDial();
    context.push('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    _currentIndex = _indexFromRoute(location);

    final auth = context.watch<AuthService>();
    final uid = auth.currentUser?.id ?? '';

    // ── Bottom-nav height so FAB clears it exactly ─────────────────────────
    // Pill nav: 68px height + 10px bottom margin + system bottom inset
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navClearance = 68.0 + 10.0 + bottomInset + 16.0; // +16 gap above nav

    return Scaffold(
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: _GlassBottomNav(
        currentIndex: _currentIndex,
        routes: _routes,
        icons: _icons,
        activeIcons: _activeIcons,
        labels: _labels,
        teal: _teal,
        onTap: (i) => context.go(_routes[i]),
      ),
      // ── FAB: endFloat so Flutter places it freely; we offset it upward ────
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        // Push FAB up so it clears the floating pill nav and has breathing room.
        // The extra right padding aligns with the pill nav's edge.
        padding: EdgeInsets.only(bottom: navClearance, right: 4),
        child: ScaleTransition(
          scale: _chatFabScale,
          child: GestureDetector(
            key: _fabKey,
            onTap: () => _openChat(context),
            onLongPress: () => _toggleSpeedDial(context, uid),
            child: _ChatFab(
              uid: uid,
              teal: _teal,
              accent: _accent,
              speedDialCtrl: _speedDialCtrl,
              speedDialOpen: _speedDialOpen,
            ),
          ),
        ),
      ),
    );
  }

  SnackBar _snack(String msg, Color color) => SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT FAB BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _ChatFab extends StatelessWidget {
  const _ChatFab({
    required this.uid,
    required this.teal,
    required this.accent,
    required this.speedDialCtrl,
    required this.speedDialOpen,
  });

  final String uid;
  final Color teal;
  final Color accent;
  final AnimationController speedDialCtrl;
  final bool speedDialOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: speedDialCtrl,
      builder: (_, __) {
        final t = speedDialCtrl.value;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(teal, accent, t)!,
                    Color.lerp(
                        const Color(0xFF00695C), const Color(0xFFD4603A), t)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color.lerp(teal, accent, t)!.withOpacity(0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Transform.rotate(
                angle: t * 3.14159 * 0.25,
                child: Icon(
                  t > 0.5 ? Icons.close_rounded : Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            // Unread badge
            if (uid.isNotEmpty)
              Positioned(
                top: -2,
                right: -2,
                child: _ChatFabBadge(uid: uid),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SPEED-DIAL OVERLAY  —  renders above everything, anchored to FAB position
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedDialOverlay extends StatelessWidget {
  const _SpeedDialOverlay({
    required this.fabBottom,
    required this.fabRight,
    required this.controller,
    required this.teal,
    required this.accent,
    required this.onClose,
    required this.onChat,
    required this.onCall,
    required this.onFaq,
  });

  final double fabBottom;
  final double fabRight;
  final AnimationController controller;
  final Color teal;
  final Color accent;
  final VoidCallback onClose;
  final VoidCallback onChat;
  final VoidCallback onCall;
  final VoidCallback onFaq;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tap outside to close
        GestureDetector(
          onTap: onClose,
          child: Container(color: Colors.transparent),
        ),
        // Speed-dial items anchored just above the FAB
        Positioned(
          bottom: fabBottom + 8, // 8px gap above FAB top
          right: fabRight,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final v = CurvedAnimation(
                parent: controller,
                curve: Curves.easeOutCubic,
              ).value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _SpeedDialItem(
                    icon: Icons.phone_in_talk_rounded,
                    label: 'Call Support',
                    color: const Color(0xFF43A047),
                    progress: v,
                    delay: 0.0,
                    onTap: onCall,
                  ),
                  const SizedBox(height: 10),
                  _SpeedDialItem(
                    icon: Icons.help_outline_rounded,
                    label: 'FAQ / Help',
                    color: const Color(0xFF1E88E5),
                    progress: v,
                    delay: 0.08,
                    onTap: onFaq,
                  ),
                  const SizedBox(height: 10),
                  _SpeedDialItem(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Live Chat',
                    color: accent,
                    progress: v,
                    delay: 0.16,
                    onTap: onChat,
                  ),
                  const SizedBox(height: 10),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GLASSMORPHIC BOTTOM NAV
// ─────────────────────────────────────────────────────────────────────────────

class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({
    required this.currentIndex,
    required this.routes,
    required this.icons,
    required this.activeIcons,
    required this.labels,
    required this.teal,
    required this.onTap,
  });

  final int currentIndex;
  final List<String> routes;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final List<String> labels;
  final Color teal;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: Colors.white.withOpacity(0.6),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: List.generate(labels.length, (i) {
                  return _GlassNavItem(
                    icon: icons[i],
                    activeIcon: activeIcons[i],
                    label: labels[i],
                    isActive: currentIndex == i,
                    teal: teal,
                    onTap: () => onTap(i),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatefulWidget {
  const _GlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.teal,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final Color teal;
  final VoidCallback onTap;

  @override
  State<_GlassNavItem> createState() => _GlassNavItemState();
}

class _GlassNavItemState extends State<_GlassNavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.isActive ? 1.0 : 0.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 1.15)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_ctrl);
  }

  @override
  void didUpdateWidget(_GlassNavItem old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      widget.isActive ? _ctrl.forward() : _ctrl.reverse();
      if (widget.isActive) HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.isActive ? 14 : 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isActive
                          ? widget.teal.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      widget.isActive ? widget.activeIcon : widget.icon,
                      color: widget.isActive
                          ? widget.teal
                          : const Color(0xFFB0BEC5),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                        widget.isActive ? FontWeight.w700 : FontWeight.w400,
                    color:
                        widget.isActive ? widget.teal : const Color(0xFFB0BEC5),
                  ),
                  child: Text(widget.label),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT FAB UNREAD BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _ChatFabBadge extends StatelessWidget {
  const _ChatFabBadge({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('chats').doc(uid).snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data();
        final unread = data?['unreadByStudent'] as bool? ?? false;
        if (!unread) return const SizedBox.shrink();
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withOpacity(0.4),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SPEED DIAL ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedDialItem extends StatelessWidget {
  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.progress,
    required this.delay,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final double progress;
  final double delay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
    final opacity = p;
    final offset = (1.0 - p) * 16.0;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, offset),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Icon circle
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
