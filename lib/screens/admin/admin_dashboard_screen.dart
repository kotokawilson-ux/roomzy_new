import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../constants/admin_theme.dart';
import 'admin_section.dart';
import 'widgets/sidebar.dart';
import 'widgets/top_bar.dart';
import 'panes/dashboard_pane.dart';
import 'panes/bookings_pane.dart';
import 'panes/landlords_pane.dart';
import 'panes/hostels_pane.dart';
import 'panes/rooms_pane.dart';
import 'panes/facilities_pane.dart';
import 'panes/schools_pane.dart';
import 'panes/users_pane.dart';
import 'panes/activity_log_pane.dart';
import 'chat/admin_live_chat_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminSection _current = AdminSection.dashboard;
  bool _sidebarCollapsed = false;

  // Single ScaffoldKey — used by BOTH layouts via the same Scaffold.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _navigateTo(AdminSection section) {
    setState(() => _current = section);
    // Close drawer if open (narrow layout).
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    // FIX: ONE Scaffold for the entire screen.
    // Previously build() returned a bare Scaffold and _narrowLayout() also
    // returned a Scaffold, giving two nested Scaffolds. The inner one painted
    // a white background over everything, causing the white-screen bug.
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kCream,
      // Drawer is only meaningful in narrow layout; harmless on wide.
      drawer: isWide
          ? null
          : Drawer(
              child: Sidebar(
                current: _current,
                collapsed: false,
                onSelect: (s) {
                  setState(() => _current = s);
                  Navigator.pop(context);
                },
                onToggleCollapse: () {},
                onLogout: _logout,
              ),
            ),
      body: isWide ? _wideLayout() : _narrowLayout(),
    );
  }

  // ── Wide layout: persistent sidebar + content ─────────────────────────────
  Widget _wideLayout() {
    return Row(
      children: [
        Sidebar(
          current: _current,
          collapsed: _sidebarCollapsed,
          onSelect: (s) => setState(() => _current = s),
          onToggleCollapse: () =>
              setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          onLogout: _logout,
        ),
        Expanded(
          child: Column(
            children: [
              TopBar(
                section: _current,
                onMenuTap: null, // no hamburger needed on wide layout
                onNavigateToSection: _navigateTo,
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ],
    );
  }

  // ── Narrow layout: hamburger opens Scaffold drawer ────────────────────────
  // FIX: No longer returns its own Scaffold. Uses the single Scaffold from
  // build() above. The TopBar hamburger now calls
  // _scaffoldKey.currentState!.openDrawer() directly.
  Widget _narrowLayout() {
    return Column(
      children: [
        // Narrow top bar: shows app branding + icon row
        _NarrowAppBar(
          onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        TopBar(
          section: _current,
          // FIX: was null — means the hamburger in TopBar was always hidden.
          // Now wired to open the Scaffold drawer.
          onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
          onNavigateToSection: _navigateTo,
        ),
        Expanded(child: _body()),
      ],
    );
  }

  // ── Body: switch panes ────────────────────────────────────────────────────
  Widget _body() => switch (_current) {
        AdminSection.dashboard => const DashboardPane(),
        AdminSection.bookings => const BookingsPane(),
        AdminSection.landlords => const LandlordsPane(),
        AdminSection.hostels => const HostelsPane(),
        AdminSection.rooms => const RoomsPane(),
        AdminSection.facilities => const FacilitiesPane(),
        AdminSection.schools => const SchoolsPane(),
        AdminSection.users => const UsersPane(),
        AdminSection.activityLog => const ActivityLogPane(),
        AdminSection.liveChat => const AdminLiveChatScreen(),
        AdminSection.analytics => const _PlaceholderPane(label: 'Analytics'),
        AdminSection.payments => const _PlaceholderPane(label: 'Payments'),
        AdminSection.revenue => const _PlaceholderPane(label: 'Revenue'),
        AdminSection.settings => const _PlaceholderPane(label: 'Settings'),
      };

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            const Text('Logout', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<AuthService>().logout();
      if (mounted) context.go('/login');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NARROW APP BAR  — replaces the AppBar widget (which required a Scaffold)
// A plain Container so we don't need a second Scaffold just for the top bar.
// ─────────────────────────────────────────────────────────────────────────────

class _NarrowAppBar extends StatelessWidget {
  const _NarrowAppBar({required this.onMenuTap});
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    // Respect the status bar height so content doesn't sit under the notch.
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      color: kGreen,
      padding: EdgeInsets.only(top: topPadding),
      height: kToolbarHeight + topPadding,
      child: Row(
        children: [
          // Hamburger
          GestureDetector(
            onTap: onMenuTap,
            child: const SizedBox(
              width: 52,
              height: kToolbarHeight,
              child: Icon(Icons.menu_rounded, color: Colors.white, size: 22),
            ),
          ),
          // Brand icon + title
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: kGreenAccent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.home_work_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          const Text(
            'RoomzyFind Admin',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLACEHOLDER PANE
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceholderPane extends StatelessWidget {
  const _PlaceholderPane({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_rounded,
              size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            '$label — Coming Soon',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
