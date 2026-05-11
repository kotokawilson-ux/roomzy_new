import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN SECTION ENUM
// Shared across sidebar, top bar, and dashboard screen
// ─────────────────────────────────────────────────────────────────────────────

enum AdminSection {
  // ── Main ──
  dashboard,
  analytics,

  // ── Operations ──
  bookings,
  rooms,
  hostels,

  // ── Management ──
  landlords,
  facilities,
  schools,
  users,

  // ── Finance ──
  payments,
  revenue,

  // ── System ──
  liveChat,
  activityLog,
  settings,
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION GROUP — for sidebar section labels
// ─────────────────────────────────────────────────────────────────────────────

enum SidebarGroup { main, operations, management, finance, system }

extension SidebarGroupInfo on SidebarGroup {
  String get label => const {
        SidebarGroup.main: 'Main',
        SidebarGroup.operations: 'Operations',
        SidebarGroup.management: 'Management',
        SidebarGroup.finance: 'Finance',
        SidebarGroup.system: 'System',
      }[this]!;

  List<AdminSection> get sections => const {
        SidebarGroup.main: [AdminSection.dashboard, AdminSection.analytics],
        SidebarGroup.operations: [
          AdminSection.bookings,
          AdminSection.rooms,
          AdminSection.hostels,
        ],
        SidebarGroup.management: [
          AdminSection.landlords,
          AdminSection.facilities,
          AdminSection.schools,
          AdminSection.users,
        ],
        SidebarGroup.finance: [
          AdminSection.payments,
          AdminSection.revenue,
        ],
        SidebarGroup.system: [
          AdminSection.liveChat,
          AdminSection.activityLog,
          AdminSection.settings,
        ],
      }[this]!;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION METADATA
// ─────────────────────────────────────────────────────────────────────────────

extension AdminSectionInfo on AdminSection {
  String get label => const {
        AdminSection.dashboard: 'Dashboard',
        AdminSection.analytics: 'Analytics',
        AdminSection.bookings: 'Bookings',
        AdminSection.hostels: 'Hostels',
        AdminSection.rooms: 'Rooms',
        AdminSection.landlords: 'Landlords',
        AdminSection.facilities: 'Facilities',
        AdminSection.schools: 'Schools',
        AdminSection.users: 'Users',
        AdminSection.payments: 'Payments',
        AdminSection.revenue: 'Revenue',
        AdminSection.liveChat: 'Live Chat',
        AdminSection.activityLog: 'Activity Log',
        AdminSection.settings: 'Settings',
      }[this]!;

  IconData get icon => const {
        AdminSection.dashboard: Icons.dashboard_rounded,
        AdminSection.analytics: Icons.bar_chart_rounded,
        AdminSection.bookings: Icons.receipt_long_rounded,
        AdminSection.hostels: Icons.apartment_rounded,
        AdminSection.rooms: Icons.bed_rounded,
        AdminSection.landlords: Icons.person_4_rounded,
        AdminSection.facilities: Icons.room_service_rounded,
        AdminSection.schools: Icons.school_rounded,
        AdminSection.users: Icons.group_rounded,
        AdminSection.payments: Icons.credit_card_rounded,
        AdminSection.revenue: Icons.trending_up_rounded,
        AdminSection.liveChat: Icons.chat_bubble_outline_rounded,
        AdminSection.activityLog: Icons.history_rounded,
        AdminSection.settings: Icons.settings_rounded,
      }[this]!;

  /// Static badge count — replace with a real stream/provider in production.
  /// Return null for no badge.
  int? get staticBadge => const {
        AdminSection.bookings: 5,
        AdminSection.payments: 2,
        AdminSection.liveChat: 3,
      }[this];

  /// Show a green "live" dot instead of a numbered badge
  bool get showLiveDot => this == AdminSection.analytics;
}
