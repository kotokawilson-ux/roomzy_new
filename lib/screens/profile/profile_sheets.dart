// lib/profile/profile_sheets.dart
// ─────────────────────────────────────────────────────────────────────────────
// showEditProfileSheet  — bottom sheet for editing name / phone / university /
//                         student ID / emergency contact
// showReferralSheet     — bottom sheet displaying the user's referral code
// showConfirmDialog     — reusable confirm / destructive alert dialog
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'profile_constants.dart';
import 'profile_widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  showEditProfileSheet
// ══════════════════════════════════════════════════════════════════════════════
Future<void> showEditProfileSheet(
  BuildContext context, {
  required String uid,
  required Map<String, dynamic> data,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditProfileSheet(uid: uid, data: data),
  );
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.uid, required this.data});

  final String uid;
  final Map<String, dynamic> data;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _uniCtrl;
  late final TextEditingController _studentIdCtrl;
  late final TextEditingController _emergencyCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _nameCtrl = TextEditingController(text: d['name'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: d['phone'] as String? ?? '');
    _uniCtrl = TextEditingController(text: d['university'] as String? ?? '');
    _studentIdCtrl =
        TextEditingController(text: d['studentId'] as String? ?? '');
    _emergencyCtrl =
        TextEditingController(text: d['emergencyContact'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _uniCtrl.dispose();
    _studentIdCtrl.dispose();
    _emergencyCtrl.dispose();
    super.dispose();
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set(
        {
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'university': _uniCtrl.text.trim(),
          'studentId': _studentIdCtrl.text.trim(),
          'emergencyContact': _emergencyCtrl.text.trim(),
        },
        SetOptions(merge: true),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Save failed. Please try again.'),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      debugPrint('Edit profile save error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text('Edit Profile', style: KText.labelLg),
            const SizedBox(height: 20),

            _KField(
              controller: _nameCtrl,
              label: 'Full Name',
              icon: Icons.person_outline_rounded,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),

            _KField(
              controller: _phoneCtrl,
              label: 'Phone Number',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 14),

            _KField(
              controller: _uniCtrl,
              label: 'University',
              icon: Icons.school_outlined,
            ),
            const SizedBox(height: 14),

            _KField(
              controller: _studentIdCtrl,
              label: 'Student ID',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 14),

            _KField(
              controller: _emergencyCtrl,
              label: 'Emergency Contact',
              icon: Icons.emergency_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 24),

            KButton(
              label: _saving ? 'Saving…' : 'Save Changes',
              onTap: _saving ? null : _save,
              loading: _saving,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet text field ─────────────────────────────────────────────────────────
class _KField extends StatelessWidget {
  const _KField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard,
    this.validator,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        validator: validator,
        style: const TextStyle(
          color: kTextPrimary,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: kTextSecondary, fontSize: 14),
          prefixIcon: Icon(icon, color: kTeal, size: 20),
          filled: true,
          fillColor: kBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kTeal, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kRed, width: 1.5),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  showReferralSheet
// ══════════════════════════════════════════════════════════════════════════════
Future<void> showReferralSheet(
  BuildContext context, {
  required String referralCode,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReferralSheet(referralCode: referralCode),
  );
}

class _ReferralSheet extends StatelessWidget {
  const _ReferralSheet({required this.referralCode});

  final String referralCode;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Referral code copied!',
            style: TextStyle(color: Colors.white)),
        backgroundColor: kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Icon
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kTealLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.card_giftcard_rounded,
                  color: kTeal, size: 32),
            ),
            const SizedBox(height: 16),

            Text('Refer a Friend', style: KText.labelLg),
            const SizedBox(height: 8),
            Text(
              'Share your code and earn loyalty points\nfor every friend who signs up.',
              style: KText.bodyXS,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Code display + copy button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    referralCode,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: kTeal,
                      letterSpacing: 4,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _copy(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kTealLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.copy_rounded,
                          color: kTeal, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            KButton(
              label: 'Done',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  showConfirmDialog
// ══════════════════════════════════════════════════════════════════════════════
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
  bool isDestructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: KText.labelLg),
      content: Text(message, style: KText.bodyXS),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: TextStyle(color: kTextSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmText,
            style: TextStyle(
              color: isDestructive ? kRed : kTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
