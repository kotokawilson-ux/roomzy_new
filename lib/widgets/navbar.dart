import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import '../../services/auth_service.dart';

/// Menu item model
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

/// Helper — decides whether to push or go based on the route
void _navigate(BuildContext context, String route) {
  if (route == '/home') {
    context.go(route);
  } else {
    context.push(route);
  }
}

/// Handles logout — calls AuthService then redirects to /login
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
      content: const Text('Are you sure you want to logout?',
          style: TextStyle(fontSize: 14, color: Colors.black54)),
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

/// NAVBAR
class Navbar extends StatelessWidget implements PreferredSizeWidget {
  const Navbar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(140);

  static const List<_MenuItem> _menuItems = [
    _MenuItem(label: "Home", route: "/home", icon: Icons.home),
    _MenuItem(
        label: "Hostel/Apartment", route: "/hostels", icon: Icons.apartment),
    _MenuItem(label: "About", route: "/about", icon: Icons.info),
    _MenuItem(
        label: "Logout", route: "/logout", icon: Icons.logout, isLogout: true),
  ];

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveBreakpoints.of(context);
    final isMobile = responsive.smallerOrEqualTo(MOBILE);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F766E),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              /// LOGO
              GestureDetector(
                onTap: () => context.go('/home'),
                child: const Text(
                  "RoomzyFind",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              /// DESKTOP MENU
              if (!isMobile)
                Row(
                  children: _menuItems
                      .map((item) => Padding(
                            padding: const EdgeInsets.only(right: 30),
                            child: _NavItem(item: item),
                          ))
                      .toList(),
                ),

              /// MOBILE MENU BUTTON
              if (isMobile)
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// NAV ITEM (desktop)
class _NavItem extends StatelessWidget {
  final _MenuItem item;
  const _NavItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (item.isLogout) {
          _handleLogout(context);
        } else {
          _navigate(context, item.route);
        }
      },
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

/// MOBILE DRAWER
class NavbarDrawer extends StatelessWidget {
  const NavbarDrawer({super.key});

  static const List<_MenuItem> _menuItems = [
    _MenuItem(label: "Home", route: "/home", icon: Icons.home),
    _MenuItem(
        label: "Hostel/Apartment", route: "/hostels", icon: Icons.apartment),
    _MenuItem(label: "About", route: "/about", icon: Icons.info),
    _MenuItem(
        label: "Logout", route: "/logout", icon: Icons.logout, isLogout: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF0F766E)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.home, color: Color(0xFF0F766E), size: 32),
                ),
                SizedBox(height: 12),
                Text(
                  'RoomzyFind',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  'Find your perfect hostel',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ..._menuItems.map((item) => ListTile(
                leading: Icon(item.icon,
                    color: item.isLogout ? Colors.redAccent : null),
                title: Text(item.label,
                    style: TextStyle(
                        color: item.isLogout ? Colors.redAccent : null)),
                onTap: () {
                  if (item.isLogout) {
                    // Close drawer first, then logout after frame completes
                    // so the context remains valid for the dialog and navigation
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) _handleLogout(context);
                    });
                  } else {
                    Navigator.pop(context);
                    _navigate(context, item.route);
                  }
                },
              )),
        ],
      ),
    );
  }
}
