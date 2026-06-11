// lib/screens/landlord/landlord_portal.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Landlord Portal Shell  (fully responsive)
// Breakpoints:
//   mobile  < 600 px  → bottom nav + full-screen drawer
//   tablet  600–900   → collapsed sidebar (icons only)
//   desktop > 900     → full sidebar, collapsible
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/landlord_service.dart';
import '../../models/models.dart';
import 'dashboard/landlord_dashboard.dart';
import 'hostels/landlord_hostels.dart';
import 'rooms/landlord_rooms.dart';
import 'bookings/landlord_bookings.dart';
import 'profile/landlord_profile.dart';

// ─────────────────────────────────────────────────────────────
// COLOUR TOKENS
// ─────────────────────────────────────────────────────────────
class _C {
  static const sidebarBg = Color(0xFF1B4332);
  static const pageBg = Color(0xFFF5F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF1F2937);
  static const textLight = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const green = Color(0xFF2D6A4F);
  static const greenLight = Color(0xFFD8F3DC);
  static const greenFaint = Color(0xFFF0FAF3);
}

// ─────────────────────────────────────────────────────────────
// NAV ITEMS
// ─────────────────────────────────────────────────────────────
enum _Page { dashboard, hostels, rooms, bookings, profile }

class _NavItem {
  final _Page page;
  final IconData icon;
  final String label;
  const _NavItem(this.page, this.icon, this.label);
}

const _mainNav = [
  _NavItem(_Page.dashboard, Icons.dashboard_rounded, 'Dashboard'),
  _NavItem(_Page.hostels, Icons.apartment_rounded, 'My Hostels'),
  _NavItem(_Page.rooms, Icons.bed_rounded, 'Rooms'),
  _NavItem(_Page.bookings, Icons.calendar_month_rounded, 'Bookings'),
];

const _bottomNav = [
  _NavItem(_Page.profile, Icons.person_outline_rounded, 'Profile'),
];

// ─────────────────────────────────────────────────────────────
// BREAKPOINTS
// ─────────────────────────────────────────────────────────────
enum _Layout { mobile, tablet, desktop }

_Layout _layoutOf(double width) {
  if (width < 600) return _Layout.mobile;
  if (width < 900) return _Layout.tablet;
  return _Layout.desktop;
}

// ─────────────────────────────────────────────────────────────
// PORTAL ROOT
// ─────────────────────────────────────────────────────────────
class LandlordPortal extends StatefulWidget {
  const LandlordPortal({super.key});

  @override
  State<LandlordPortal> createState() => _LandlordPortalState();
}

class _LandlordPortalState extends State<LandlordPortal> {
  _Page _current = _Page.dashboard;

  // On desktop: user-toggled. On tablet: forced collapsed.
  bool _sidebarCollapsedByUser = false;

  Landlord? _landlord;
  bool _landlordLoaded = false;

  late final LandlordService _service;
  AuthService? _auth;

  @override
  void initState() {
    super.initState();
    _service = LandlordService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth ??= context.read<AuthService>();

    if (!_landlordLoaded) _loadLandlord();
  }

  Future<void> _loadLandlord() async {
    final lid = _auth?.landlordId;
    if (lid == null) return;
    final l = await _service.getLandlord(lid);
    if (mounted) {
      setState(() {
        _landlord = l;
        _landlordLoaded = true;
      });
    }
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (mounted) context.go('/login');
  }

  String get _pageTitle => switch (_current) {
        _Page.dashboard => 'Dashboard',
        _Page.hostels => 'My Hostels',
        _Page.rooms => 'Rooms',
        _Page.bookings => 'Bookings',
        _Page.profile => 'Profile',
      };

  Widget _buildPage() {
    final lid = _auth?.landlordId ?? '';

    if (lid.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _C.green),
      );
    }

    return switch (_current) {
      _Page.dashboard => LandlordDashboard(landlordId: lid, service: _service),
      _Page.hostels => LandlordHostels(landlordId: lid, service: _service),
      _Page.rooms => LandlordRooms(landlordId: lid, service: _service),
      _Page.bookings =>
        LandlordBookingsScreen(landlordId: lid, service: _service),
      _Page.profile => LandlordProfileScreen(
          landlordId: lid,
          service: _service,
          authService: _auth!,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    _auth = auth;
    final mq = MediaQuery.of(context);
    final layout = _layoutOf(mq.size.width);
    final collapsed = layout == _Layout.tablet ? true : _sidebarCollapsedByUser;

    return Scaffold(
      backgroundColor: _C.pageBg,

      // ── Mobile drawer ──────────────────────────────────────
      drawer: layout == _Layout.mobile
          ? Drawer(
              width: 260,
              backgroundColor: _C.sidebarBg,
              child: SafeArea(
                child: _SidebarContent(
                  current: _current,
                  collapsed: false,
                  landlord: _landlord,
                  onSelect: (p) {
                    // Pop FIRST so the drawer closes cleanly,
                    // then update state — prevents rebuild mid-animation.
                    Navigator.pop(context);
                    setState(() => _current = p);
                  },
                  onLogout: _logout,
                  onToggle: () {}, // no collapse inside drawer
                  showToggle: false,
                ),
              ),
            )
          : null,

      // ── Bottom nav (mobile only) ───────────────────────────
      bottomNavigationBar: layout == _Layout.mobile
          ? _BottomNav(
              current: _current,
              onSelect: (p) => setState(() => _current = p),
            )
          : null,

      // ── Body ───────────────────────────────────────────────
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // ── Sidebar (tablet / desktop) ───────────────────
            if (layout != _Layout.mobile)
              _Sidebar(
                current: _current,
                collapsed: collapsed,
                landlord: _landlord,
                onSelect: (p) => setState(() => _current = p),
                onLogout: _logout,
                onToggle: layout == _Layout.desktop
                    ? () => setState(
                          () => _sidebarCollapsedByUser =
                              !_sidebarCollapsedByUser,
                        )
                    : () {}, // tablet: toggle hidden
                showToggle: layout == _Layout.desktop,
              ),

            // ── Main content ─────────────────────────────────
            Expanded(
              child: Column(
                children: [
                  // Builder gives _TopBar a true descendant context
                  // so Scaffold.of() can reliably find the Scaffold.
                  Builder(
                    builder: (innerContext) => _TopBar(
                      pageTitle: _pageTitle,
                      landlord: _landlord,
                      layout: layout,
                      onMenuTap: layout == _Layout.mobile
                          ? () => Scaffold.of(innerContext).openDrawer()
                          : null,
                    ),
                  ),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: _buildPage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SIDEBAR SHELL  (animated width container)
// ─────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.current,
    required this.collapsed,
    required this.landlord,
    required this.onSelect,
    required this.onLogout,
    required this.onToggle,
    required this.showToggle,
  });

  final _Page current;
  final bool collapsed;
  final Landlord? landlord;
  final void Function(_Page) onSelect;
  final VoidCallback onLogout;
  final VoidCallback onToggle;
  final bool showToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: collapsed ? 64.0 : 220.0,
      color: _C.sidebarBg,
      child: _SidebarContent(
        current: current,
        collapsed: collapsed,
        landlord: landlord,
        onSelect: onSelect,
        onLogout: onLogout,
        onToggle: onToggle,
        showToggle: showToggle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SIDEBAR CONTENT  (reused by drawer + desktop sidebar)
// ─────────────────────────────────────────────────────────────
class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.current,
    required this.collapsed,
    required this.landlord,
    required this.onSelect,
    required this.onLogout,
    required this.onToggle,
    required this.showToggle,
  });

  final _Page current;
  final bool collapsed;
  final Landlord? landlord;
  final void Function(_Page) onSelect;
  final VoidCallback onLogout;
  final VoidCallback onToggle;
  final bool showToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SidebarBrand(
          collapsed: collapsed,
          onToggle: onToggle,
          showToggle: showToggle,
        ),
        if (!collapsed) const _SidebarSection('MAIN'),
        ..._mainNav.map((n) => _SidebarTile(
              item: n,
              active: current == n.page,
              collapsed: collapsed,
              onTap: () => onSelect(n.page),
            )),
        const Spacer(),
        const Divider(color: Color(0x33FFFFFF), height: 1),
        const SizedBox(height: 8),
        ..._bottomNav.map((n) => _SidebarTile(
              item: n,
              active: current == n.page,
              collapsed: collapsed,
              onTap: () => onSelect(n.page),
            )),
        _LogoutTile(collapsed: collapsed, onLogout: onLogout),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SIDEBAR BRAND
// ─────────────────────────────────────────────────────────────
class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.collapsed,
    required this.onToggle,
    required this.showToggle,
  });

  final bool collapsed;
  final VoidCallback onToggle;
  final bool showToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: collapsed
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.apartment_rounded,
                      color: Colors.white, size: 18),
                ),
                if (showToggle) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onToggle,
                    child: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white54, size: 16),
                  ),
                ],
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.apartment_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('RoomzyFind',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        Text('Landlord Portal',
                            style: TextStyle(
                                color: Color(0xAAFFFFFF), fontSize: 10)),
                      ],
                    ),
                  ),
                  if (showToggle)
                    IconButton(
                      onPressed: onToggle,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(Icons.chevron_left_rounded,
                          color: Colors.white70, size: 18),
                      tooltip: 'Collapse',
                    ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SIDEBAR SECTION LABEL
// ─────────────────────────────────────────────────────────────
class _SidebarSection extends StatelessWidget {
  const _SidebarSection(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(label,
            style: const TextStyle(
                color: Color(0x88FFFFFF),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      );
}

// ─────────────────────────────────────────────────────────────
// SIDEBAR TILE
// ─────────────────────────────────────────────────────────────
class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: collapsed ? 10 : 8, vertical: 2),
      child: Tooltip(
        message: collapsed ? item.label : '',
        preferBelow: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 10 : 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  active ? Colors.white.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: active
                  ? Border.all(color: Colors.white.withOpacity(0.10))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(item.icon,
                    color: active ? Colors.white : Colors.white60, size: 18),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.label,
                        style: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400)),
                  ),
                  if (active)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LOGOUT TILE
// ─────────────────────────────────────────────────────────────
class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.collapsed, required this.onLogout});

  final bool collapsed;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.symmetric(horizontal: collapsed ? 10 : 8, vertical: 2),
        child: Tooltip(
          message: collapsed ? 'Logout' : '',
          child: InkWell(
            onTap: onLogout,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 10 : 12, vertical: 10),
              decoration:
                  BoxDecoration(borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  const Icon(Icons.logout_rounded,
                      color: Color(0xFFFF6B6B), size: 18),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    const Text('Logout',
                        style: TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// BOTTOM NAV  (mobile only)
// ─────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onSelect});

  final _Page current;
  final void Function(_Page) onSelect;

  @override
  Widget build(BuildContext context) {
    final all = [..._mainNav, ..._bottomNav];
    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(top: BorderSide(color: _C.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: all.map((n) {
              final active = current == n.page;
              return Expanded(
                child: InkWell(
                  onTap: () => onSelect(n.page),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(n.icon,
                          color: active ? _C.green : _C.textMuted, size: 22),
                      const SizedBox(height: 2),
                      Text(n.label,
                          style: TextStyle(
                              fontSize: 10,
                              color: active ? _C.green : _C.textMuted,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.pageTitle,
    required this.landlord,
    required this.layout,
    this.onMenuTap,
  });

  final String pageTitle;
  final Landlord? landlord;
  final _Layout layout;
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    final name = landlord?.fullName ?? 'Landlord';
    final initials = name
        .trim()
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          // ── Hamburger (mobile only) ──────────────────────
          if (layout == _Layout.mobile) ...[
            IconButton(
              onPressed: onMenuTap,
              icon: const Icon(Icons.menu_rounded, color: _C.textDark),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
          ],

          // ── Breadcrumb ───────────────────────────────────
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (layout != _Layout.mobile) ...[
                  const Text('Landlord',
                      style: TextStyle(fontSize: 13, color: _C.textMuted)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: _C.textMuted),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    pageTitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _C.textDark),
                  ),
                ),
              ],
            ),
          ),

          // ── Name + avatar (always at far right) ──────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (layout == _Layout.desktop)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _C.textDark)),
                        const Text('Landlord',
                            style:
                                TextStyle(fontSize: 10, color: _C.textMuted)),
                      ],
                    ),
                  ),
                ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.greenLight,
                  border: Border.all(color: _C.green, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _C.green),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
