// lib/widgets/navbar.dart
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  NAVBAR  —  2025 Style  (zero duplication, no avatar dropdown)
// ─────────────────────────────────────────────────────────────────────────────

class _MenuItem {
  final String label;
  final String route;
  final IconData icon;
  const _MenuItem(
      {required this.label, required this.route, required this.icon});
}

void _navigate(BuildContext context, String route) {
  if (route == '/home') {
    context.go(route);
  } else {
    context.push(route);
  }
}

Future<void> _handleLogout(BuildContext context) async {
  final router = GoRouter.of(context);
  final auth = context.read<AuthService>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.logout_rounded, color: Colors.redAccent),
          SizedBox(width: 10),
          Text('Logout',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
      content: const Text(
        'Are you sure you want to logout?',
        style: TextStyle(fontSize: 14, color: Colors.black54),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Logout', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await auth.logout();
    router.go('/login');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NAVBAR WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class Navbar extends StatefulWidget implements PreferredSizeWidget {
  const Navbar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 20);

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> {
  static const _teal = Color(0xFF00897B);

  static const List<_MenuItem> _desktopItems = [];

  OverlayEntry? _notifPanel;
  final _notifKey = GlobalKey();

  @override
  void dispose() {
    _notifPanel?.remove();
    super.dispose();
  }

  void _openNotifications(BuildContext context, String uid) {
    HapticFeedback.selectionClick();
    if (_notifPanel != null) {
      _notifPanel!.remove();
      _notifPanel = null;
      return;
    }

    final box = _notifKey.currentContext!.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;

    // Capture the navigator context before the overlay is built.
    final navContext = context;

    _notifPanel = OverlayEntry(
      builder: (overlayCtx) {
        final screenW = MediaQuery.of(overlayCtx).size.width;
        final panelW = screenW < 340 ? screenW - 24.0 : 300.0;
        final rightEdge = screenW - pos.dx - size.width;
        final clampedRight = rightEdge.clamp(8.0, screenW - panelW - 8);

        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                _notifPanel?.remove();
                _notifPanel = null;
              },
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              top: pos.dy + size.height + 8,
              right: clampedRight,
              child: _NotificationPanel(
                uid: uid,
                teal: _teal,
                // Pass the outer context so the panel can call context.push
                navContext: navContext,
                onClose: () {
                  _notifPanel?.remove();
                  _notifPanel = null;
                },
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_notifPanel!);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.of(context).smallerOrEqualTo(MOBILE);
    final auth = context.watch<AuthService>();
    final username = auth.currentUser?.username ?? 'Student';
    final uid = auth.currentUser?.id ?? '';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'R';

    return Container(
      decoration: const BoxDecoration(
        color: _teal,
        boxShadow: [
          BoxShadow(
              color: Color(0x28000000), blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight + 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // ── Logo ──────────────────────────────────────────────────────
                GestureDetector(
                  onTap: () => context.go('/home'),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.home_work_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'RoomzyFind',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Desktop nav links ──────────────────────────────────────────
                if (!isMobile) ...[
                  const SizedBox(width: 36),
                  ...(_desktopItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(right: 28),
                      child: _DesktopNavLink(item: item),
                    ),
                  )),
                ],

                const Spacer(),

                // ── Right-side actions ─────────────────────────────────────────
                Row(
                  children: [
                    _NotifBell(
                      uid: uid,
                      bellKey: _notifKey,
                      onTap: () => _openNotifications(context, uid),
                    ),
                    const SizedBox(width: 8),
                    if (!isMobile)
                      Builder(
                        builder: (ctx) => _DesktopUserChip(
                          username: username,
                          initial: initial,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Scaffold.of(ctx).openEndDrawer();
                          },
                        ),
                      ),
                    if (isMobile) ...[
                      const SizedBox(width: 4),
                      Builder(
                        builder: (ctx) => _NavIconBtn(
                          icon: Icons.menu_rounded,
                          tooltip: 'Menu',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Scaffold.of(ctx).openEndDrawer();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DESKTOP USER CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopUserChip extends StatefulWidget {
  final String username;
  final String initial;
  final VoidCallback onTap;
  const _DesktopUserChip(
      {required this.username, required this.initial, required this.onTap});

  @override
  State<_DesktopUserChip> createState() => _DesktopUserChipState();
}

class _DesktopUserChipState extends State<_DesktopUserChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withOpacity(0.28)
                : Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(40),
            border:
                Border.all(color: Colors.white.withOpacity(0.35), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE8845A), Color(0xFFD4603A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.username.split(' ').first,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white70, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SMALL ICON BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _NavIconBtn extends StatelessWidget {
  const _NavIconBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NOTIFICATION BELL
// ─────────────────────────────────────────────────────────────────────────────

class _NotifBell extends StatelessWidget {
  const _NotifBell(
      {required this.uid, required this.bellKey, required this.onTap});
  final String uid;
  final GlobalKey bellKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance.collection('chats').doc(uid).snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data();
        final unread = data?['unreadByStudent'] as bool? ?? false;
        return GestureDetector(
          key: bellKey,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_rounded,
                    color: Colors.white, size: 20),
              ),
              if (unread)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF00897B), width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NOTIFICATION PANEL
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.uid,
    required this.teal,
    required this.navContext,
    required this.onClose,
  });
  final String uid;
  final Color teal;

  /// The BuildContext from the Navbar, used to call context.push('/chat').
  final BuildContext navContext;
  final VoidCallback onClose;

  void _goToMessage(String messageId) {
    onClose(); // close panel first
    // Push chat screen, passing the message ID to scroll to.
    navContext.push('/chat', extra: {'scrollToMessageId': messageId});
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final panelW = screenW < 340 ? screenW - 24 : 300.0;

    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        width: panelW,
        height: 370,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Icon(Icons.notifications_rounded, color: teal, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2E2B)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onClose,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Scrollable list ──────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: uid.isEmpty
                    ? const Stream.empty()
                    : FirebaseFirestore.instance
                        .collection('chats')
                        .doc(uid)
                        .collection('messages')
                        .where('role', isEqualTo: 'admin')
                        .orderBy('timestamp', descending: true)
                        .limit(5)
                        .snapshots(),
                builder: (_, snap) {
                  // ── Still loading ─────────────────────────────────────────
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: teal,
                        ),
                      ),
                    );
                  }

                  final docs = snap.data?.docs ?? [];

                  // ── No messages yet ───────────────────────────────────────
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mark_chat_read_rounded,
                              size: 44, color: teal.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          const Text(
                            "You're all caught up!",
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  }

                  // ── Messages list ─────────────────────────────────────────
                  return ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final doc = docs[i];
                      final data = doc.data();
                      final text = data['text'] as String? ?? '';
                      final ts = data['timestamp'] as Timestamp?;
                      final time = ts != null ? _formatTime(ts.toDate()) : '';
                      final messageId = doc.id;

                      return InkWell(
                        // ── Tap → go to chat and scroll to this message ──────
                        onTap: () => _goToMessage(messageId),
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: teal.withOpacity(0.1),
                                shape: BoxShape.circle),
                            child: Icon(Icons.support_agent_rounded,
                                color: teal, size: 18),
                          ),
                          title: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Support replied',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A2E2B)),
                                ),
                              ),
                              // Small arrow hint so user knows it's tappable
                              Icon(Icons.arrow_forward_ios_rounded,
                                  size: 11, color: teal.withOpacity(0.5)),
                            ],
                          ),
                          subtitle: Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 52),
                            child: Text(
                              time,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  fontSize: 10.5, color: Colors.grey),
                            ),
                          ),
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 2),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Footer: mark all read ────────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: GestureDetector(
                onTap: () {
                  if (uid.isNotEmpty) {
                    FirebaseFirestore.instance.collection('chats').doc(uid).set(
                        {'unreadByStudent': false}, SetOptions(merge: true));
                  }
                  onClose();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Mark all as read',
                      style: TextStyle(
                          color: teal,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day) {
      final h = dt.hour > 12
          ? dt.hour - 12
          : dt.hour == 0
              ? 12
              : dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $period';
    }
    return '${dt.day}/${dt.month}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DESKTOP NAV LINK
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopNavLink extends StatefulWidget {
  final _MenuItem item;
  const _DesktopNavLink({required this.item});

  @override
  State<_DesktopNavLink> createState() => _DesktopNavLinkState();
}

class _DesktopNavLinkState extends State<_DesktopNavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isActive = location.startsWith(widget.item.route);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _navigate(context, widget.item.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withOpacity(0.22)
                : _hovered
                    ? Colors.white.withOpacity(0.15)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.item.label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NAVBAR DRAWER
// ─────────────────────────────────────────────────────────────────────────────

class NavbarDrawer extends StatelessWidget {
  const NavbarDrawer({super.key});

  static const List<_MenuItem> _drawerItems = [
    _MenuItem(
        label: 'Settings', route: '/settings', icon: Icons.settings_outlined),
    _MenuItem(
        label: 'About', route: '/about', icon: Icons.info_outline_rounded),
    _MenuItem(
        label: 'Contact', route: '/contact', icon: Icons.mail_outline_rounded),
  ];

  static const _teal = Color(0xFF00897B);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final username = auth.currentUser?.username ?? 'Student';
    final email = auth.currentUser?.email ?? '';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'R';

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 56, 22, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00897B), Color(0xFF00695C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE8845A), Color(0xFFD4603A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.4), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(email,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5)),
                ],
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded,
                          color: Color(0xFF69F0AE), size: 13),
                      SizedBox(width: 5),
                      Text(
                        'Student Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 16, 6),
                  child: Text(
                    'MORE OPTIONS',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                ..._drawerItems.map(
                  (item) => _DrawerItem(
                    item: item,
                    teal: _teal,
                    onTap: () {
                      Navigator.pop(context);
                      _navigate(context, item.route);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Divider(),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InkWell(
                    onTap: () {
                      final nav = Navigator.of(context);
                      final rootCtx = context;
                      nav.pop();
                      _handleLogout(rootCtx);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.logout_rounded,
                              color: Colors.redAccent, size: 20),
                          SizedBox(width: 12),
                          Text(
                            'Logout',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.home_work_rounded,
                      color: _teal, size: 17),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RoomzyFind',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2E2B)),
                    ),
                    Text(
                      'v1.0.0 · Student Portal',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DRAWER ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerItem extends StatelessWidget {
  const _DrawerItem(
      {required this.item, required this.teal, required this.onTap});
  final _MenuItem item;
  final Color teal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: teal.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: teal, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              item.label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A2E2B),
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
