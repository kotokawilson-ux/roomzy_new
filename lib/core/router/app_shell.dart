// lib/core/router/app_shell.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _activeColor = Color(0xFFE8845A);
  static const _inactiveColor = Color(0xFF9E9E9E);

  // Tab index → route
  static const _routes = [
    '/home',
    '/hostels',
    '/bookings',
    '/chat',
    '/profile'
  ];

  // Icons for each tab
  static const _icons = [
    Icons.home_rounded,
    Icons.apartment_rounded,
    Icons.calendar_today_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.person_outline_rounded,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.apartment_rounded,
    Icons.calendar_today_rounded,
    Icons.chat_bubble_rounded,
    Icons.person_rounded,
  ];
  static const _labels = ['Home', 'Hostels', 'Bookings', 'Chat', 'Profile'];

  int _currentIndex = 0;

  int _indexFromRoute(String location) {
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    _currentIndex = _indexFromRoute(location);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: _RoomzyBottomNav(
        currentIndex: _currentIndex,
        activeColor: _activeColor,
        inactiveColor: _inactiveColor,
        icons: _icons,
        activeIcons: _activeIcons,
        labels: _labels,
        onTap: (i) => context.go(_routes[i]),
      ),
    );
  }
}

// ── Bottom Nav Widget ─────────────────────────────────────────────────────────

class _RoomzyBottomNav extends StatelessWidget {
  const _RoomzyBottomNav({
    required this.currentIndex,
    required this.activeColor,
    required this.inactiveColor,
    required this.icons,
    required this.activeIcons,
    required this.labels,
    required this.onTap,
  });

  final int currentIndex;
  final Color activeColor;
  final Color inactiveColor;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(labels.length, (i) {
              return _NavItem(
                icon: icons[i],
                activeIcon: activeIcons[i],
                label: labels[i],
                isActive: currentIndex == i,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                // Chat tab (index 3) shows unread badge — wire to real count below
                badgeCount: i == 3 ? _UnreadBadge() : null,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }

  // Returns a stream-based unread count widget for the chat badge.
  // Reads from chats/{studentUid} → unreadByStudent field.
  static Widget? _UnreadBadge() => null; // replaced by _ChatBadge in the item
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
  final Widget? badgeCount; // unused now; badge drawn inside

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1, end: 1.18)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_ctrl);
  }

  @override
  void didUpdateWidget(_NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _ctrl.forward(from: 0).then((_) => _ctrl.reverse());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.currentUser?.id ?? '';

    return Expanded(
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    widget.isActive ? widget.activeIcon : widget.icon,
                    color: widget.isActive
                        ? widget.activeColor
                        : widget.inactiveColor,
                    size: 24,
                  ),
                  // Chat tab unread badge
                  if (widget.label == 'Chat' && uid.isNotEmpty)
                    _ChatUnreadBadge(uid: uid),
                ],
              ),
            ),
            const SizedBox(height: 3),
            // Active dot
            if (widget.isActive)
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.activeColor,
                  shape: BoxShape.circle,
                ),
              )
            else
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: widget.inactiveColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reads unread count for student from Firestore and shows a red badge.
class _ChatUnreadBadge extends StatelessWidget {
  const _ChatUnreadBadge({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('chats').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final unread = data?['unreadByStudent'] as bool? ?? false;
        if (!unread) return const SizedBox.shrink();
        return Positioned(
          top: -4,
          right: -6,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
