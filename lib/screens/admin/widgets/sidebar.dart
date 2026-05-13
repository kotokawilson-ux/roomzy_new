import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../constants/admin_theme.dart';
import '../../../utils/activity_logger.dart';
import '../admin_section.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR
// ─────────────────────────────────────────────────────────────────────────────

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.current,
    required this.collapsed,
    required this.onSelect,
    required this.onToggleCollapse,
    required this.onLogout,
  });

  final AdminSection current;
  final bool collapsed;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onToggleCollapse, onLogout;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
      width: collapsed ? 68 : 240,
      decoration: const BoxDecoration(
        color: kGreen,
        // Subtle right-edge highlight to lift it off the content area
        border: Border(
          right: BorderSide(color: Colors.white10, width: 1),
        ),
      ),
      child: Column(
        children: [
          _SidebarHeader(collapsed: collapsed, onToggle: onToggleCollapse),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final group in SidebarGroup.values) ...[
                  _SidebarGroupLabel(group: group, collapsed: collapsed),
                  for (final section in group.sections)
                    _SidebarItem(
                      section: section,
                      active: current == section,
                      collapsed: collapsed,
                      onTap: () => onSelect(section),
                    ),
                  if (group != SidebarGroup.system) const _SidebarDivider(),
                ],
              ],
            ),
          ),
          const _SidebarDivider(),
          _LogoutButton(collapsed: collapsed, onLogout: onLogout),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER — Logo + collapse toggle
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed, required this.onToggle});
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 14),
      child: Row(
        children: [
          // Logo icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kGreenAccent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: kGreenAccent.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.home_work_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),

          if (!collapsed) ...[
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RoomzyFind',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    'Admin Panel',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Collapse toggle
          GestureDetector(
            onTap: onToggle,
            child: AnimatedRotation(
              turns: collapsed ? 0 : 0.5,
              duration: const Duration(milliseconds: 240),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GROUP LABEL
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel({required this.group, required this.collapsed});
  final SidebarGroup group;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: collapsed
          // When collapsed show a thin divider line instead of text
          ? Padding(
              key: ValueKey('dot-${group.name}'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Container(
                height: 1,
                color: Colors.white10,
              ),
            )
          : Padding(
              key: ValueKey('label-${group.name}'),
              padding: const EdgeInsets.fromLTRB(18, 14, 16, 4),
              child: Text(
                group.label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.section,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });
  final AdminSection section;
  final bool active, collapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.active;
    final badge = widget.section.staticBadge;
    final hasLiveDot = widget.section.showLiveDot;

    return Tooltip(
      message: widget.collapsed ? widget.section.label : '',
      preferBelow: false,
      decoration: BoxDecoration(
        color: kGreenAccent,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed ? 0 : 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? kGreenAccent.withOpacity(0.18)
                  : _hovered
                      ? Colors.white.withOpacity(0.06)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isActive
                  ? Border.all(color: kGreenAccent.withOpacity(0.4), width: 1)
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                // ── Active indicator line ──
                if (!widget.collapsed)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 3,
                    height: isActive ? 18 : 0,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: kGreenAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                // ── Icon with live dot ──
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      widget.section.icon,
                      color: isActive ? kGreenAccent : Colors.white54,
                      size: 19,
                    ),
                    if (hasLiveDot)
                      Positioned(
                        top: -2,
                        right: -3,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1DB954),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),

                if (!widget.collapsed) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      widget.section.label,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white60,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 13.5,
                      ),
                    ),
                  ),

                  // ── Badge ──
                  if (widget.section == AdminSection.liveChat)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .where('unreadByAdmin', isEqualTo: true)
                          .snapshots(),
                      builder: (_, snap) {
                        final count = snap.data?.docs.length ?? 0;
                        if (count == 0) return const SizedBox.shrink();
                        return _Badge(count: count);
                      },
                    )
                  else if (badge != null)
                    _Badge(count: badge!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGOUT BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.collapsed, required this.onLogout});
  final bool collapsed;
  final VoidCallback onLogout;

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: () async {
          final user = FirebaseAuth.instance.currentUser;
          await ActivityLogger.log(
            action: 'User Logout',
            details: 'Email: ${user?.email ?? 'Unknown'}',
          );
          widget.onLogout();
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: EdgeInsets.symmetric(
            horizontal: widget.collapsed ? 0 : 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.redAccent.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
                size: 19,
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: 12),
                const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(color: Colors.white10, height: 1, thickness: 1);
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE24B4A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
