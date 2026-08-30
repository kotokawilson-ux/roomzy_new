// lib/screens/admin/profile/admin_profile.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Admin Profile & Settings Screen
// ─────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/auth_service.dart';

// ── Colour tokens (mirrors landlord profile) ────────────────────
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
  static const purple = Color(0xFF7C3AED);
  static const purpleFaint = Color(0xFFF3EEFE);
}

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({
    super.key,
    required this.uid,
    required this.authService,
  });

  final String uid;
  final AuthService authService;

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _signingOut = false;
  Key _futureKey = UniqueKey();

  void _refresh() => setState(() => _futureKey = UniqueKey());

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out',
            style: TextStyle(fontWeight: FontWeight.w700, color: _C.textDark)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(fontSize: 13, color: _C.textLight)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _C.red, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    await widget.authService.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        elevation: 0,
        title: const Text('My Profile',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _C.border),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _C.green));
          }
          final data = snap.data?.data() as Map<String, dynamic>?;
          final username = data?['username']?.toString() ?? '';
          final email = data?['email']?.toString() ?? '';
          final role = data?['role']?.toString() ?? 'admin';
          final photoUrl = data?['photoUrl']?.toString();
          final isSuperAdmin = role == 'super_admin';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              _AdminAvatarCard(
                uid: widget.uid,
                username: username,
                email: email,
                photoUrl: photoUrl,
                isSuperAdmin: isSuperAdmin,
              ),
              const SizedBox(height: 20),
              _EditAdminProfileSection(
                uid: widget.uid,
                initialUsername: username,
                onSaved: _refresh,
              ),
              const SizedBox(height: 16),
              _AdminSecuritySection(
                authService: widget.authService,
                currentEmail: email,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _signingOut ? null : _signOut,
                  icon: _signingOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.logout_rounded, size: 16),
                  label: Text(_signingOut ? 'Signing out…' : 'Sign Out'),
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
              const Text('RoomzyFind v1.0.0',
                  style: TextStyle(fontSize: 11, color: _C.textMuted)),
              const SizedBox(height: 32),
            ]),
          );
        },
      ),
    );
  }
}

// ── Avatar card ──────────────────────────────────────────────
class _AdminAvatarCard extends StatefulWidget {
  const _AdminAvatarCard({
    required this.uid,
    required this.username,
    required this.email,
    required this.photoUrl,
    required this.isSuperAdmin,
  });
  final String uid;
  final String username;
  final String email;
  final String? photoUrl;
  final bool isSuperAdmin;

  @override
  State<_AdminAvatarCard> createState() => _AdminAvatarCardState();
}

class _AdminAvatarCardState extends State<_AdminAvatarCard> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 400,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final filename = picked.name.isNotEmpty
          ? picked.name
          : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final uri =
          Uri.parse('https://api.cloudinary.com/v1_1/dfv9yibba/image/upload');
      final req = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = 'ml_default'
        ..fields['folder'] = 'avatars'
        ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final res = await req.send();
      final body = await res.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (res.statusCode == 200 && json['secure_url'] != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .update({'photoUrl': json['secure_url']});
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Photo upload failed: $e'), backgroundColor: _C.red));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.username.trim().isNotEmpty
        ? widget.username.trim()[0].toUpperCase()
        : '?';
    final hasPhoto = widget.photoUrl != null && widget.photoUrl!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _C.greenFaint,
                shape: BoxShape.circle,
                border: Border.all(color: _C.greenLight, width: 2),
              ),
              child: ClipOval(
                child: hasPhoto
                    ? Image.network(
                        widget.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(initials,
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: _C.green)),
                        ),
                      )
                    : Center(
                        child: Text(initials,
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: _C.green)),
                      ),
              ),
            ),
            GestureDetector(
              onTap: _uploading ? null : _pickAndUpload,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _uploading ? Colors.grey.shade400 : _C.green,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: _uploading
                    ? const Padding(
                        padding: EdgeInsets.all(5),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.camera_alt_rounded,
                        size: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(widget.username,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: _C.textDark)),
        const SizedBox(height: 4),
        Text(widget.email,
            style: const TextStyle(fontSize: 13, color: _C.textLight)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isSuperAdmin ? _C.purpleFaint : _C.greenFaint,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: widget.isSuperAdmin ? _C.purple : _C.greenLight),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                widget.isSuperAdmin
                    ? Icons.shield_rounded
                    : Icons.person_rounded,
                size: 14,
                color: widget.isSuperAdmin ? _C.purple : _C.green),
            const SizedBox(width: 6),
            Text(widget.isSuperAdmin ? 'Super Admin' : 'Admin',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.isSuperAdmin ? _C.purple : _C.green)),
          ]),
        ),
      ]),
    );
  }
}

// ── Edit username ────────────────────────────────────────────
class _EditAdminProfileSection extends StatefulWidget {
  const _EditAdminProfileSection({
    required this.uid,
    required this.initialUsername,
    required this.onSaved,
  });
  final String uid;
  final String initialUsername;
  final VoidCallback onSaved;

  @override
  State<_EditAdminProfileSection> createState() =>
      _EditAdminProfileSectionState();
}

class _EditAdminProfileSectionState extends State<_EditAdminProfileSection> {
  late final _username = TextEditingController(text: widget.initialUsername);
  bool _saving = false;

  Future<void> _save() async {
    final value = _username.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Username cannot be empty'), backgroundColor: _C.red));
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({'username': value});
      if (!mounted) return;
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated'), backgroundColor: _C.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _C.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 16, color: _C.green),
            const SizedBox(width: 8),
            const Text('Edit Profile',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _C.textDark)),
          ]),
        ),
        const Divider(height: 20, color: _C.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Username',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textLight)),
            const SizedBox(height: 6),
            TextField(
              controller: _username,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_outline_rounded,
                    size: 17, color: _C.green),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _C.border)),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded,
                        size: 16, color: Colors.white),
                label: Text(_saving ? 'Saving…' : 'Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Security section — reuses AuthService.changeEmail / changePassword /
// sendPasswordReset, same as the landlord side ──────────────────────────
class _AdminSecuritySection extends StatelessWidget {
  const _AdminSecuritySection(
      {required this.authService, required this.currentEmail});
  final AuthService authService;
  final String currentEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            const Icon(Icons.security_outlined, size: 16, color: _C.green),
            const SizedBox(width: 8),
            const Text('Login & Security',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _C.textDark)),
          ]),
        ),
        const Divider(height: 20, color: _C.border),
        InkWell(
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ChangeEmailDialog(
                authService: authService, currentEmail: currentEmail),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.email_outlined, size: 18, color: _C.textLight),
              SizedBox(width: 12),
              Expanded(
                  child: Text('Change Email', style: TextStyle(fontSize: 13))),
              Icon(Icons.chevron_right_rounded, size: 18, color: _C.textMuted),
            ]),
          ),
        ),
        InkWell(
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ChangePasswordDialog(
                authService: authService, currentEmail: currentEmail),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: _C.textLight),
              SizedBox(width: 12),
              Expanded(
                  child:
                      Text('Change Password', style: TextStyle(fontSize: 13))),
              Icon(Icons.chevron_right_rounded, size: 18, color: _C.textMuted),
            ]),
          ),
        ),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// ── Change Email Dialog ──────────────────────────────────────
class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog(
      {required this.authService, required this.currentEmail});
  final AuthService authService;
  final String currentEmail;

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _newEmail = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _newEmail.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_newEmail.text.trim().isEmpty || _password.text.trim().isEmpty) {
      setState(() => _error = 'Enter your new email and current password.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.authService.changeEmail(
      currentPassword: _password.text.trim(),
      newEmail: _newEmail.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.success) {
        _sent = true;
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Change Email',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark)),
      content: _sent
          ? Text(
              'We sent a confirmation link to ${_newEmail.text.trim()}. Open it to finish the change — your login email stays as ${widget.currentEmail} until then.',
              style: const TextStyle(fontSize: 13, color: _C.textLight),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current login email: ${widget.currentEmail}',
                    style: const TextStyle(fontSize: 12, color: _C.textLight)),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: _C.redLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!,
                        style: const TextStyle(fontSize: 12, color: _C.red)),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _newEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'New email', isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
            ),
      actions: _sent
          ? [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _C.green, foregroundColor: Colors.white),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _C.green, foregroundColor: Colors.white),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Send Confirmation'),
              ),
            ],
    );
  }
}

// ── Change Password Dialog ───────────────────────────────────
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog(
      {required this.authService, required this.currentEmail});
  final AuthService authService;
  final String currentEmail;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _resetSent = false;

  @override
  void dispose() {
    _current.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_current.text.trim().isEmpty || _newPass.text.trim().isEmpty) {
      setState(() => _error = 'Fill in both password fields.');
      return;
    }
    if (_newPass.text.trim().length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (_newPass.text.trim() != _confirm.text.trim()) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.authService.changePassword(
      currentPassword: _current.text.trim(),
      newPassword: _newPass.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password updated'),
        backgroundColor: _C.green,
      ));
    } else {
      setState(() => _error = result.error);
    }
  }

  Future<void> _forgotPassword() async {
    setState(() => _saving = true);
    final error =
        await widget.authService.sendPasswordReset(widget.currentEmail);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _resetSent = error == null;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Change Password',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_resetSent)
            Text(
                'Password reset email sent to ${widget.currentEmail}. Check your inbox.',
                style: const TextStyle(fontSize: 13, color: _C.green))
          else ...[
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: _C.redLight, borderRadius: BorderRadius.circular(8)),
                child: Text(_error!,
                    style: const TextStyle(fontSize: 12, color: _C.red)),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Current password', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newPass,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New password', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Confirm new password', isDense: true),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _saving ? null : _forgotPassword,
              child: const Text(
                  "Forgot your current password? Email me a reset link",
                  style: TextStyle(
                      fontSize: 12,
                      color: _C.green,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      actions: _resetSent
          ? [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _C.green, foregroundColor: Colors.white),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _C.green, foregroundColor: Colors.white),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Update'),
              ),
            ],
    );
  }
}
// ── These two dialogs are byte-for-byte the same logic as
// landlord_profile.dart's _ChangeEmailDialog / _ChangePasswordDialog.
// If you already have them as shared widgets, delete these and import
// those instead — otherwise paste the two classes from landlord_profile.dart
// here unchanged (they only depend on AuthService, not landlord-specific state).
