// lib/profile/profile_settings.dart
// ─────────────────────────────────────────────────────────────────────────────
// ProfileSettings — account section, preferences section, danger zone.
// Receives all callbacks from profile_screen.dart; holds no state of its own.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'profile_constants.dart';
import 'profile_widgets.dart';
import 'profile_sheets.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  ProfileSettings
// ══════════════════════════════════════════════════════════════════════════════
class ProfileSettings extends StatelessWidget {
  const ProfileSettings({
    super.key,
    required this.notificationsOn,
    required this.onNotifToggle,
    required this.onLogout,
    required this.onDeleteAccount,
    required this.onTapRoute,
    required this.uid,
    required this.data,
  });

  final bool notificationsOn;
  final ValueChanged<bool> onNotifToggle;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;
  final void Function(String route) onTapRoute;
  final String uid;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Account ──────────────────────────────────────────────────────
          const KSectionTitle('Account'),
          const SizedBox(height: 12),
          KCard(
            child: Column(
              children: [
                KSettingsRow(
                  icon: Icons.person_outline_rounded,
                  iconColor: kBlue,
                  iconBg: kBlueBg,
                  label: 'Edit Profile',
                  onTap: () => showEditProfileSheet(
                    context,
                    uid: uid,
                    data: data,
                  ),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.lock_outline_rounded,
                  iconColor: kPurple,
                  iconBg: kPurpleBg,
                  label: 'Change Password',
                  onTap: () => onTapRoute(KRoutes.changePassword),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.verified_user_outlined,
                  iconColor: kGreen,
                  iconBg: kGreenBg,
                  label: 'Verify Student ID',
                  onTap: () => onTapRoute(KRoutes.verifyStudent),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.receipt_long_outlined,
                  iconColor: kTeal,
                  iconBg: kTealLight,
                  label: 'Payment Methods',
                  onTap: () => onTapRoute(KRoutes.payments),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Preferences ──────────────────────────────────────────────────
          const KSectionTitle('Preferences'),
          const SizedBox(height: 12),
          KCard(
            child: Column(
              children: [
                // Notifications toggle
                KSettingsRow(
                  icon: Icons.notifications_none_rounded,
                  iconColor: kAccent,
                  iconBg: kAccentBg,
                  label: 'Push Notifications',
                  trailing: Switch.adaptive(
                    value: notificationsOn,
                    onChanged: onNotifToggle,
                    activeColor: kTeal,
                    inactiveThumbColor: kTextTertiary,
                  ),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.language_rounded,
                  iconColor: kBlue,
                  iconBg: kBlueBg,
                  label: 'Language',
                  subtitle: 'English',
                  onTap: () => onTapRoute(KRoutes.language),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.dark_mode_outlined,
                  iconColor: kPurple,
                  iconBg: kPurpleBg,
                  label: 'Appearance',
                  subtitle: 'System default',
                  onTap: () => onTapRoute(KRoutes.appearance),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: kGreen,
                  iconBg: kGreenBg,
                  label: 'Privacy & Data',
                  onTap: () => onTapRoute(KRoutes.privacy),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Support ──────────────────────────────────────────────────────
          const KSectionTitle('Support'),
          const SizedBox(height: 12),
          KCard(
            child: Column(
              children: [
                KSettingsRow(
                  icon: Icons.help_outline_rounded,
                  iconColor: kTeal,
                  iconBg: kTealLight,
                  label: 'Help Center',
                  onTap: () => onTapRoute(KRoutes.support),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.star_outline_rounded,
                  iconColor: kGold,
                  iconBg: kGoldBg,
                  label: 'Rate the App',
                  onTap: () => onTapRoute(KRoutes.rateApp),
                ),
                const KRowDivider(),
                KSettingsRow(
                  icon: Icons.info_outline_rounded,
                  iconColor: kTextSecondary,
                  iconBg: kSurface,
                  label: 'About',
                  subtitle: kAppVersion,
                  onTap: () => onTapRoute(KRoutes.about),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Session ──────────────────────────────────────────────────────
          const KSectionTitle('Session'),
          const SizedBox(height: 12),
          KCard(
            child: KSettingsRow(
              icon: Icons.logout_rounded,
              iconColor: kAccent,
              iconBg: kAccentBg,
              label: 'Log Out',
              labelColor: kAccent,
              onTap: onLogout,
            ),
          ),

          const SizedBox(height: 20),

          // ── Danger zone ──────────────────────────────────────────────────
          KCard(
            borderColor: kRed.withValues(alpha: .25),
            child: KSettingsRow(
              icon: Icons.delete_forever_rounded,
              iconColor: kRed,
              iconBg: kRedBg,
              label: 'Delete Account',
              labelColor: kRed,
              subtitle: 'Permanently removes all your data',
              onTap: onDeleteAccount,
            ),
          ),

          const SizedBox(height: 12),

          // ── App version footer ───────────────────────────────────────────
          Center(
            child: Text(
              'Version $kAppVersion',
              style: KText.caption.copyWith(color: kTextTertiary),
            ),
          ),
        ],
      );
}
