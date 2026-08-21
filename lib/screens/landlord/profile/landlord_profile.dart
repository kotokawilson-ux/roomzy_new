// lib/screens/landlord/profile/landlord_profile.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Landlord Profile & Settings Screen
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/landlord_service.dart';
import '../../../models/models.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';
const _kCloudName = 'dfv9yibba';
const _kUploadPreset = 'ml_default';

Future<String?> _pickAndUploadProfilePhoto() async {
  final picker = ImagePicker();
  final XFile? picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
  );
  if (picked == null) return null;

  final Uint8List bytes = await picked.readAsBytes();
  final String filename = picked.name.isNotEmpty
      ? picked.name
      : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_kCloudName/image/upload',
  );

  final req = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _kUploadPreset
    ..fields['folder'] = 'landlords/profiles'
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

  try {
    final res = await req.send();
    final body = await res.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (res.statusCode == 200) return json['secure_url'] as String?;
    return null;
  } catch (_) {
    return null;
  }
}

class _PayoutSection extends StatefulWidget {
  const _PayoutSection({required this.landlordId});
  final String landlordId;

  @override
  State<_PayoutSection> createState() => _PayoutSectionState();
}

class _PayoutSectionState extends State<_PayoutSection> {
  final _accountNumber = TextEditingController();
  final _businessName = TextEditingController();
  String _provider = 'MTN';
  bool _saving = false;
  bool _hasPayout = false;
  String? _savedAccount;

  final _providers = ['MTN', 'Vodafone', 'AirtelTigo'];

  // Paystack bank codes for mobile money
  String get _bankCode => switch (_provider) {
        'MTN' => 'MTN',
        'Vodafone' => 'VOD',
        _ => 'ATL',
      };

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final doc = await FirebaseFirestore.instance
        .collection('landlords')
        .doc(widget.landlordId)
        .get();
    if (!mounted) return;
    final data = doc.data();
    final subaccount = data?['paystack_subaccount'];
    final account = data?['payout_account_number']?.toString() ?? '';
    setState(() {
      _hasPayout = subaccount != null && subaccount.toString().isNotEmpty;
      _savedAccount = account.isNotEmpty ? account : null;
    });
  }

  Future<void> _save() async {
    if (_accountNumber.text.trim().isEmpty ||
        _businessName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill in all fields'),
        backgroundColor: _C.red,
      ));
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await http.post(
        Uri.parse('$_kBackendUrl/create-subaccount'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'landlordId': widget.landlordId,
          'businessName': _businessName.text.trim(),
          'bankCode': _bankCode,
          'accountNumber': _accountNumber.text.trim(),
          'percentageCharge': 5,
        }),
      );

      final data = jsonDecode(res.body);

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      if (!mounted) return;
      setState(() {
        _hasPayout = true;
        _savedAccount = _accountNumber.text.trim();
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Payout account saved successfully'),
        backgroundColor: _C.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: _C.red,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _accountNumber.dispose();
    _businessName.dispose();
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
            const Icon(Icons.account_balance_wallet_outlined,
                size: 16, color: _C.green),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Payout Account',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _C.textDark)),
            ),
            if (_hasPayout)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _C.greenFaint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _C.greenLight),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded, size: 12, color: _C.green),
                  SizedBox(width: 4),
                  Text('Active',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _C.green)),
                ]),
              ),
          ]),
        ),
        const Divider(height: 20, color: _C.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_hasPayout && _savedAccount != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _C.greenFaint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.greenLight),
                ),
                child: Row(children: [
                  const Icon(Icons.phone_android_rounded,
                      size: 16, color: _C.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Current payout number',
                              style:
                                  TextStyle(fontSize: 11, color: _C.textLight)),
                          Text(_savedAccount!,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _C.textDark)),
                        ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              const Text('Update payout account:',
                  style: TextStyle(fontSize: 12, color: _C.textLight)),
              const SizedBox(height: 10),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: Color(0xFFEA580C)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Set up your payout account so students can pay you directly through the app.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFEA580C),
                              height: 1.5),
                        ),
                      ),
                    ]),
              ),
              const SizedBox(height: 14),
            ],

            // Business name
            const Text('Business / Full Name',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textLight)),
            const SizedBox(height: 6),
            TextField(
              controller: _businessName,
              style: const TextStyle(fontSize: 13, color: _C.textDark),
              decoration: InputDecoration(
                hintText: 'Your name or business name',
                hintStyle: const TextStyle(fontSize: 13, color: _C.textMuted),
                prefixIcon: const Icon(Icons.person_outline_rounded,
                    size: 17, color: _C.green),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _C.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _C.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _C.green, width: 1.5)),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
              ),
            ),
            const SizedBox(height: 12),

            // Provider selector
            const Text('Mobile Money Network',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textLight)),
            const SizedBox(height: 8),
            Row(
              children: _providers.map((p) {
                final selected = _provider == p;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _provider = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin:
                          EdgeInsets.only(right: p != _providers.last ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            selected ? _C.greenFaint : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? _C.green : _C.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(p,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? _C.green : _C.textLight)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Account number
            const Text('Mobile Money Number',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textLight)),
            const SizedBox(height: 6),
            TextField(
              controller: _accountNumber,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 13, color: _C.textDark),
              decoration: InputDecoration(
                hintText: '024XXXXXXX',
                hintStyle: const TextStyle(fontSize: 13, color: _C.textMuted),
                prefixIcon: const Icon(Icons.phone_android_rounded,
                    size: 17, color: _C.green),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _C.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _C.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _C.green, width: 1.5)),
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
                label: Text(
                  _saving
                      ? 'Saving…'
                      : _hasPayout
                          ? 'Update Payout Account'
                          : 'Save Payout Account',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
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

// ─────────────────────────────────────────────────────────────
// EDIT PROFILE SECTION (name / phone / address)
class _EditProfileSection extends StatefulWidget {
  const _EditProfileSection({
    required this.landlordId,
    required this.authService,
    required this.onSaved,
  });

  final String landlordId;
  final AuthService authService;
  final VoidCallback onSaved;

  @override
  State<_EditProfileSection> createState() => _EditProfileSectionState();
}

class _EditProfileSectionState extends State<_EditProfileSection> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _profileImage = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance
        .collection('landlords')
        .doc(widget.landlordId)
        .get();
    if (!mounted) return;
    final d = doc.data();
    _name.text = d?['full_name']?.toString() ?? '';
    _phone.text = d?['phone']?.toString() ?? '';
    _address.text = d?['address']?.toString() ?? '';
    _profileImage.text = d?['profile_image']?.toString() ?? '';
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _profileImage.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      final url = await _pickAndUploadProfilePhoto();
      if (url != null) {
        await FirebaseFirestore.instance
            .collection('landlords')
            .doc(widget.landlordId)
            .update({'profile_image': url});
        if (!mounted) return;
        setState(() => _profileImage.text = url);
        widget.onSaved();
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Name and phone are required'),
        backgroundColor: _C.red,
      ));
      return;
    }
    setState(() => _saving = true);
    final result = await widget.authService.updateLandlordProfile(
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.success) widget.onSaved();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          result.success ? 'Profile updated' : result.error ?? 'Update failed'),
      backgroundColor: result.success ? _C.green : _C.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: const Center(
            child: CircularProgressIndicator(color: _C.green, strokeWidth: 2)),
      );
    }
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
            const Expanded(
              child: Text('Edit Profile',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _C.textDark)),
            ),
          ]),
        ),
        const Divider(height: 20, color: _C.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _C.greenFaint,
                          border: Border.all(color: _C.greenLight, width: 2),
                        ),
                        child: ClipOval(
                          child: _profileImage.text.trim().isNotEmpty
                              ? Image.network(_profileImage.text.trim(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      color: _C.green,
                                      size: 32))
                              : const Icon(Icons.person,
                                  color: _C.green, size: 32),
                        ),
                      ),
                      GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickPhoto,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _uploadingPhoto
                                ? Colors.grey.shade400
                                : _C.green,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: _uploadingPhoto
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
                  const SizedBox(height: 6),
                  Text(
                    _uploadingPhoto ? 'Uploading…' : 'Tap to change photo',
                    style: TextStyle(
                        fontSize: 11,
                        color: _uploadingPhoto ? _C.green : _C.textLight),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ProfileField(
                label: 'Full Name',
                controller: _name,
                icon: Icons.person_outline_rounded),
            const SizedBox(height: 12),
            _ProfileField(
                label: 'Phone',
                controller: _phone,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _ProfileField(
                label: 'Address',
                controller: _address,
                icon: Icons.location_on_outlined),
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
                label: Text(_saving ? 'Saving…' : 'Save Changes',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
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

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _C.textLight)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 13, color: _C.textDark),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 17, color: _C.green),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.green, width: 1.5)),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
// SECURITY SECTION (change email / password / forgot password)
// ─────────────────────────────────────────────────────────────
class _SecuritySection extends StatelessWidget {
  const _SecuritySection(
      {required this.authService, required this.currentEmail});
  final AuthService authService;
  final String? currentEmail;

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
            const Expanded(
              child: Text('Login & Security',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _C.textDark)),
            ),
          ]),
        ),
        const Divider(height: 20, color: _C.border),
        _SettingsTile(
          icon: Icons.email_outlined,
          label: 'Change Email',
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ChangeEmailDialog(
                authService: authService, currentEmail: currentEmail ?? ''),
          ),
        ),
        _SettingsTile(
          icon: Icons.lock_outline_rounded,
          label: 'Change Password',
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ChangePasswordDialog(
                authService: authService, currentEmail: currentEmail ?? ''),
          ),
        ),
        const SizedBox(height: 4),
      ]),
    );
  }
}

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
  Key _futureKey = UniqueKey();

  void _refreshProfile() => setState(() => _futureKey = UniqueKey());

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
        key: _futureKey,
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
                _PayoutSection(landlordId: widget.landlordId),
                const SizedBox(height: 16),
                _EditProfileSection(
                  landlordId: widget.landlordId,
                  authService: widget.authService,
                  onSaved: _refreshProfile,
                ),
                const SizedBox(height: 16),
                _SecuritySection(
                  authService: widget.authService,
                  currentEmail: landlord.email,
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
