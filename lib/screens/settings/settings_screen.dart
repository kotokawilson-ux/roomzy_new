// lib/screens/settings/settings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Design Tokens (matches hostel_detail_screen.dart) ────────────────────────
const _kPrimary = Color(0xFF0F766E);
const _kAccent = Color(0xFF14B8A6);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kCard = Colors.white;
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kOrange = Color(0xFFEA580C);
const _kSurface = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE2E8F0);
const _kTextMuted = Color(0xFF64748B);
const _kTextDim = Color(0xFF94A3B8);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = FirebaseAuth.instance;
  final _store = FirebaseFirestore.instance;

  bool _pushNotifs = true;
  bool _emailNotifs = true;
  bool _darkMode = false;
  bool _loading = true;
  bool _busy = false;

  String get _uid => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    DocumentSnapshot<Map<String, dynamic>>? doc;
    if (_uid.isNotEmpty) {
      doc = await _store.collection('users').doc(_uid).get();
    }
    if (!mounted) return;

    final data = doc?.data() ?? {};
    setState(() {
      _pushNotifs = data['notificationsEnabled'] as bool? ?? true;
      _emailNotifs = data['emailNotificationsEnabled'] as bool? ?? true;
      _darkMode = prefs.getBool('dark_mode_enabled') ?? false;
      _loading = false;
    });
  }

  Future<void> _updateField(String field, bool value) async {
    HapticFeedback.selectionClick();
    if (_uid.isEmpty) return;
    await _store.collection('users').doc(_uid).set(
      {field: value},
      SetOptions(merge: true),
    );
  }

  Future<void> _toggleDarkMode(bool value) async {
    setState(() => _darkMode = value);
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode_enabled', value);
    if (!mounted) return;
    _showSnack(
      value
          ? 'Dark mode saved. Full app theming can be wired to this next.'
          : 'Light mode restored.',
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? _kRed : _kDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Change password (with reauth) ─────────────────────────────────────────
  Future<void> _changePassword() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text('Change Password',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _kDark)),
                const SizedBox(height: 18),
                TextFormField(
                  controller: currentCtrl,
                  obscureText: true,
                  decoration: _fieldDecoration('Current Password'),
                  validator: (v) =>
                      v!.isEmpty ? 'Enter your current password' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: _fieldDecoration('New Password'),
                  validator: (v) => v!.length < 6
                      ? 'Password must be at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(ctx, true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Update Password',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true) return;

    setState(() => _busy = true);
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newCtrl.text);
      if (!mounted) return;
      _showSnack('Password updated successfully ✓');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.code == 'wrong-password'
            ? 'Current password is incorrect.'
            : 'Could not update password: ${e.message}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: _kSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
      );

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text(message,
            style: const TextStyle(color: _kTextMuted, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) await action();
  }

  Future<void> _logout() async {
    await _confirmAndRun(
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmLabel: 'Log Out',
      confirmColor: _kPrimary,
      action: () async {
        await _auth.signOut();
        if (!mounted) return;
        context.go('/login');
      },
    );
  }

  Future<void> _deleteAccount() async {
    await _confirmAndRun(
      title: 'Delete Account',
      message:
          'This permanently deletes your account and all your data, including bookings. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: _kRed,
      action: () async {
        try {
          await _store.collection('users').doc(_uid).delete();
          if (!mounted) return;
          await _auth.currentUser?.delete();
          if (!mounted) return;
          context.go('/login');
        } on FirebaseAuthException catch (e) {
          if (!mounted) return;
          _showSnack(
            e.code == 'requires-recent-login'
                ? 'Please log out and back in, then try deleting again.'
                : 'Could not delete account: ${e.message}',
            isError: true,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _kDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings',
            style: TextStyle(
                color: _kDark, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
                  children: [
                    _SectionLabel('Notifications'),
                    _SettingsCard(children: [
                      _ToggleRow(
                        icon: Icons.notifications_active_rounded,
                        label: 'Push Notifications',
                        subtitle: 'Booking updates, payment reminders',
                        value: _pushNotifs,
                        onChanged: (v) {
                          setState(() => _pushNotifs = v);
                          _updateField('notificationsEnabled', v);
                        },
                      ),
                      const _RowDivider(),
                      _ToggleRow(
                        icon: Icons.mail_outline_rounded,
                        label: 'Email Notifications',
                        subtitle: 'Receipts, confirmations, offers',
                        value: _emailNotifs,
                        onChanged: (v) {
                          setState(() => _emailNotifs = v);
                          _updateField('emailNotificationsEnabled', v);
                        },
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('Appearance'),
                    _SettingsCard(children: [
                      _ToggleRow(
                        icon: Icons.dark_mode_rounded,
                        label: 'Dark Mode',
                        subtitle: 'Easier on the eyes at night',
                        value: _darkMode,
                        onChanged: _toggleDarkMode,
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('Security'),
                    _SettingsCard(children: [
                      _NavRow(
                        icon: Icons.lock_outline_rounded,
                        label: 'Change Password',
                        onTap: _changePassword,
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('Support'),
                    _SettingsCard(children: [
                      _NavRow(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Contact Us',
                        onTap: () => context.push('/contact'),
                      ),
                      const _RowDivider(),
                      _NavRow(
                        icon: Icons.info_outline_rounded,
                        label: 'About RoomzyFind',
                        onTap: () => context.push('/about'),
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('Account'),
                    _SettingsCard(children: [
                      _NavRow(
                        icon: Icons.logout_rounded,
                        label: 'Log Out',
                        color: _kOrange,
                        onTap: _logout,
                      ),
                      const _RowDivider(),
                      _NavRow(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete Account',
                        color: _kRed,
                        onTap: _deleteAccount,
                      ),
                    ]),
                  ],
                ),
                if (_busy)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ─── Shared small widgets ──────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: _kTextMuted,
                letterSpacing: 0.4)),
      );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(children: children),
      );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 58, color: _kBorder);
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _kPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: _kDark)),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: _kTextDim)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _kPrimary,
          ),
        ]),
      );
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = _kDark,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: color == _kDark ? _kDark : color)),
            ),
            Icon(Icons.chevron_right_rounded, color: _kTextDim, size: 20),
          ]),
        ),
      );
}
