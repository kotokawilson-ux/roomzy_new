// lib/screens/landlord/hostels/hostel_form.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Add / Edit Hostel Form (Landlord)
// Full field parity with admin panel.
// Cloudinary image upload — no dart:io dependency.
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../services/landlord_service.dart';
import '../../../models/models.dart';

// ── Cloudinary config ────────────────────────────────────────
const _kCloudName = 'dfv9yibba';
const _kUploadPreset = 'ml_default';

Future<String?> _uploadToCloudinary({required String folder}) async {
  final picker = ImagePicker();
  final XFile? picked =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
  if (picked == null) return null;

  final Uint8List bytes = await picked.readAsBytes();
  final String filename = picked.name.isNotEmpty
      ? picked.name
      : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final uri =
      Uri.parse('https://api.cloudinary.com/v1_1/$_kCloudName/image/upload');

  final req = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _kUploadPreset
    ..fields['folder'] = folder
    ..files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

  try {
    final res = await req.send();
    final body = await res.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (res.statusCode == 200) return json['secure_url'] as String?;
    debugPrint('Cloudinary error [${res.statusCode}]: $body');
    return null;
  } catch (e) {
    debugPrint('_uploadToCloudinary: $e');
    return null;
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
  static const amber = Color(0xFFF59E0B);
}

// ─────────────────────────────────────────────────────────────
// HOSTEL FORM
// ─────────────────────────────────────────────────────────────
class HostelForm extends StatefulWidget {
  const HostelForm({
    super.key,
    required this.landlordId,
    required this.service,
    this.hostel,
  });

  final String landlordId;
  final LandlordService service;
  final Hostel? hostel;

  @override
  State<HostelForm> createState() => _HostelFormState();
}

class _HostelFormState extends State<HostelForm> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool get _isEdit => widget.hostel != null;

  // Controllers — basic
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _town;
  late final TextEditingController _phone;
  late final TextEditingController _description;
  late final TextEditingController _priceRange;
  late final TextEditingController _googleMap;

  // Controllers — payment
  late final TextEditingController _momo;
  late final TextEditingController _cash;
  late final TextEditingController _bank;
  late final TextEditingController _other;

  // Controllers — images (hold URLs)
  late final TextEditingController _mainImage;
  late final TextEditingController _galleryImages; // comma-separated

  // Controllers — deposit
  late final TextEditingController _depositValue;

  // Duration
  late String _durationType;

  // Deposit
  late String _depositType; // 'none' | 'percent' | 'fixed'

  // School
  String? _schoolId;
  String? _schoolName;
  String? _schoolShortName;
  List<School> _schools = [];
  bool _schoolsLoaded = false;

  @override
  void initState() {
    super.initState();
    final h = widget.hostel;
    _name = TextEditingController(text: h?.hostelName ?? '');
    _address = TextEditingController(text: h?.address ?? '');
    _town = TextEditingController(text: h?.town ?? '');
    _phone = TextEditingController(text: h?.phone ?? '');
    _description = TextEditingController(text: h?.description ?? '');
    _priceRange = TextEditingController(text: h?.priceRange ?? '');
    _googleMap = TextEditingController(text: h?.googleMap ?? '');
    _momo = TextEditingController(text: h?.paymentMomo ?? '');
    _cash = TextEditingController(text: h?.paymentCash ?? '');
    _bank = TextEditingController(text: h?.paymentBank ?? '');
    _other = TextEditingController(text: h?.paymentOther ?? '');
    _mainImage = TextEditingController(text: h?.image ?? '');
    _galleryImages = TextEditingController(text: h?.images ?? '');
    _durationType = h?.durationType ?? 'per year';
    _depositType = h?.depositType ?? 'none';
    _depositValue = TextEditingController(
      text: (h?.depositValue ?? 0) > 0
          ? h!.depositValue.toStringAsFixed(h.depositType == 'percent' ? 0 : 2)
          : '',
    );
    _schoolId = h?.schoolId;
    _schoolName = h?.schoolName;
    _schoolShortName = h?.schoolShortName;
    _loadSchools();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _town,
      _phone,
      _description,
      _priceRange,
      _googleMap,
      _momo,
      _cash,
      _bank,
      _other,
      _mainImage,
      _galleryImages,
      _depositValue,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSchools() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .orderBy('full_name')
          .get();
      if (mounted)
        setState(() {
          _schools =
              snap.docs.map((d) => School.fromJson(d.id, d.data())).toList();
          _schoolsLoaded = true;
        });
    } catch (_) {
      if (mounted) setState(() => _schoolsLoaded = true);
    }
  }

  // ── Save ─────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_schoolId == null) {
      _showSnack('Please select a school.', isError: true);
      return;
    }

    // Validate deposit value when type is not 'none'
    double parsedDepositValue = 0.0;
    if (_depositType != 'none') {
      parsedDepositValue = double.tryParse(_depositValue.text.trim()) ?? 0.0;
      if (parsedDepositValue <= 0) {
        _showSnack('Enter a valid deposit amount.', isError: true);
        return;
      }
      if (_depositType == 'percent' && parsedDepositValue > 100) {
        _showSnack('Percentage cannot exceed 100%.', isError: true);
        return;
      }
    }

    setState(() => _saving = true);

    final h = widget.hostel;
    final hostel = Hostel(
      id: h?.id ?? '',
      landlordId: widget.landlordId,
      landlordName: h?.landlordName ?? '',
      landlordCode: h?.landlordCode ?? '',
      hostelName: _name.text.trim(),
      hostelCode: h?.hostelCode ?? '',
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      town: _town.text.trim().isEmpty ? null : _town.text.trim(),
      schoolId: _schoolId!,
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      roomsAvailable: h?.roomsAvailable ?? 0,
      image: _mainImage.text.trim().isEmpty ? null : _mainImage.text.trim(),
      images: _galleryImages.text.trim().isEmpty
          ? null
          : _galleryImages.text.trim(),
      phone: _phone.text.trim(),
      durationType: _durationType,
      paymentMomo: _momo.text.trim(),
      paymentCash: _cash.text.trim(),
      paymentBank: _bank.text.trim(),
      paymentOther: _other.text.trim(),
      googleMap: _googleMap.text.trim().isEmpty ? null : _googleMap.text.trim(),
      schoolName: _schoolName,
      schoolShortName: _schoolShortName,
      priceRange:
          _priceRange.text.trim().isEmpty ? null : _priceRange.text.trim(),
      depositType: _depositType,
      depositValue: parsedDepositValue,
    );

    if (_isEdit) {
      final r = await widget.service.updateHostel(hostel);
      setState(() => _saving = false);
      if (!mounted) return;
      if (r.success) {
        Navigator.pop(context);
        _showSnack('Hostel updated successfully');
      } else {
        _showSnack(r.error ?? 'Update failed', isError: true);
      }
    } else {
      final r = await widget.service.addHostel(hostel);
      setState(() => _saving = false);
      if (!mounted) return;
      if (r.id != null) {
        Navigator.pop(context);
        _showSnack('Hostel added successfully');
      } else {
        _showSnack(r.error ?? 'Add failed', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _C.red : _C.green,
    ));
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _C.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? 'Edit Hostel' : 'Add Hostel',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: _C.textDark),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _C.border),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: _C.green, strokeWidth: 2),
                  )
                : ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: Text(
                      _isEdit ? 'Save Changes' : 'Add Hostel',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Basic Info ──────────────────────────────
              _Section(
                title: 'Basic Information',
                icon: Icons.apartment_rounded,
                children: [
                  _Field(
                    label: 'Hostel Name *',
                    controller: _name,
                    hint: 'e.g. Green Valley Hostel',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  _SchoolPicker(
                    schools: _schools,
                    loaded: _schoolsLoaded,
                    selectedId: _schoolId,
                    onSelected: (s) => setState(() {
                      _schoolId = s.id;
                      _schoolName = s.fullName;
                      _schoolShortName = s.shortName;
                    }),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: _Field(
                        label: 'Town / Area',
                        controller: _town,
                        hint: 'e.g. Kumasi',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        label: 'Phone *',
                        controller: _phone,
                        hint: '024XXXXXXX',
                        keyboardType: TextInputType.phone,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Full Address',
                    controller: _address,
                    hint: 'Street / landmark',
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Description',
                    controller: _description,
                    hint: 'Describe your hostel...',
                    maxLines: 3,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Pricing ─────────────────────────────────
              _Section(
                title: 'Pricing',
                icon: Icons.payments_outlined,
                children: [
                  Row(children: [
                    Expanded(
                      child: _Field(
                        label: 'Price Range',
                        controller: _priceRange,
                        hint: 'e.g. GHS 1200 – 1800',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DurationDropdown(
                        value: _durationType,
                        onChanged: (v) =>
                            setState(() => _durationType = v ?? 'per year'),
                      ),
                    ),
                  ]),
                ],
              ),

              const SizedBox(height: 16),

              // ── Deposit ─────────────────────────────────
              _Section(
                title: 'Deposit Policy',
                icon: Icons.price_check_rounded,
                children: [
                  // Info note
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _C.amber.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _C.amber.withOpacity(0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 14, color: _C.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Set a deposit students must pay before their booking is accepted. '
                            'This will show on the room listing and booking form.',
                            style: TextStyle(
                                fontSize: 11, color: _C.amber, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Type selector
                  const Text('Deposit Type',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _C.textDark)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _DepositTypeChip(
                      label: 'None',
                      icon: Icons.block_rounded,
                      selected: _depositType == 'none',
                      onTap: () => setState(() {
                        _depositType = 'none';
                        _depositValue.clear();
                      }),
                    ),
                    const SizedBox(width: 8),
                    _DepositTypeChip(
                      label: 'Percentage',
                      icon: Icons.percent_rounded,
                      selected: _depositType == 'percent',
                      onTap: () => setState(() => _depositType = 'percent'),
                    ),
                    const SizedBox(width: 8),
                    _DepositTypeChip(
                      label: 'Fixed (GHS)',
                      icon: Icons.attach_money_rounded,
                      selected: _depositType == 'fixed',
                      onTap: () => setState(() => _depositType = 'fixed'),
                    ),
                  ]),

                  // Value field — only shown when type isn't 'none'
                  if (_depositType != 'none') ...[
                    const SizedBox(height: 16),
                    _Field(
                      label: _depositType == 'percent'
                          ? 'Deposit Percentage (%)'
                          : 'Deposit Amount (GHS per slot)',
                      controller: _depositValue,
                      hint: _depositType == 'percent'
                          ? 'e.g. 30  (means 30% of total)'
                          : 'e.g. 200  (per slot booked)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (_depositType == 'none') return null;
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Enter a valid number';
                        if (_depositType == 'percent' && n > 100)
                          return 'Max 100%';
                        return null;
                      },
                    ),

                    // Live preview
                    _DepositPreview(
                        type: _depositType, rawValue: _depositValue.text),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // ── Payment ─────────────────────────────────
              _Section(
                title: 'Payment Methods',
                icon: Icons.account_balance_wallet_outlined,
                children: [
                  _Field(
                    label: 'Mobile Money (MoMo)',
                    controller: _momo,
                    hint: 'e.g. 024XXXXXXX (MTN MoMo)',
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Cash',
                    controller: _cash,
                    hint: 'e.g. Pay on arrival',
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Bank Transfer',
                    controller: _bank,
                    hint: 'Account name / number / bank',
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Other',
                    controller: _other,
                    hint: 'Any other payment info',
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Media ───────────────────────────────────
              _Section(
                title: 'Photos',
                icon: Icons.photo_library_outlined,
                children: [
                  _ImagePickerField(
                    label: 'Main Cover Photo',
                    controller: _mainImage,
                    folder: 'hostels/main',
                  ),
                  const SizedBox(height: 16),
                  _MultiImagePickerField(
                    label: 'Gallery Photos',
                    controller: _galleryImages,
                    folder: 'hostels/gallery',
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Location ────────────────────────────────
              _Section(
                title: 'Location',
                icon: Icons.map_outlined,
                children: [
                  _Field(
                    label: 'Google Maps Link',
                    controller: _googleMap,
                    hint: 'https://maps.google.com/...',
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DEPOSIT TYPE CHIP
// ─────────────────────────────────────────────────────────────
class _DepositTypeChip extends StatelessWidget {
  const _DepositTypeChip({
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
              color: selected ? _C.green : _C.pageBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? _C.green : _C.border, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 18, color: selected ? Colors.white : _C.textLight),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : _C.textLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// DEPOSIT PREVIEW — live calculation example
// ─────────────────────────────────────────────────────────────
class _DepositPreview extends StatelessWidget {
  const _DepositPreview({required this.type, required this.rawValue});
  final String type;
  final String rawValue;

  @override
  Widget build(BuildContext context) {
    final val = double.tryParse(rawValue.trim()) ?? 0.0;
    if (val <= 0) return const SizedBox.shrink();

    String preview;
    if (type == 'percent') {
      // Example: 30% of GHS 1000 room = GHS 300
      const examplePrice = 1000.0;
      final dep = examplePrice * val / 100;
      preview =
          'Example: ${val.toStringAsFixed(0)}% of GHS ${examplePrice.toStringAsFixed(0)} room = '
          'GHS ${dep.toStringAsFixed(2)} deposit';
    } else {
      preview =
          'Student pays GHS ${val.toStringAsFixed(2)} deposit per slot booked';
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _C.green.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined, size: 13, color: _C.green),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              preview,
              style: const TextStyle(
                  fontSize: 11, color: _C.green, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SINGLE IMAGE PICKER FIELD
// ─────────────────────────────────────────────────────────────
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
      final url = await _uploadToCloudinary(folder: widget.folder);
      if (url != null && mounted) {
        widget.controller.text = url;
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: _C.red,
        ));
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
        Text(widget.label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _C.textDark)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _C.border),
                borderRadius: BorderRadius.circular(8),
                color: _C.pageBg,
              ),
              child: Text(
                url.isEmpty ? 'No image selected' : url,
                style: TextStyle(
                    fontSize: 11,
                    color: url.isEmpty ? _C.textMuted : _C.textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _pick,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_rounded,
                    size: 16, color: Colors.white),
            label: Text(
              _uploading ? 'Uploading…' : 'Upload',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.green,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        if (url.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 140,
                      color: _C.pageBg,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2))),
              errorBuilder: (_, __, ___) => _brokenImage(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _brokenImage() => Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.broken_image_outlined,
              color: Colors.red.shade400, size: 16),
          const SizedBox(width: 6),
          Text('Could not load image',
              style: TextStyle(color: Colors.red.shade400, fontSize: 11)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
// MULTI IMAGE PICKER FIELD
// ─────────────────────────────────────────────────────────────
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

  Future<void> _addMore() async {
    setState(() => _uploading = true);
    try {
      final url = await _uploadToCloudinary(folder: widget.folder);
      if (url != null && mounted) {
        final current = _urls;
        current.add(url);
        _setUrls(current);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: _C.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _remove(int index) {
    final current = _urls;
    current.removeAt(index);
    _setUrls(current);
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    const thumbSize = 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textDark)),
          ),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _addMore,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_photo_alternate_outlined,
                    size: 16, color: Colors.white),
            label: Text(
              _uploading ? 'Uploading…' : 'Add Photo',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.green,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (urls.isEmpty)
          Container(
            height: thumbSize,
            decoration: BoxDecoration(
              border: Border.all(color: _C.border),
              borderRadius: BorderRadius.circular(8),
              color: _C.pageBg,
            ),
            child: const Center(
              child: Text('No gallery photos yet',
                  style: TextStyle(fontSize: 12, color: _C.textMuted)),
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
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _remove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 12),
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

// ─────────────────────────────────────────────────────────────
// SECTION WRAPPER
// ─────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// REUSABLE TEXT FIELD
// ─────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.maxLines = 1,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.textDark)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            validator: validator,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 13, color: _C.textDark),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 13, color: _C.textMuted),
              filled: true,
              fillColor: _C.pageBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _C.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _C.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _C.green, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _C.red),
              ),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────
// SCHOOL PICKER
// ─────────────────────────────────────────────────────────────
class _SchoolPicker extends StatelessWidget {
  const _SchoolPicker({
    required this.schools,
    required this.loaded,
    required this.selectedId,
    required this.onSelected,
  });
  final List<School> schools;
  final bool loaded;
  final String? selectedId;
  final void Function(School) onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = schools.where((s) => s.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nearest School *',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _C.textDark)),
        const SizedBox(height: 6),
        InkWell(
          onTap: loaded ? () => _showSheet(context) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _C.pageBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _C.border),
            ),
            child: Row(children: [
              const Icon(Icons.school_rounded, size: 16, color: _C.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected?.fullName ??
                      (loaded ? 'Select a school' : 'Loading...'),
                  style: TextStyle(
                      fontSize: 13,
                      color: selected != null ? _C.textDark : _C.textMuted),
                ),
              ),
              const Icon(Icons.expand_more_rounded,
                  size: 18, color: _C.textMuted),
            ]),
          ),
        ),
      ],
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, ctrl) => _SchoolSheet(
          schools: schools,
          selectedId: selectedId,
          scrollController: ctrl,
          onSelected: (s) {
            onSelected(s);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

class _SchoolSheet extends StatefulWidget {
  const _SchoolSheet({
    required this.schools,
    required this.selectedId,
    required this.scrollController,
    required this.onSelected,
  });
  final List<School> schools;
  final String? selectedId;
  final ScrollController scrollController;
  final void Function(School) onSelected;

  @override
  State<_SchoolSheet> createState() => _SchoolSheetState();
}

class _SchoolSheetState extends State<_SchoolSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.schools
        : widget.schools
            .where((s) =>
                s.fullName.toLowerCase().contains(_q.toLowerCase()) ||
                s.shortName.toLowerCase().contains(_q.toLowerCase()))
            .toList();

    return Column(children: [
      Container(
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
            color: _C.border, borderRadius: BorderRadius.circular(2)),
      ),
      const Text('Select School',
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: _C.textDark)),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Search schools...',
            prefixIcon:
                const Icon(Icons.search_rounded, size: 18, color: _C.textMuted),
            filled: true,
            fillColor: _C.pageBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _C.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _C.border)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ListView.builder(
          controller: widget.scrollController,
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final s = filtered[i];
            final selected = s.id == widget.selectedId;
            return ListTile(
              onTap: () => widget.onSelected(s),
              title: Text(s.fullName,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: _C.textDark)),
              subtitle: Text(s.shortName,
                  style: const TextStyle(fontSize: 11, color: _C.textMuted)),
              trailing: selected
                  ? const Icon(Icons.check_circle_rounded,
                      color: _C.green, size: 18)
                  : null,
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
// DURATION DROPDOWN
// ─────────────────────────────────────────────────────────────
class _DurationDropdown extends StatelessWidget {
  const _DurationDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  static const _options = [
    'per year',
    'per semester',
    'per month',
    'per Academic year',
    'per week',
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Duration Type',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.textDark)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _options.contains(value) ? value : 'per year',
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13, color: _C.textDark),
            decoration: InputDecoration(
              filled: true,
              fillColor: _C.pageBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _C.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _C.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _C.green, width: 1.5)),
            ),
            items: _options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
          ),
        ],
      );
}
