// lib/screens/landlord/profile/landlord_profile.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Landlord Profile & Settings Screen
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/landlord_service.dart';
import '../../../models/models.dart';

// ── Colour tokens ─────────────────────────────────────────────
class _C {
  static const pageBg = Color(0xFFF5F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF1F2937);
  static const textLight = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const green = Color(0xFF2D6A4F);
  static const greenLight = Color(0xFFD8F3DC);
  static const greenFaint = Color(0xFFF0FAF3);
  static const red = Color(0xFFEF4444);
  static const redLight = Color(0xFFFEE2E2);
}

// ─────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────
class LandlordProfileScreen extends StatefulWidget {
  const LandlordProfileScreen({
    super.key,
    required this.landlordId,
    required this.service,
    required this.authService,
  });

  final String landlordId;
  final LandlordService service;
  final AuthService authService;

  @override
  State<LandlordProfileScreen> createState() => _LandlordProfileScreenState();
}

class _LandlordProfileScreenState extends State<LandlordProfileScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(fontSize: 13, color: _C.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _C.textLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sign Out', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    await widget.authService.logout();
    if (!mounted) return;
    setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _C.border),
        ),
      ),
      body: FutureBuilder<Landlord?>(
        future: widget.service.getLandlord(widget.landlordId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _C.green));
          }

          final landlord = snap.data;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              // ── Avatar card ──────────────────────────────
              _AvatarCard(landlord: landlord),

              const SizedBox(height: 20),

              // ── Account info ─────────────────────────────
              if (landlord != null) ...[
                _InfoSection(
                  title: 'Account Info',
                  icon: Icons.person_outline_rounded,
                  tiles: [
                    _InfoTile(label: 'Full Name', value: landlord.fullName),
                    _InfoTile(label: 'Email', value: landlord.email),
                    _InfoTile(label: 'Phone', value: landlord.phone),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // ── Settings ─────────────────────────────────
              _SettingsSection(
                title: 'Settings',
                icon: Icons.settings_outlined,
                tiles: [
                  _SettingsTile(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () => _showComingSoon(context),
                  ),
                  _SettingsTile(
                    icon: Icons.lock_outline_rounded,
                    label: 'Change Password',
                    onTap: () => _showComingSoon(context),
                  ),
                  _SettingsTile(
                    icon: Icons.help_outline_rounded,
                    label: 'Help & Support',
                    onTap: () => _showComingSoon(context),
                  ),
                  _SettingsTile(
                    icon: Icons.info_outline_rounded,
                    label: 'About RoomzyFind',
                    onTap: () => _showAbout(context),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Sign out button ───────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _signingOut ? null : _signOut,
                  icon: _signingOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded, size: 16),
                  label: Text(
                    _signingOut ? 'Signing out…' : 'Sign Out',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'RoomzyFind v1.0.0',
                style: TextStyle(fontSize: 11, color: _C.textMuted),
              ),

              const SizedBox(height: 32),
            ]),
          );
        },
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Coming soon'),
      backgroundColor: _C.green,
    ));
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _C.greenFaint,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child:
                const Icon(Icons.home_work_rounded, size: 20, color: _C.green),
          ),
          const SizedBox(width: 10),
          const Text('RoomzyFind',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _C.textDark)),
        ]),
        content: const Text(
          'Version 1.0.0\n\nRoomzyFind helps landlords manage their hostels and rooms, and helps students find accommodation near their schools.',
          style: TextStyle(fontSize: 13, color: _C.textLight),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AVATAR CARD
// ─────────────────────────────────────────────────────────────
class _AvatarCard extends StatelessWidget {
  const _AvatarCard({required this.landlord});
  final Landlord? landlord;

  @override
  Widget build(BuildContext context) {
    final name = landlord?.fullName ?? 'Landlord';
    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(children: [
        // Avatar circle
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _C.greenFaint,
            shape: BoxShape.circle,
            border: Border.all(color: _C.greenLight, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(initials,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w700, color: _C.green)),
        ),
        const SizedBox(height: 12),
        Text(name,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: _C.textDark)),
        if (landlord?.email != null) ...[
          const SizedBox(height: 4),
          Text(landlord!.email,
              style: const TextStyle(fontSize: 13, color: _C.textLight)),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _C.greenFaint,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _C.greenLight),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 14, color: _C.green),
              SizedBox(width: 6),
              Text('Verified Landlord',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _C.green)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INFO SECTION
// ─────────────────────────────────────────────────────────────
class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.tiles,
  });
  final String title;
  final IconData icon;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                Icon(icon, size: 16, color: _C.green),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _C.textDark)),
              ]),
            ),
            const Divider(height: 20, color: _C.border),
            ...tiles,
            const SizedBox(height: 4),
          ],
        ),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: _C.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _C.textDark)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
// SETTINGS SECTION
// ─────────────────────────────────────────────────────────────
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.tiles,
  });
  final String title;
  final IconData icon;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                Icon(icon, size: 16, color: _C.green),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _C.textDark)),
              ]),
            ),
            const Divider(height: 20, color: _C.border),
            ...tiles,
          ],
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 18, color: _C.textLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _C.textDark)),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: _C.textMuted),
          ]),
        ),
      );
}
