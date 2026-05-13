// lib/widgets/navbar.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MENU ITEM MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _MenuItem {
  final String label;
  final String route;
  final IconData icon;
  final bool isLogout;

  const _MenuItem({
    required this.label,
    required this.route,
    required this.icon,
    this.isLogout = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  HELPERS  –  unchanged from your original
// ─────────────────────────────────────────────────────────────────────────────
void _navigate(BuildContext context, String route) {
  if (route == '/home') {
    context.go(route);
  } else {
    context.push(route);
  }
}

Future<void> _handleLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.logout, color: Colors.redAccent),
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
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Logout', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await context.read<AuthService>().logout();
    if (context.mounted) context.go('/login');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NAVBAR
//  • Mobile  → only shows logo + hamburger (bottom nav handles tab switching)
//  • Desktop → shows full menu (no bottom nav on desktop)
// ─────────────────────────────────────────────────────────────────────────────
class Navbar extends StatelessWidget implements PreferredSizeWidget {
  const Navbar({super.key});

  @override
  // Keep same height — nothing changes visually on mobile except the menu
  Size get preferredSize => const Size.fromHeight(140);

  // Desktop menu items — bottom nav already covers these on mobile
  static const List<_MenuItem> _desktopItems = [
    _MenuItem(label: 'Home', route: '/home', icon: Icons.home),
    _MenuItem(label: 'About', route: '/about', icon: Icons.info),
    _MenuItem(label: 'Contact', route: '/contact', icon: Icons.mail),
    _MenuItem(
        label: 'Logout', route: '/logout', icon: Icons.logout, isLogout: true),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.of(context).smallerOrEqualTo(MOBILE);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F766E),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── LOGO ──────────────────────────────────────────────────
              GestureDetector(
                onTap: () => context.go('/home'),
                child: const Text(
                  'RoomzyFind',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // ── DESKTOP: full nav menu ─────────────────────────────────
              if (!isMobile)
                Row(
                  children: _desktopItems
                      .map((item) => Padding(
                            padding: const EdgeInsets.only(right: 30),
                            child: _NavItem(item: item),
                          ))
                      .toList(),
                ),

              // ── MOBILE: hamburger only (bottom nav handles tab switching)
              if (isMobile)
                Row(
                  children: [
                    // Logout icon — quick access without opening drawer
                    IconButton(
                      icon: const Icon(Icons.logout,
                          color: Colors.white70, size: 22),
                      tooltip: 'Logout',
                      onPressed: () => _handleLogout(context),
                    ),
                    // Hamburger → opens drawer for About / Contact / extra links
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu,
                            color: Colors.white, size: 28),
                        onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DESKTOP NAV ITEM
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final _MenuItem item;
  const _NavItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => item.isLogout
          ? _handleLogout(context)
          : _navigate(context, item.route),
      child: Text(
        item.label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: item.isLogout ? Colors.redAccent : Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MOBILE DRAWER
//  On mobile, the drawer is for secondary links (About, Contact)
//  because the bottom nav already handles Home/Hostels/Bookings/Profile
// ─────────────────────────────────────────────────────────────────────────────
class NavbarDrawer extends StatelessWidget {
  const NavbarDrawer({super.key});

  // Drawer items — excludes tabs already in bottom nav
  static const List<_MenuItem> _drawerItems = [
    _MenuItem(label: 'About', route: '/about', icon: Icons.info_outline),
    _MenuItem(label: 'Contact', route: '/contact', icon: Icons.mail_outline),
    _MenuItem(
        label: 'Logout', route: '/logout', icon: Icons.logout, isLogout: true),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final username = auth.currentUser?.username ?? 'Student';
    final email = auth.currentUser?.email ?? '';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── DRAWER HEADER ──────────────────────────────────────────────
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF0F766E)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : 'R',
                    style: const TextStyle(
                      color: Color(0xFF0F766E),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),

          // ── SEPARATOR LABEL ────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'MORE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // ── DRAWER MENU ITEMS ──────────────────────────────────────────
          ..._drawerItems.map(
            (item) => ListTile(
              leading: Icon(
                item.icon,
                color:
                    item.isLogout ? Colors.redAccent : const Color(0xFF0F766E),
              ),
              title: Text(
                item.label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: item.isLogout ? Colors.redAccent : null,
                ),
              ),
              onTap: () {
                if (item.isLogout) {
                  final rootContext = Navigator.of(context).context;
                  Navigator.pop(context);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) _handleLogout(rootContext);
                  });
                } else {
                  Navigator.pop(context);
                  _navigate(context, item.route);
                }
              },
            ),
          ),

          const Divider(height: 32),

          // ── APP VERSION ────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'RoomzyFind v1.0.0',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
