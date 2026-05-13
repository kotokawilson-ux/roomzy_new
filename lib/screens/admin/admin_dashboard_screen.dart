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
// ADMIN DASHBOARD SCREEN — shell only, all logic lives in panes + widgets
// ─────────────────────────────────────────────────────────────────────────────

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminSection _current = AdminSection.dashboard;
  bool _sidebarCollapsed = false;

  // FIX: key needed so _narrowLayout can open the drawer programmatically
  // from the TopBar's onMenuTap callback
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // FIX: shared navigation handler used by BOTH layouts and passed into
  // TopBar's onNavigateToSection — was an empty lambda `(p1) {}` before,
  // which meant "View all activity logs" and "Open Live Chat" never worked
  void _navigateTo(AdminSection section) {
    setState(() => _current = section);
    // Close the drawer if it's open (narrow layout)
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: kCream,
      body: isWide ? _wideLayout() : _narrowLayout(),
    );
  }

  // ── Wide layout: persistent sidebar + content ──────────────────────────────
  Widget _wideLayout() => Row(
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
                  onMenuTap: null, // ← this hides/disables the ≡ icon in TopBar
                  onNavigateToSection: _navigateTo,
                ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ],
      );

  // ── Narrow layout: drawer sidebar + app bar ────────────────────────────────
  Widget _narrowLayout() => Scaffold(
        key: _scaffoldKey, // FIX: attach key so onMenuTap can open drawer
        backgroundColor: kCream,
        drawer: Drawer(
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
        appBar: AppBar(
          backgroundColor: kGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: kGreenAccent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.home_work_rounded,
                  color: Colors.white,
                  size: 16,
                ),
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
        ),
        // FIX: wrap body in a TopBar so the notification/message/profile
        // icons are visible and functional on narrow screens too.
        // Previously _body() was used directly, so those icons were missing
        // entirely on mobile — only the AppBar was shown.
        body: Column(
          children: [
            TopBar(
              section: _current,
              onMenuTap: null,
              onNavigateToSection: _navigateTo,
            ),
            Expanded(child: _body()),
          ],
        ),
      );

  // ── Body: switch between panes based on current section ───────────────────
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

  // ── Logout with confirmation dialog ───────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.white),
            ),
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
// PLACEHOLDER PANE — shown for sections not yet implemented
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
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
