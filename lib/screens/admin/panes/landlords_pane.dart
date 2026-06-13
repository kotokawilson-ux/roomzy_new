import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../constants/admin_theme.dart';
import '../../../../utils/admin_helpers.dart';
import '../widgets/dialog_widgets.dart';
import '../widgets/form_widgets.dart';
import '../widgets/shared_widgets.dart';
import '../../../../services/activity_log_service.dart';
import '../../../../utils/activity_logger.dart';
import '../../../services/auth_service.dart';
// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

bool _isPhone(BuildContext context) => MediaQuery.of(context).size.width < 600;

double _dialogWidth(BuildContext context, {double maxPx = 560}) {
  final w = MediaQuery.of(context).size.width;
  if (w < 600) return w * 0.95;
  if (w < 900) return w * 0.80;
  return maxPx.clamp(0.0, w * 0.55);
}

double _dialogMaxHeight(BuildContext context) {
  final h = MediaQuery.of(context).size.height;
  return _isPhone(context) ? h * 0.92 : h * 0.85;
}

// ─────────────────────────────────────────────────────────────────────────────
// CLOUDINARY CONFIG
// ─────────────────────────────────────────────────────────────────────────────

const _kCloudName = 'dfv9yibba';
const _kUploadPreset = 'ml_default';

Future<String?> _pickAndUpload({String folder = 'landlords'}) async {
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
    ..fields['folder'] = folder
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

  try {
    final res = await req.send();
    final body = await res.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (res.statusCode == 200) return json['secure_url'] as String?;
    debugPrint('Cloudinary error [${res.statusCode}]: $body');
    return null;
  } catch (e) {
    debugPrint('_pickAndUpload exception: $e');
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE IMAGE PICKER WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileImagePicker extends StatefulWidget {
  const _ProfileImagePicker({
    required this.controller,
    required this.name,
  });

  final TextEditingController controller;
  final String name;

  @override
  State<_ProfileImagePicker> createState() => _ProfileImagePickerState();
}

class _ProfileImagePickerState extends State<_ProfileImagePicker> {
  bool _uploading = false;

  Future<void> _pick() async {
    setState(() => _uploading = true);
    try {
      final url = await _pickAndUpload(folder: 'landlords/profiles');
      if (url != null && mounted) {
        widget.controller.text = url;
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    final initials = widget.name.trim().isNotEmpty
        ? widget.name
            .trim()
            .split(' ')
            .where((e) => e.isNotEmpty)
            .take(2)
            .map((e) => e[0].toUpperCase())
            .join()
        : '?';

    return Center(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kGreen.withOpacity(0.10),
                  border: Border.all(color: kGreen, width: 2.5),
                ),
                child: ClipOval(
                  child: url.isNotEmpty
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                                  ? child
                                  : Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: kGreen)),
                          errorBuilder: (_, __, ___) =>
                              _InitialsAvatar(initials: initials),
                        )
                      : _InitialsAvatar(initials: initials),
                ),
              ),
              GestureDetector(
                onTap: _uploading ? null : _pick,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _uploading ? Colors.grey.shade400 : kGreen,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: _uploading
                      ? const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt_rounded,
                          size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _uploading
                ? 'Uploading…'
                : (url.isEmpty ? 'Tap to upload photo' : 'Tap to change photo'),
            style: TextStyle(
              fontSize: 11,
              color: _uploading ? kGreen : kTextLight,
              fontWeight: _uploading ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: kGreen,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDLORDS PANE
// ─────────────────────────────────────────────────────────────────────────────

class LandlordsPane extends StatefulWidget {
  const LandlordsPane({super.key});

  @override
  State<LandlordsPane> createState() => _LandlordsPaneState();
}

class _LandlordsPaneState extends State<LandlordsPane> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_isPhone(context) ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResponsiveHeader(
            title: 'All Landlords',
            search: _search,
            onSearch: (v) => setState(() => _search = v),
            onAdd: _openAdd,
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('landlords').orderBy('full_name').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const CardLoading(height: 200);
              }
              if (snap.hasError) {
                return EmptyCard(message: 'Error: ${snap.error}', height: 120);
              }

              // ✅ Explicitly typed list — fixes (dynamic)=>dynamic TypeError
              var docs = snap.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              if (_search.isNotEmpty) {
                final q = _search.toLowerCase();
                docs = docs.where((d) {
                  final data = d.data();
                  return <String>[
                    'full_name',
                    'email',
                    'phone',
                    'landlord_code',
                    'address',
                  ].any((k) =>
                      (data[k]?.toString() ?? '').toLowerCase().contains(q));
                }).toList();
              }

              if (docs.isEmpty) {
                return const EmptyCard(
                    message: 'No landlords found', height: 160);
              }

              return _ResponsiveGrid(
                itemCount: docs.length,
                itemBuilder: (i) => _LandlordCard(
                  doc: docs[i],
                  onEdit: () => _openEdit(docs[i]),
                  onDelete: () async {
                    final d = docs[i].data();
                    final name = d['full_name']?.toString() ?? 'Unknown';
                    await ActivityLogger.log(
                      action: 'Deleted Landlord',
                      details: 'Name: $name, Email: ${d['email'] ?? 'Unknown'}',
                    );
                    confirmDelete(context, 'landlords', docs[i].id);
                  },
                  onViewHostels: () => _showHostelsSheet(context, docs[i]),
                ),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _openAdd() => showDialog(
        context: context,
        builder: (_) => _LandlordDialog(parentContext: context),
      );

  void _openEdit(QueryDocumentSnapshot<Map<String, dynamic>> doc) => showDialog(
        context: context,
        builder: (_) => _LandlordDialog(doc: doc, parentContext: context),
      );

  void _showHostelsSheet(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LandlordHostelsSheet(
        landlordId: doc.id,
        landlordName: d['full_name']?.toString() ?? 'Landlord',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _ResponsiveHeader extends StatelessWidget {
  const _ResponsiveHeader({
    required this.title,
    required this.search,
    required this.onSearch,
    required this.onAdd,
  });

  final String title;
  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;

      if (w < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            const SizedBox(height: 10),
            SearchBox(value: search, onChanged: onSearch),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: _AddBtn(onTap: onAdd)),
          ],
        );
      }

      if (w < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: SearchBox(value: search, onChanged: onSearch)),
              const SizedBox(width: 8),
              _AddBtn(onTap: onAdd),
            ]),
          ],
        );
      }

      return Row(children: [
        Expanded(child: SectionLabel(title)),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: 120, maxWidth: w < 800 ? 180 : 260),
          child: SearchBox(value: search, onChanged: onSearch),
        ),
        const SizedBox(width: 12),
        _AddBtn(onTap: onAdd),
      ]);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE GRID
// ─────────────────────────────────────────────────────────────────────────────

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final int cols = w < 560 ? 1 : (w < 900 ? 2 : 3);
      const double gap = 16;
      final cardW = (w - gap * (cols - 1)) / cols;

      final rows = <Widget>[];
      for (var i = 0; i < itemCount; i += cols) {
        final rowChildren = <Widget>[];
        for (var j = 0; j < cols; j++) {
          if (j > 0) rowChildren.add(const SizedBox(width: gap));
          if (i + j < itemCount) {
            rowChildren.add(SizedBox(width: cardW, child: itemBuilder(i + j)));
          } else {
            rowChildren.add(SizedBox(width: cardW));
          }
        }
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowChildren,
        ));
      }

      return Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) const SizedBox(height: gap),
          ],
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDLORD CARD
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordCard extends StatelessWidget {
  const _LandlordCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
    required this.onViewHostels,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewHostels;

  @override
  Widget build(BuildContext context) {
    // ✅ No cast needed — already typed
    final d = doc.data();

    final name = d['full_name']?.toString() ?? '—';
    final code = (d['landlord_code']?.toString().isNotEmpty == true)
        ? d['landlord_code'].toString()
        : 'N/A';
    final email = d['email']?.toString() ?? '—';
    final phone = d['phone']?.toString() ?? '—';
    final address = (d['address']?.toString().isNotEmpty == true)
        ? d['address'].toString()
        : 'N/A';
    final profileUrl = d['profile_image']?.toString() ?? '';
    final registeredAt = d['registered_at'];
    String registeredStr = '—';
    if (registeredAt is Timestamp) {
      registeredStr = DateFormat('dd MMM yyyy').format(registeredAt.toDate());
    }

    final initials = name.trim().isNotEmpty
        ? name
            .trim()
            .split(' ')
            .where((e) => e.isNotEmpty)
            .take(2)
            .map((e) => e[0].toUpperCase())
            .join()
        : '?';

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Profile header strip ──
          Container(
            decoration: BoxDecoration(
              color: kGreen.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: kBorder)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGreen.withOpacity(0.12),
                    border: Border.all(color: kGreen, width: 2),
                  ),
                  child: ClipOval(
                    child: profileUrl.isNotEmpty
                        ? Image.network(
                            profileUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _CardInitials(initials: initials),
                          )
                        : _CardInitials(initials: initials),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: kGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Info rows ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoRow(
                    icon: Icons.email_outlined, label: 'Email', value: email),
                _InfoRow(
                    icon: Icons.phone_outlined, label: 'Phone', value: phone),
                _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: address),
                _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Registered',
                    value: registeredStr),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    _CardBtn(
                      icon: Icons.apartment_rounded,
                      label: 'Hostels',
                      color: Colors.blue,
                      onTap: onViewHostels,
                    ),
                    _CardBtn(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      color: Colors.orange,
                      onTap: onEdit,
                    ),
                    _CardBtn(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardInitials extends StatelessWidget {
  const _CardInitials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kGreen,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDLORD DIALOG  ── tabbed: Personal · Photo
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordDialog extends StatefulWidget {
  const _LandlordDialog({this.doc, required this.parentContext});
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  final BuildContext parentContext;

  @override
  State<_LandlordDialog> createState() => _LandlordDialogState();
}

class _LandlordDialogState extends State<_LandlordDialog>
    with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _profileImage = TextEditingController();
  final _password = TextEditingController();

  late final TabController _tabs;
  bool _saving = false;
  bool _obscurePassword = true;
  String? _validationError;
// Add this state variable at the top of _LandlordDialogState
  bool _creatingAuth = false;
  String? _authSuccess;
  bool get _isEdit => widget.doc != null;
// Payout fields
  final _payoutName = TextEditingController();
  final _payoutNumber = TextEditingController();
  String _payoutProvider = 'MTN';
  bool _payoutSaving = false;
  bool _payoutHasAccount = false;
  String? _payoutSubaccount;

  static const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';
  static const _payoutProviders = ['MTN', 'Vodafone', 'AirtelTigo'];

  String get _bankCode => switch (_payoutProvider) {
        'MTN' => 'MTN',
        'Vodafone' => 'VOD',
        _ => 'ATL',
      };
  @override
  void initState() {
    super.initState();
    // 3 tabs: Personal · Photo · Credentials
    _tabs = TabController(length: 4, vsync: this);
    if (_isEdit) {
      final d = widget.doc!.data();
      _name.text = d['full_name']?.toString() ?? '';
      _email.text = d['email']?.toString() ?? '';
      _phone.text = d['phone']?.toString() ?? '';
      _address.text = d['address']?.toString() ?? '';
      _code.text = d['landlord_code']?.toString() ?? '';
      _profileImage.text = d['profile_image']?.toString() ?? '';
    }
    _name.addListener(_genCode);
    _phone.addListener(_genCode);
    _name.addListener(() => setState(() {}));
    // Keep Credentials tab email preview in sync
    _email.addListener(() => setState(() {}));
    if (_isEdit) {
      final d = widget.doc!.data();
      _payoutName.text = d['payout_business_name']?.toString() ?? '';
      _payoutNumber.text = d['payout_account_number']?.toString() ?? '';
      _payoutSubaccount = d['paystack_subaccount']?.toString();
      _payoutHasAccount = _payoutSubaccount?.isNotEmpty == true;
      final code = d['payout_bank_code']?.toString() ?? 'MTN';
      _payoutProvider = code == 'VOD'
          ? 'Vodafone'
          : code == 'ATL'
              ? 'AirtelTigo'
              : 'MTN';
    }
  }

  void _genCode() {
    if (_isEdit) return;
    final n = _name.text.trim().replaceAll(' ', '').toUpperCase();
    final p = _phone.text.trim();
    if (n.isNotEmpty && p.length >= 3) {
      _code.text = '$n-${p.substring(p.length - 3)}';
    } else if (n.isNotEmpty) {
      _code.text = n.length > 6 ? n.substring(0, 6) : n;
    } else {
      _code.text = '';
    }
    setState(() {});
  }

  Future<void> _savePayout(String landlordId) async {
    if (_payoutName.text.trim().isEmpty || _payoutNumber.text.trim().isEmpty) {
      setState(() =>
          _validationError = 'Business name and MoMo number are required.');
      return;
    }
    setState(() => _payoutSaving = true);
    try {
      // ── Read the landlord's commission rate ──────────────────────────────
      double commissionRate = 5.0; // fallback
      try {
        final landlordDoc = await FirebaseFirestore.instance
            .collection('landlords')
            .doc(landlordId)
            .get();
        final landlordCustomRate =
            (landlordDoc.data()?['commission_percent'] as num?)?.toDouble();

        if (landlordCustomRate != null) {
          commissionRate = landlordCustomRate;
        } else {
          final settingsDoc = await FirebaseFirestore.instance
              .collection('settings')
              .doc('platform')
              .get();
          commissionRate =
              (settingsDoc.data()?['commission_percent'] as num?)?.toDouble() ??
                  5.0;
        }
      } catch (_) {
        // fallback to 5 if fetch fails
      }

      final res = await http.post(
        Uri.parse('$_kBackendUrl/create-subaccount'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'landlordId': landlordId,
          'businessName': _payoutName.text.trim(),
          'bankCode': _bankCode,
          'accountNumber': _payoutNumber.text.trim(),
          'percentageCharge': commissionRate, // ← dynamic now
        }),
      );
      final data = jsonDecode(res.body);
      if (data['error'] != null) throw Exception(data['error']);
      if (mounted) {
        setState(() {
          _payoutHasAccount = true;
          _payoutSubaccount = data['subaccountCode'];
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payout account saved'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _validationError = 'Payout error: $e');
      }
    } finally {
      if (mounted) setState(() => _payoutSaving = false);
    }
  }

  Future<void> _save() async {
    // Build validation errors
    final missing = <String>[
      if (_name.text.trim().isEmpty) 'Full Name',
      if (_email.text.trim().isEmpty) 'Email',
      if (_phone.text.trim().isEmpty) 'Phone',
      if (!_isEdit && _password.text.trim().isEmpty) 'Password',
      if (!_isEdit &&
          _password.text.trim().isNotEmpty &&
          _password.text.trim().length < 6)
        'Password (min 6 characters)',
    ];

    if (missing.isNotEmpty) {
      setState(() => _validationError = 'Required: ${missing.join(', ')}');
      return;
    }

    setState(() {
      _saving = true;
      _validationError = null;
    });

    final data = <String, dynamic>{
      'full_name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'landlord_code': _code.text.trim(),
      'profile_image': _profileImage.text.trim(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEdit) {
        // ── EDIT: update Firestore only ──────────────────────────────
        await db.collection('landlords').doc(widget.doc!.id).update(data);
        await ActivityLogger.log(
          action: 'Updated Landlord',
          details: 'Name: ${_name.text.trim()}, Email: ${_email.text.trim()}',
        );
      } else {
        // ── ADD: Firestore doc first, then Firebase Auth account ─────
        data['registered_at'] = FieldValue.serverTimestamp();
        final docRef = await db.collection('landlords').add(data);

        // Create the Firebase Auth account via AuthService secondary app
        // ✅ Use the Provider instance
        final result = await context.read<AuthService>().createLandlordAccount(
              landlordDocId: docRef.id,
              fullName: _name.text.trim(),
              email: _email.text.trim(),
              phone: _phone.text.trim(),
              password: _password.text.trim(),
              landlordCode: _code.text.trim(),
            );

        if (!result.success) {
          // Auth failed — roll back the Firestore doc so no orphan is left
          await docRef.delete();
          if (!mounted) return;
          setState(() {
            _saving = false;
            _validationError =
                result.error ?? 'Failed to create login account.';
          });
          return;
        }

        await ActivityLogger.log(
          action: 'Created Landlord',
          details: 'Name: ${_name.text.trim()}, Email: ${_email.text.trim()}',
        );
      }

      if (!mounted) return;
      final parentCtx = widget.parentContext;
      final message = _isEdit
          ? 'Landlord Updated Successfully!'
          : 'Landlord Account Created Successfully!';
      Navigator.of(context).pop();
      _showSuccessToast(parentCtx, message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationError = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dw = _dialogWidth(context, maxPx: 500);
    final dh = _dialogMaxHeight(context);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: _isPhone(context) ? 8 : 24,
        vertical: _isPhone(context) ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: SizedBox(
        width: dw,
        height: dh,
        child: Column(
          children: [
            _DialogHeader(
              icon: Icons.person_outline_rounded,
              title: _isEdit ? 'Edit Landlord' : 'Add Landlord',
              subtitle: _isEdit
                  ? 'Update landlord details'
                  : 'Register a new landlord',
              iconColor: kGreen,
            ),
            _DialogTabBar(
              controller: _tabs,
              tabs: const [
                Tab(
                  icon: Icon(Icons.person_rounded, size: 16),
                  text: 'Personal',
                ),
                Tab(
                  icon: Icon(Icons.photo_camera_outlined, size: 16),
                  text: 'Photo',
                ),
                Tab(
                  icon: Icon(Icons.lock_outline_rounded, size: 16),
                  text: 'Credentials',
                ),
                Tab(
                  icon: Icon(Icons.account_balance_wallet_outlined, size: 16),
                  text: 'Payout',
                ),
              ],
            ),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _ValidationBanner(_validationError!),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // ── Tab 1: Personal Info ─────────────────────────────
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          icon: Icons.badge_outlined,
                          label: 'Personal information',
                        ),
                        _FormField(
                          label: 'Full name',
                          required: true,
                          icon: Icons.person_outline,
                          controller: _name,
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          label: 'Email address',
                          required: true,
                          icon: Icons.email_outlined,
                          controller: _email,
                          keyboard: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          label: 'Phone number',
                          required: true,
                          icon: Icons.phone_outlined,
                          controller: _phone,
                          keyboard: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          label: 'Address',
                          icon: Icons.location_on_outlined,
                          controller: _address,
                        ),
                        const SizedBox(height: 16),
                        _SectionLabel(
                          icon: Icons.tag_rounded,
                          label: 'Auto-generated code',
                        ),
                        _ReadOnlyCodeField(
                          label: 'Landlord code',
                          value: _code.text.isEmpty ? '—' : _code.text,
                        ),
                        if (!_isEdit) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Generated from name + last 3 digits of phone.',
                            style: TextStyle(fontSize: 11, color: kTextLight),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Tab 2: Photo ─────────────────────────────────────
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          icon: Icons.photo_camera_outlined,
                          label: 'Profile photo',
                        ),
                        _ProfileImagePicker(
                          controller: _profileImage,
                          name: _name.text,
                        ),
                        const SizedBox(height: 16),
                        _InfoNote(
                          icon: Icons.info_outline_rounded,
                          text:
                              'Photo is stored securely and only visible to admins.',
                        ),
                      ],
                    ),
                  ),

                  // ── Tab 3: Credentials ───────────────────────────────
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          icon: Icons.lock_outline_rounded,
                          label: 'Login credentials',
                        ),

                        // Read-only email mirror from tab 1
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Login email',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kTextLight,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: kSurfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: kBorder),
                              ),
                              child: Row(children: [
                                Icon(Icons.email_outlined,
                                    size: 14, color: kTextLight),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _email.text.trim().isEmpty
                                        ? 'Fill in Email on Personal tab first'
                                        : _email.text.trim(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _email.text.trim().isEmpty
                                          ? kTextLight
                                          : kTextDark,
                                      fontStyle: _email.text.trim().isEmpty
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Password field
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(
                                _isEdit ? 'New password' : 'Password',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kTextLight,
                                ),
                              ),
                              if (!_isEdit) ...[
                                const SizedBox(width: 3),
                                const Text('*',
                                    style: TextStyle(
                                        color: Colors.red, fontSize: 12)),
                              ],
                              if (_isEdit) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(leave blank to keep current)',
                                  style: TextStyle(
                                      fontSize: 10, color: kTextLight),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 5),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscurePassword,
                              style: const TextStyle(
                                  fontSize: 13, color: kTextDark),
                              decoration: InputDecoration(
                                hintText: _isEdit
                                    ? 'Enter new password (optional)'
                                    : 'Min. 6 characters',
                                hintStyle:
                                    TextStyle(fontSize: 12, color: kTextLight),
                                prefixIcon: Icon(Icons.lock_outline,
                                    size: 16, color: kTextLight),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 16,
                                    color: kTextLight,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: kBorder)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: kBorder)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: kGreen, width: 1.5)),
                                filled: true,
                                fillColor: kSurface,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        _InfoNote(
                          icon: Icons.info_outline_rounded,
                          text: _isEdit
                              ? 'Leave the password blank to keep the landlord\'s existing password unchanged.'
                              : 'The landlord will use this email and password to log into the app.',
                        ),
                        if (_isEdit) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _creatingAuth
                                  ? null
                                  : () async {
                                      if (_email.text.trim().isEmpty ||
                                          _password.text.trim().isEmpty) {
                                        setState(() => _validationError =
                                            'Email and password are required.');
                                        return;
                                      }
                                      if (_password.text.trim().length < 6) {
                                        setState(() => _validationError =
                                            'Password must be at least 6 characters.');
                                        return;
                                      }
                                      setState(() {
                                        _creatingAuth = true;
                                        _validationError = null;
                                        _authSuccess = null;
                                      });
                                      final result = await context
                                          .read<AuthService>()
                                          .createLandlordAccount(
                                            landlordDocId: widget.doc!.id,
                                            fullName: _name.text.trim(),
                                            email: _email.text.trim(),
                                            phone: _phone.text.trim(),
                                            password: _password.text.trim(),
                                            landlordCode: _code.text.trim(),
                                          );
                                      if (!mounted) return;
                                      setState(() {
                                        _creatingAuth = false;
                                        if (result.success) {
                                          _authSuccess =
                                              'Login account created successfully!';
                                        } else {
                                          _validationError = result.error ??
                                              'Failed to create account.';
                                        }
                                      });
                                    },
                              icon: _creatingAuth
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.person_add_outlined,
                                      size: 16, color: Colors.white),
                              label: Text(
                                _creatingAuth
                                    ? 'Creating…'
                                    : 'Create Login Account',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kGreen,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                          ),
                          if (_authSuccess != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(children: [
                                Icon(Icons.check_circle_outline,
                                    color: Colors.green.shade600, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(_authSuccess!,
                                        style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500))),
                              ]),
                            ),
                          ],
                        ],
                        if (!_isEdit) ...[
                          const SizedBox(height: 12),
                          // Summary preview card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kGreen.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: kGreen.withOpacity(0.20)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(Icons.checklist_rounded,
                                      size: 13, color: kGreen),
                                  const SizedBox(width: 6),
                                  Text(
                                    'ACCOUNT SUMMARY',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: kGreen,
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 10),
                                _SummaryRow(
                                  icon: Icons.person_outline,
                                  label: 'Name',
                                  value: _name.text.trim().isEmpty
                                      ? '—'
                                      : _name.text.trim(),
                                ),
                                _SummaryRow(
                                  icon: Icons.email_outlined,
                                  label: 'Email',
                                  value: _email.text.trim().isEmpty
                                      ? '—'
                                      : _email.text.trim(),
                                ),
                                _SummaryRow(
                                  icon: Icons.tag_rounded,
                                  label: 'Code',
                                  value: _code.text.trim().isEmpty
                                      ? '—'
                                      : _code.text.trim(),
                                ),
                                _SummaryRow(
                                  icon: Icons.lock_outline,
                                  label: 'Password',
                                  value: _password.text.isEmpty
                                      ? '—'
                                      : '●' * _password.text.length.clamp(0, 8),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // ── Tab 4: Payout ────────────────────────────────────
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Paystack payout account',
                        ),
                        if (_payoutHasAccount) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kGreen.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: kGreen.withOpacity(0.20)),
                            ),
                            child: Row(children: [
                              Icon(Icons.check_circle_rounded,
                                  color: kGreen, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Payout account active',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: kGreen)),
                                    Text(_payoutNumber.text,
                                        style: const TextStyle(
                                            fontSize: 13, color: kTextDark)),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          Text('Update payout account:',
                              style:
                                  TextStyle(fontSize: 12, color: kTextLight)),
                          const SizedBox(height: 10),
                        ] else ...[
                          _InfoNote(
                            icon: Icons.info_outline_rounded,
                            text:
                                'Set up the landlord\'s mobile money account so student payments are automatically routed to them.',
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Business name
                        _FormField(
                          label: 'Business / Full Name',
                          required: true,
                          icon: Icons.person_outline,
                          controller: _payoutName,
                        ),
                        const SizedBox(height: 12),

                        // Provider selector
                        Text('Mobile Money Network',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kTextLight)),
                        const SizedBox(height: 8),
                        Row(
                          children: _payoutProviders.map((p) {
                            final selected = _payoutProvider == p;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _payoutProvider = p),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: EdgeInsets.only(
                                      right:
                                          p != _payoutProviders.last ? 8 : 0),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? kGreen.withOpacity(0.08)
                                        : kSurfaceAlt,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selected ? kGreen : kBorder,
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(p,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              selected ? kGreen : kTextLight)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),

                        // MoMo number
                        _FormField(
                          label: 'Mobile Money Number',
                          required: true,
                          icon: Icons.phone_android_outlined,
                          controller: _payoutNumber,
                          keyboard: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),

                        // Save button — only shown when editing (landlord doc exists)
                        if (_isEdit)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _payoutSaving
                                  ? null
                                  : () => _savePayout(widget.doc!.id),
                              icon: _payoutSaving
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save_outlined,
                                      size: 16, color: Colors.white),
                              label: Text(
                                _payoutSaving
                                    ? 'Saving…'
                                    : _payoutHasAccount
                                        ? 'Update Payout Account'
                                        : 'Save Payout Account',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kGreen,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                          )
                        else
                          _InfoNote(
                            icon: Icons.info_outline_rounded,
                            text:
                                'Save the landlord first, then come back to edit and set up the payout account.',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DialogFooter(
              saving: _saving,
              onCancel: () => Navigator.pop(context),
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.removeListener(_genCode);
    _phone.removeListener(_genCode);
    for (final c in [
      _name,
      _email,
      _phone,
      _address,
      _code,
      _profileImage,
      _password,
      _payoutName,
      _payoutNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY ROW  (used inside Credentials tab preview card)
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 13, color: kTextLight),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: kTextLight),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: value == '—' ? kTextLight : kTextDark,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      );
}
// ─────────────────────────────────────────────────────────────────────────────
// LANDLORD HOSTELS SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordHostelsSheet extends StatelessWidget {
  const _LandlordHostelsSheet({
    required this.landlordId,
    required this.landlordName,
  });

  final String landlordId;
  final String landlordName;

  void _openEditHostel(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    showDialog(
      context: context,
      builder: (_) => _HostelEditDialog(doc: doc, parentContext: context),
    );
  }

  void _confirmDeleteHostel(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    _showDeleteDialog(
      context: context,
      title: 'Delete Hostel',
      name: d['hostel_name']?.toString() ?? '—',
      onConfirm: () async {
        try {
          await db.collection('hostels').doc(doc.id).delete();

          await ActivityLogger.log(
            action: 'Deleted Hostel',
            details:
                'Hostel: ${d['hostel_name']?.toString() ?? 'Unknown'}, Landlord: $landlordName',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Hostel deleted'),
                  backgroundColor: kGreenAccent),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  void _openRoomsSheet(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> hostelDoc) {
    final d = hostelDoc.data();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HostelRoomsSheet(
        hostelDoc: hostelDoc,
        hostelName: d['hostel_name']?.toString() ?? 'Hostel',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: kCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _SheetHandle(),
            _SheetHeader(
              icon: Icons.apartment_outlined,
              title: 'Hostels',
              subtitle: 'Registered by $landlordName',
              onClose: () => Navigator.pop(context),
            ),
            const Divider(color: kBorder, height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('hostels')
                    .where('landlord_id', isEqualTo: landlordId)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: kGreen));
                  }
                  // ✅ Explicitly typed — no dynamic inference
                  final docs = snap.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  if (docs.isEmpty) {
                    return _EmptySheet(
                      icon: Icons.apartment_outlined,
                      message: 'No hostels found for this landlord.',
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _HostelMiniCard(
                      doc: docs[i],
                      onEdit: () => _openEditHostel(context, docs[i]),
                      onDelete: () => _confirmDeleteHostel(context, docs[i]),
                      onViewRooms: () => _openRoomsSheet(context, docs[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOSTEL MINI CARD
// ─────────────────────────────────────────────────────────────────────────────

class _HostelMiniCard extends StatelessWidget {
  const _HostelMiniCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
    required this.onViewRooms,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewRooms;

  @override
  Widget build(BuildContext context) {
    // ✅ No cast needed
    final d = doc.data();
    final imageUrl = d['image']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                imageUrl,
                height: 90,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.apartment_rounded, color: kGreen, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      d['hostel_name']?.toString() ?? '—',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kTextDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kGreenAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${d['rooms_available'] ?? 0} rooms',
                      style: const TextStyle(
                          fontSize: 10,
                          color: kGreenAccent,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _MiniInfo(
                      icon: Icons.tag_outlined,
                      value: d['hostel_code']?.toString() ?? '—'),
                  const SizedBox(width: 12),
                  _MiniInfo(
                      icon: Icons.location_on_outlined,
                      value: d['town']?.toString() ?? '—'),
                ]),
                _PriceRangeRow(hostelId: doc.id),
                const SizedBox(height: 10),
                const Divider(height: 1, color: kBorder),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _MiniBtn(
                      icon: Icons.door_front_door_outlined,
                      label: 'Rooms',
                      color: Colors.teal,
                      onTap: onViewRooms,
                    ),
                    _MiniBtn(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      color: Colors.orange,
                      onTap: onEdit,
                    ),
                    _MiniBtn(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOSTEL EDIT DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _HostelEditDialog extends StatefulWidget {
  const _HostelEditDialog({required this.doc, required this.parentContext});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final BuildContext parentContext;

  @override
  State<_HostelEditDialog> createState() => _HostelEditDialogState();
}

class _HostelEditDialogState extends State<_HostelEditDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _town;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _desc;
  late final TextEditingController _priceRange;
  late final TextEditingController _roomsAvail;
  late final TextEditingController _momo;
  late final TextEditingController _cash;
  late final TextEditingController _bank;
  late final TextEditingController _other;
  late final TextEditingController _image;
  late final TextEditingController _images;
  late final TextEditingController _googleMap;

  late final TabController _tabs;
  String _durationType = 'per year';
  String _depositType = 'none'; // 'none' | 'percent' | 'fixed'
  late final TextEditingController _depositValue;
  bool _saving = false;
  String? _validationError;

  static const _durationOptions = [
    'per year',
    'per semester',
    'per month',
    'per Academic year',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    // ✅ No cast needed
    final d = widget.doc.data();
    _name = TextEditingController(text: d['hostel_name']?.toString() ?? '');
    _code = TextEditingController(text: d['hostel_code']?.toString() ?? '');
    _town = TextEditingController(text: d['town']?.toString() ?? '');
    _address = TextEditingController(text: d['address']?.toString() ?? '');
    _phone = TextEditingController(text: d['phone']?.toString() ?? '');
    _desc = TextEditingController(text: d['description']?.toString() ?? '');
    _priceRange =
        TextEditingController(text: d['price_range']?.toString() ?? '');
    _roomsAvail =
        TextEditingController(text: (d['rooms_available'] ?? 0).toString());
    _momo = TextEditingController(text: d['payment_momo']?.toString() ?? '');
    _cash = TextEditingController(text: d['payment_cash']?.toString() ?? '');
    _bank = TextEditingController(text: d['payment_bank']?.toString() ?? '');
    _other = TextEditingController(text: d['payment_other']?.toString() ?? '');
    _image = TextEditingController(text: d['image']?.toString() ?? '');
    _images = TextEditingController(text: d['images']?.toString() ?? '');
    _googleMap = TextEditingController(text: d['google_map']?.toString() ?? '');
    _durationType = d['duration_type']?.toString() ?? 'per year';
    _depositType = d['deposit_type']?.toString() ?? 'none';
    final dv = (d['deposit_value'] as num?)?.toDouble() ?? 0.0;
    _depositValue = TextEditingController(
      text: dv > 0 ? dv.toStringAsFixed(_depositType == 'percent' ? 0 : 2) : '',
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _validationError = 'Hostel Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });

    try {
      double parsedDeposit = 0.0;
      if (_depositType != 'none') {
        parsedDeposit = double.tryParse(_depositValue.text.trim()) ?? 0.0;
      }
      _depositValue.addListener(() => setState(() {}));
      await db.collection('hostels').doc(widget.doc.id).update({
        'hostel_name': _name.text.trim(),
        'town': _town.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'description': _desc.text.trim(),
        'duration_type': _durationType,
        'deposit_type': _depositType,
        'deposit_value': parsedDeposit,
        'price_range': _priceRange.text.trim(),
        'rooms_available': int.tryParse(_roomsAvail.text.trim()) ?? 0,
        'payment_momo': _momo.text.trim(),
        'payment_cash': _cash.text.trim(),
        'payment_bank': _bank.text.trim(),
        'payment_other': _other.text.trim(),
        'image': _image.text.trim(),
        'images': _images.text.trim(),
        'google_map': _googleMap.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });
// ✅ ADD THIS
      await ActivityLogger.log(
        action: 'Updated Hostel',
        details: 'Hostel: ${_name.text.trim()}, Town: ${_town.text.trim()}',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSuccessToast(widget.parentContext, 'Hostel Updated Successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationError = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dw = _dialogWidth(context, maxPx: 560);
    final dh = _dialogMaxHeight(context);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: _isPhone(context) ? 8 : 24,
        vertical: _isPhone(context) ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: SizedBox(
        width: dw,
        height: dh,
        child: Column(
          children: [
            _DialogHeader(
              icon: Icons.apartment_rounded,
              title: 'Edit Hostel',
              subtitle: 'Update hostel information & settings',
              iconColor: kGreen,
            ),
            _DialogTabBar(
              controller: _tabs,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Basic'),
                Tab(icon: Icon(Icons.sell_outlined, size: 16), text: 'Pricing'),
                Tab(
                    icon: Icon(Icons.credit_card_outlined, size: 16),
                    text: 'Payment'),
                Tab(
                    icon: Icon(Icons.photo_library_outlined, size: 16),
                    text: 'Media'),
              ],
            ),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _ValidationBanner(_validationError!),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // ── Tab 1: Basic ──
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                            icon: Icons.apartment_outlined,
                            label: 'Basic information'),
                        _FormField(
                          label: 'Hostel name',
                          required: true,
                          icon: Icons.apartment_rounded,
                          controller: _name,
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: _ReadOnlyCodeField(
                              label: 'Hostel code',
                              value: _code.text.isEmpty ? '—' : _code.text,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FormField(
                              label: 'Town',
                              icon: Icons.location_city_outlined,
                              controller: _town,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        _FormField(
                          label: 'Address',
                          icon: Icons.location_on_outlined,
                          controller: _address,
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          label: 'Phone',
                          icon: Icons.phone_outlined,
                          controller: _phone,
                          keyboard: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          label: 'Description',
                          icon: Icons.notes_outlined,
                          controller: _desc,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),

                  // ── Tab 2: Pricing ──
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                            icon: Icons.sell_outlined,
                            label: 'Pricing & availability'),
                        _DropdownField(
                          label: 'Duration type',
                          value: _durationOptions.contains(_durationType)
                              ? _durationType
                              : 'per year',
                          items: _durationOptions,
                          onChanged: (v) =>
                              setState(() => _durationType = v ?? 'per year'),
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          label: 'Price range (e.g. ₵800 – ₵1200)',
                          icon: Icons.attach_money_outlined,
                          controller: _priceRange,
                        ),
                        const SizedBox(height: 12),
                        _SectionLabel(
                            icon: Icons.meeting_room_outlined,
                            label: 'Room count'),
                        _StepperField(
                          label: 'Rooms available',
                          controller: _roomsAvail,
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(
                            icon: Icons.price_check_rounded,
                            label: 'Deposit policy'),
                        Row(children: [
                          _DepositChip(
                            label: 'None',
                            icon: Icons.block_rounded,
                            selected: _depositType == 'none',
                            onTap: () => setState(() {
                              _depositType = 'none';
                              _depositValue.clear();
                            }),
                          ),
                          const SizedBox(width: 8),
                          _DepositChip(
                            label: 'Percentage',
                            icon: Icons.percent_rounded,
                            selected: _depositType == 'percent',
                            onTap: () =>
                                setState(() => _depositType = 'percent'),
                          ),
                          const SizedBox(width: 8),
                          _DepositChip(
                            label: 'Fixed (GHS)',
                            icon: Icons.attach_money_rounded,
                            selected: _depositType == 'fixed',
                            onTap: () => setState(() => _depositType = 'fixed'),
                          ),
                        ]),
                        if (_depositType != 'none') ...[
                          const SizedBox(height: 12),
                          _FormField(
                            label: _depositType == 'percent'
                                ? 'Deposit % *'
                                : 'Deposit Amount (GHS) *',
                            controller: _depositValue,
                            icon: _depositType == 'percent'
                                ? Icons.percent_rounded
                                : Icons.attach_money_rounded,
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                          const SizedBox(height: 6),
                          _DepositPreviewNote(
                            type: _depositType,
                            rawValue: _depositValue.text,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Tab 3: Payment ──
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'Payment methods'),
                        _PaymentCard(
                          icon: Icons.phone_android_outlined,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'Mobile Money (MoMo)',
                          hint: 'Number & network (e.g. 0244 123 456 — MTN)',
                          controller: _momo,
                        ),
                        const SizedBox(height: 10),
                        _PaymentCard(
                          icon: Icons.account_balance_outlined,
                          iconColor: Colors.blue.shade600,
                          title: 'Bank Transfer',
                          hint: 'Bank name & account number',
                          controller: _bank,
                        ),
                        const SizedBox(height: 10),
                        _PaymentCard(
                          icon: Icons.payments_outlined,
                          iconColor: kGreen,
                          title: 'Cash Payment',
                          hint: 'Cash payment instructions',
                          controller: _cash,
                        ),
                        const SizedBox(height: 10),
                        _PaymentCard(
                          icon: Icons.more_horiz_rounded,
                          iconColor: kTextLight,
                          title: 'Other',
                          hint: 'Any other payment details',
                          controller: _other,
                        ),
                      ],
                    ),
                  ),

                  // ── Tab 4: Media ──
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                            icon: Icons.photo_library_outlined,
                            label: 'Images & location'),
                        _ImagePickerField(
                          label: 'Main image',
                          controller: _image,
                          folder: 'hostels/main',
                        ),
                        const SizedBox(height: 16),
                        _MultiImagePickerField(
                          label: 'Additional images',
                          controller: _images,
                          folder: 'hostels/gallery',
                        ),
                        const SizedBox(height: 16),
                        _FormField(
                          label: 'Google Maps link',
                          icon: Icons.map_outlined,
                          controller: _googleMap,
                          keyboard: TextInputType.url,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DialogFooter(
              saving: _saving,
              onCancel: () => Navigator.pop(context),
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _depositValue.dispose();
    for (final c in [
      _name,
      _code,
      _town,
      _address,
      _phone,
      _desc,
      _priceRange,
      _roomsAvail,
      _momo,
      _cash,
      _bank,
      _other,
      _image,
      _images,
      _googleMap,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOSTEL ROOMS SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _HostelRoomsSheet extends StatelessWidget {
  const _HostelRoomsSheet({
    required this.hostelDoc,
    required this.hostelName,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> hostelDoc;
  final String hostelName;

  void _openEditRoom(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> roomDoc) {
    showDialog(
      context: context,
      builder: (_) => _RoomEditDialog(doc: roomDoc, parentContext: context),
    );
  }

  void _confirmDeleteRoom(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> roomDoc) {
    final d = roomDoc.data();
    _showDeleteDialog(
      context: context,
      title: 'Delete Room',
      name: 'Room ${d['room_number']?.toString() ?? '—'}',
      onConfirm: () async {
        try {
          await db.collection('rooms').doc(roomDoc.id).delete();
// ✅ ADD THIS
          await ActivityLogger.log(
            action: 'Deleted Room',
            details:
                'Room ${d['room_number']?.toString() ?? 'Unknown'} in ${d['hostel_name']?.toString() ?? 'Unknown'}',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Room deleted'), backgroundColor: kGreenAccent),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: kCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _SheetHandle(),
            _SheetHeader(
              icon: Icons.door_front_door_outlined,
              title: 'Rooms',
              subtitle: hostelName,
              onClose: () => Navigator.pop(context),
            ),
            const Divider(color: kBorder, height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('rooms')
                    .where('hostel_id', isEqualTo: hostelDoc.id)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: kGreen));
                  }
                  // ✅ Explicitly typed — no dynamic inference
                  final docs = snap.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  if (docs.isEmpty) {
                    return _EmptySheet(
                      icon: Icons.bed_outlined,
                      message: 'No rooms found for this hostel.',
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _RoomMiniCard(
                      doc: docs[i],
                      onEdit: () => _openEditRoom(context, docs[i]),
                      onDelete: () => _confirmDeleteRoom(context, docs[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOM MINI CARD
// ─────────────────────────────────────────────────────────────────────────────

class _RoomMiniCard extends StatelessWidget {
  const _RoomMiniCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // ✅ No cast needed
    final d = doc.data();
    final price = (d['price'] as num?)?.toDouble();
    final fmt = NumberFormat('#,##0.00');
    final priceStr = price != null ? '₵${fmt.format(price)}' : '—';

    // ✅ Safe boolean check — no dynamic type confusion
    final availableRaw = d['available'];
    final available = availableRaw == true || availableRaw?.toString() == '1';

    final imageUrl = d['image']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: Image.network(
                imageUrl,
                height: 80,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.bed_rounded, color: kGreen, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Room ${d['room_number']?.toString() ?? '—'}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kTextDark),
                    ),
                  ),
                  _StatusBadge(available: available),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 12, children: [
                  _MiniInfo(
                      icon: Icons.category_outlined,
                      value: d['type']?.toString() ?? '—'),
                  _MiniInfo(
                      icon: Icons.people_outline,
                      value: 'Cap: ${d['capacity'] ?? 0}'),
                  _MiniInfo(icon: Icons.attach_money_outlined, value: priceStr),
                ]),
                const SizedBox(height: 8),
                const Divider(height: 1, color: kBorder),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _MiniBtn(
                      icon: Icons.edit_outlined,
                      label: 'Edit Room',
                      color: Colors.orange,
                      onTap: onEdit,
                    ),
                    _MiniBtn(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOM EDIT DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _RoomEditDialog extends StatefulWidget {
  const _RoomEditDialog({required this.doc, required this.parentContext});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final BuildContext parentContext;

  @override
  State<_RoomEditDialog> createState() => _RoomEditDialogState();
}

class _RoomEditDialogState extends State<_RoomEditDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _roomNumber;
  late final TextEditingController _capacity;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late final TextEditingController _images;

  late final TabController _tabs;
  String _type = 'Single';
  bool _available = true;
  bool _saving = false;
  String? _validationError;

  static const _types = [
    'Single',
    'Double',
    'Triple',
    'Quad',
    'Suite',
    'Studio'
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // ✅ No cast needed
    final d = widget.doc.data();
    _roomNumber =
        TextEditingController(text: d['room_number']?.toString() ?? '');
    _capacity = TextEditingController(text: (d['capacity'] ?? 1).toString());
    _price = TextEditingController(text: (d['price'] ?? 0).toString());
    _image = TextEditingController(text: d['image']?.toString() ?? '');
    _images = TextEditingController(text: d['images']?.toString() ?? '');
    _type = _types.contains(d['type']) ? d['type'].toString() : 'Single';
    // ✅ Safe boolean check
    final availableRaw = d['available'];
    _available = availableRaw == true || availableRaw?.toString() == '1';
  }

  Future<void> _save() async {
    if (_roomNumber.text.trim().isEmpty) {
      setState(() => _validationError = 'Room Number is required.');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });

    try {
      await db.collection('rooms').doc(widget.doc.id).update({
        'room_number': _roomNumber.text.trim(),
        'type': _type,
        'capacity': int.tryParse(_capacity.text.trim()) ?? 1,
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'available': _available,
        'image': _image.text.trim(),
        'images': _images.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      final d = widget.doc.data();
      await ActivityLogger.log(
        action: 'Updated Room',
        details:
            'Room ${_roomNumber.text.trim()} in ${d['hostel_name']?.toString() ?? 'Unknown'}',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSuccessToast(widget.parentContext, 'Room Updated Successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationError = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dw = _dialogWidth(context, maxPx: 460);
    final dh = _dialogMaxHeight(context);
    // ✅ No cast needed
    final d = widget.doc.data();
    final hostelName = d['hostel_name']?.toString() ?? 'Hostel';

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: _isPhone(context) ? 8 : 24,
        vertical: _isPhone(context) ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: SizedBox(
        width: dw,
        height: dh,
        child: Column(
          children: [
            _DialogHeader(
              icon: Icons.door_front_door_outlined,
              title: 'Edit Room',
              subtitle: hostelName,
              iconColor: Colors.blue.shade600,
              accentColor: Colors.blue.shade600,
            ),
            _DialogTabBar(
              controller: _tabs,
              accentColor: Colors.blue.shade600,
              tabs: const [
                Tab(icon: Icon(Icons.tune_rounded, size: 16), text: 'Details'),
                Tab(
                    icon: Icon(Icons.photo_library_outlined, size: 16),
                    text: 'Photos'),
              ],
            ),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _ValidationBanner(_validationError!),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // ── Tab 1: Details ──
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                            icon: Icons.door_front_door_outlined,
                            label: 'Room details'),
                        Row(children: [
                          Expanded(
                            child: _FormField(
                              label: 'Room number',
                              required: true,
                              icon: Icons.tag_rounded,
                              controller: _roomNumber,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StepperField(
                              label: 'Capacity',
                              controller: _capacity,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _SectionLabel(
                            icon: Icons.category_outlined, label: 'Room type'),
                        _RoomTypePills(
                          types: _types,
                          selected: _type,
                          onChanged: (t) => setState(() => _type = t),
                        ),
                        const SizedBox(height: 16),
                        _SectionLabel(
                            icon: Icons.attach_money_outlined,
                            label: 'Pricing'),
                        _PricePrefixField(
                          label: 'Price (₵)',
                          controller: _price,
                        ),
                        const SizedBox(height: 16),
                        _SectionLabel(
                            icon: Icons.toggle_on_outlined,
                            label: 'Availability'),
                        _AvailabilityToggle(
                          available: _available,
                          onChanged: (v) => setState(() => _available = v),
                        ),
                      ],
                    ),
                  ),

                  // ── Tab 2: Photos ──
                  SingleChildScrollView(
                    padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                            icon: Icons.photo_camera_outlined,
                            label: 'Room photos'),
                        _ImagePickerField(
                          label: 'Main room photo',
                          controller: _image,
                          folder: 'rooms/main',
                        ),
                        const SizedBox(height: 16),
                        _MultiImagePickerField(
                          label: 'Additional photos',
                          controller: _images,
                          folder: 'rooms/gallery',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DialogFooter(
              saving: _saving,
              accentColor: Colors.blue.shade600,
              onCancel: () => Navigator.pop(context),
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_roomNumber, _capacity, _price, _image, _images]) {
      c.dispose();
    }
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED DIALOG CHROME WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kTextDark)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11, color: kTextLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogTabBar extends StatelessWidget {
  const _DialogTabBar({
    required this.controller,
    required this.tabs,
    this.accentColor,
  });

  final TabController controller;
  final List<Widget> tabs;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? kGreen;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder)),
        color: kSurface,
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: color,
        unselectedLabelColor: kTextLight,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
        indicatorColor: color,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: tabs,
      ),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  const _DialogFooter({
    required this.saving,
    required this.onCancel,
    required this.onSave,
    this.accentColor,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? kGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 13, color: kTextLight),
            const SizedBox(width: 5),
            const Text(
              'Fields marked * are required',
              style: TextStyle(fontSize: 11, color: kTextLight),
            ),
          ]),
          const Spacer(),
          TextButton(
            onPressed: saving ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: kTextLight,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: ElevatedButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined,
                      size: 16, color: Colors.white),
              label: Text(
                saving ? 'Saving…' : 'Save changes',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                disabledBackgroundColor: color.withOpacity(0.5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED FORM WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(icon, size: 13, color: kTextLight),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: kTextLight,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: kBorder, height: 1)),
        ]),
      );
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.controller,
    this.icon,
    this.required = false,
    this.keyboard = TextInputType.text,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final bool required;
  final TextInputType keyboard;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextLight)),
          if (required) ...[
            const SizedBox(width: 3),
            const Text('*', style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ]),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: kTextDark),
          decoration: InputDecoration(
            prefixIcon:
                icon != null ? Icon(icon, size: 16, color: kTextLight) : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kGreen, width: 1.5)),
            filled: true,
            fillColor: kSurface,
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyCodeField extends StatelessWidget {
  const _ReadOnlyCodeField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextLight)),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kSurfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: Row(children: [
              Icon(Icons.tag_rounded, size: 14, color: kGreen),
              const SizedBox(width: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kGreen)),
            ]),
          ),
        ],
      );
}

class _StepperField extends StatelessWidget {
  const _StepperField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight)),
        const SizedBox(height: 5),
        Row(children: [
          _StepBtn(
            icon: Icons.remove,
            onTap: () {
              final v = int.tryParse(controller.text) ?? 0;
              if (v > 0) controller.text = (v - 1).toString();
            },
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: kTextDark),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: kGreen, width: 1.5)),
                filled: true,
                fillColor: kSurface,
              ),
            ),
          ),
          _StepBtn(
            icon: Icons.add,
            onTap: () {
              final v = int.tryParse(controller.text) ?? 0;
              controller.text = (v + 1).toString();
            },
          ),
        ]),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kSurfaceAlt,
            border: Border.all(color: kBorder),
          ),
          child: Icon(icon, size: 18, color: kTextDark),
        ),
      );
}

class _PricePrefixField extends StatelessWidget {
  const _PricePrefixField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextLight)),
          const SizedBox(height: 5),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13, color: kTextDark),
            decoration: InputDecoration(
              prefixIcon: Container(
                width: 40,
                alignment: Alignment.center,
                child: Text('₵',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kTextLight)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.blue.shade600, width: 1.5)),
              filled: true,
              fillColor: kSurface,
            ),
          ),
        ],
      );
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextLight)),
          const SizedBox(height: 5),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: value,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kGreen, width: 1.5)),
              filled: true,
              fillColor: kSurface,
            ),
            style: const TextStyle(fontSize: 13, color: kTextDark),
            items: items
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      );
}

class _RoomTypePills extends StatelessWidget {
  const _RoomTypePills({
    required this.types,
    required this.selected,
    required this.onChanged,
  });

  final List<String> types;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: types.map((t) {
          final isSelected = t == selected;
          return GestureDetector(
            onTap: () => onChanged(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.shade600.withOpacity(0.10)
                    : kSurfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.blue.shade600 : kBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(t,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? Colors.blue.shade700 : kTextLight,
                  )),
            ),
          );
        }).toList(),
      );
}

class _AvailabilityToggle extends StatelessWidget {
  const _AvailabilityToggle({
    required this.available,
    required this.onChanged,
  });

  final bool available;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kSurfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          children: [
            Row(children: [
              Icon(
                available
                    ? Icons.check_circle_outline_rounded
                    : Icons.cancel_outlined,
                size: 18,
                color: available ? kGreen : Colors.red,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Room available',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextDark)),
                    const Text('Visible to students for booking',
                        style: TextStyle(fontSize: 11, color: kTextLight)),
                  ],
                ),
              ),
              Switch(
                value: available,
                activeColor: kGreen,
                onChanged: onChanged,
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _StatusPill(
                label: available ? 'Available' : 'Unavailable',
                color: available ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: available ? 'Not booked' : 'Booked',
                color: available ? Colors.blue : Colors.orange,
              ),
            ]),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.hint,
    required this.controller,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextDark)),
            ]),
            const SizedBox(height: 10),
            TextFormField(
              controller: controller,
              style: const TextStyle(fontSize: 12, color: kTextDark),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 12, color: kTextLight),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: kGreen, width: 1.5)),
                filled: true,
                fillColor: kSurfaceAlt,
              ),
            ),
          ],
        ),
      );
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kGreen.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kGreen.withOpacity(0.20)),
        ),
        child: Row(children: [
          Icon(icon, size: 15, color: kGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 11, color: kTextDark)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SHEET CHROME WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: kBorder, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 8, 12),
        child: Row(
          children: [
            Icon(icon, color: kGreen, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kTextDark)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: kTextLight)),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, color: kTextLight),
              tooltip: 'Close',
            ),
          ],
        ),
      );
}

class _EmptySheet extends StatelessWidget {
  const _EmptySheet({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: kTextLight.withOpacity(0.35)),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(fontSize: 13, color: kTextLight)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DELETE DIALOG
// ─────────────────────────────────────────────────────────────────────────────

void _showDeleteDialog({
  required BuildContext context,
  required String title,
  required String name,
  required Future<void> Function() onConfirm,
}) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Are you sure you want to delete:',
              style: TextStyle(color: kTextLight, fontSize: 13)),
          const SizedBox(height: 6),
          Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: kTextDark)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 13, color: Colors.red.shade600),
              const SizedBox(width: 6),
              const Text('This action cannot be undone.',
                  style: TextStyle(color: Colors.red, fontSize: 11)),
            ]),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
          label: const Text('Delete',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          onPressed: () async {
            Navigator.pop(context);
            await onConfirm();
          },
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.available});
  final bool available;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: available
              ? Colors.green.withOpacity(0.10)
              : Colors.red.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: available
                  ? Colors.green.withOpacity(0.35)
                  : Colors.red.withOpacity(0.35)),
        ),
        child: Text(
          available ? 'Available' : 'Booked',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: available ? Colors.green : Colors.red),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PRICE RANGE ROW
// ─────────────────────────────────────────────────────────────────────────────

class _PriceRangeRow extends StatelessWidget {
  const _PriceRangeRow({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future:
          db.collection('rooms').where('hostel_id', isEqualTo: hostelId).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _MiniInfo(icon: Icons.attach_money, value: '…'),
          );
        }
        // ✅ Explicitly typed
        final rooms =
            snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (rooms.isEmpty) return const SizedBox.shrink();

        double? minPrice, maxPrice;
        for (final r in rooms) {
          final price = (r.data()['price'] as num?)?.toDouble();
          if (price != null) {
            minPrice = minPrice == null
                ? price
                : (price < minPrice ? price : minPrice);
            maxPrice = maxPrice == null
                ? price
                : (price > maxPrice ? price : maxPrice);
          }
        }
        if (minPrice == null) return const SizedBox.shrink();

        final fmt = NumberFormat('#,##0.00');
        final priceStr = (minPrice == maxPrice)
            ? '₵${fmt.format(minPrice)}'
            : '₵${fmt.format(minPrice)} – ₵${fmt.format(maxPrice!)}';

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _MiniInfo(icon: Icons.attach_money_outlined, value: priceStr),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VALIDATION BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUCCESS TOAST
// ─────────────────────────────────────────────────────────────────────────────

void _showSuccessToast(BuildContext context, String message) {
  final overlay = Navigator.of(context).overlay;
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) =>
        _SuccessToast(message: message, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}
// ─────────────────────────────────────────────────────────────────────────────
// DEPOSIT CHIP  (admin)
// ─────────────────────────────────────────────────────────────────────────────

class _DepositChip extends StatelessWidget {
  const _DepositChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? kGreen : kSurfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: selected ? kGreen : kBorder, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16, color: selected ? Colors.white : kTextLight),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : kTextLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DEPOSIT PREVIEW NOTE
// ─────────────────────────────────────────────────────────────────────────────

class _DepositPreviewNote extends StatelessWidget {
  const _DepositPreviewNote({required this.type, required this.rawValue});
  final String type;
  final String rawValue;

  @override
  Widget build(BuildContext context) {
    final val = double.tryParse(rawValue.trim()) ?? 0.0;
    if (val <= 0) return const SizedBox.shrink();

    final String preview;
    if (type == 'percent') {
      final dep = 1000.0 * val / 100;
      preview =
          'e.g. ${val.toStringAsFixed(0)}% of GHS 1000 room = GHS ${dep.toStringAsFixed(2)} deposit';
    } else {
      preview = 'Student pays GHS ${val.toStringAsFixed(2)} deposit per slot';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kGreen.withOpacity(0.20)),
      ),
      child: Row(children: [
        Icon(Icons.calculate_outlined, size: 13, color: kGreen),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            preview,
            style: TextStyle(
                fontSize: 11, color: kGreen, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
}

class _SuccessToast extends StatefulWidget {
  const _SuccessToast({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;

  @override
  State<_SuccessToast> createState() => _SuccessToastState();
}

class _SuccessToastState extends State<_SuccessToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onDone();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = _isPhone(context) ? 16.0 : 0.0;
    return Positioned(
      top: 40,
      left: pad,
      right: pad,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF03b352), Color(0xFF028802)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: kTextLight),
            const SizedBox(width: 5),
            SizedBox(
              width: 72,
              child: Text('$label:',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextLight)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 12, color: kTextDark),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

class _CardBtn extends StatelessWidget {
  const _CardBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      );
}

class _AddBtn extends StatelessWidget {
  const _AddBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 18, color: Colors.white),
        label: const Text('Add New', style: TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      );
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: kTextLight),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontSize: 12, color: kTextLight)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE PICKER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePickerField extends StatefulWidget {
  const _ImagePickerField({
    required this.label,
    required this.controller,
    this.folder = 'hostels',
  });
  final String label;
  final TextEditingController controller;
  final String folder;

  @override
  State<_ImagePickerField> createState() => _ImagePickerFieldState();
}

class _ImagePickerFieldState extends State<_ImagePickerField> {
  bool _uploading = false;

  Future<void> _pick() async {
    setState(() => _uploading = true);
    try {
      final url = await _pickAndUpload(folder: widget.folder);
      if (url != null && mounted) {
        widget.controller.text = url;
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextLight)),
          ),
          if (_uploading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: kGreen),
            ),
        ]),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _uploading ? null : _pick,
          child: Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              color: kSurfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: url.isNotEmpty ? kGreen.withOpacity(0.4) : kBorder),
            ),
            child: url.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _UploadPlaceholder(uploading: _uploading)),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit, size: 11, color: Colors.white),
                                SizedBox(width: 4),
                                Text('Replace',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : _UploadPlaceholder(uploading: _uploading),
          ),
        ),
      ],
    );
  }
}

class _UploadPlaceholder extends StatelessWidget {
  const _UploadPlaceholder({required this.uploading});
  final bool uploading;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              uploading
                  ? Icons.cloud_upload_outlined
                  : Icons.add_photo_alternate_outlined,
              size: 28,
              color: uploading ? kGreen : kTextLight,
            ),
            const SizedBox(height: 6),
            Text(
              uploading ? 'Uploading…' : 'Tap to upload',
              style: TextStyle(
                  fontSize: 12,
                  color: uploading ? kGreen : kTextLight,
                  fontWeight: uploading ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      );
}

class _MultiImagePickerField extends StatefulWidget {
  const _MultiImagePickerField({
    required this.label,
    required this.controller,
    this.folder = 'hostels',
  });
  final String label;
  final TextEditingController controller;
  final String folder;

  @override
  State<_MultiImagePickerField> createState() => _MultiImagePickerFieldState();
}

class _MultiImagePickerFieldState extends State<_MultiImagePickerField> {
  bool _uploading = false;

  List<String> get _urls {
    final raw = widget.controller.text.trim();
    if (raw.isEmpty) return [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _setUrls(List<String> urls) {
    widget.controller.text = urls.join(',');
    setState(() {});
  }

  Future<void> _pickMore() async {
    setState(() => _uploading = true);
    try {
      final url = await _pickAndUpload(folder: widget.folder);
      if (url != null && mounted) {
        _setUrls([..._urls, url]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _remove(int index) {
    final list = _urls;
    list.removeAt(index);
    _setUrls(list);
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    const double thumbSize = 80;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextLight)),
          ),
          GestureDetector(
            onTap: _uploading ? null : _pickMore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kGreen.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _uploading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kGreen),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined,
                          size: 14, color: kGreen),
                  const SizedBox(width: 5),
                  Text(
                    _uploading ? 'Uploading…' : 'Add image',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: kGreen),
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (urls.isEmpty)
          Container(
            height: thumbSize,
            decoration: BoxDecoration(
              color: kSurfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: const Center(
              child: Text('No additional images',
                  style: TextStyle(fontSize: 12, color: kTextLight)),
            ),
          )
        else
          SizedBox(
            height: thumbSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      urls[i],
                      width: thumbSize,
                      height: thumbSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.red.shade300),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: GestureDetector(
                      onTap: () => _remove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
