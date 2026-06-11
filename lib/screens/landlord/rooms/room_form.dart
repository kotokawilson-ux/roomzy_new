// lib/screens/landlord/rooms/room_form.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Add / Edit Room Form
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
}

// ─────────────────────────────────────────────────────────────
// ROOM FORM
// ─────────────────────────────────────────────────────────────
class RoomForm extends StatefulWidget {
  const RoomForm({
    super.key,
    required this.landlordId,
    required this.service,
    required this.hostels,
    this.room,
    this.preselectedHostelId,
  });

  final String landlordId;
  final LandlordService service;
  final List<Hostel> hostels;
  final Room? room;
  final String? preselectedHostelId;

  @override
  State<RoomForm> createState() => _RoomFormState();
}

class _RoomFormState extends State<RoomForm> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool get _isEdit => widget.room != null;

  // Controllers
  late final TextEditingController _roomNumber;
  late final TextEditingController _price;
  late final TextEditingController _capacity;

  late String _type;
  late bool _available;
  late String? _selectedHostelId;

  static const _roomTypes = [
    'Single',
    'Single Ensuite',
    'Double',
    'Double Ensuite',
    'Triple',
    'Triple Ensuite',
    'Quad',
    'Studio',
    'Suite',
    'Dormitory'
        'Chamber and Hall',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.room;
    _roomNumber = TextEditingController(text: r?.roomNumber ?? '');
    _price = TextEditingController(
        text: r != null ? r.price.toStringAsFixed(0) : '');
    _capacity =
        TextEditingController(text: r != null ? r.capacity.toString() : '');
    _type = r?.type ?? 'Single';
    _available = r?.available ?? true;
    _selectedHostelId = r?.hostelId ??
        widget.preselectedHostelId ??
        (widget.hostels.isNotEmpty ? widget.hostels.first.id : null);
  }

  @override
  void dispose() {
    _roomNumber.dispose();
    _price.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Hostel? get _selectedHostel =>
      widget.hostels.where((h) => h.id == _selectedHostelId).firstOrNull;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedHostelId == null) {
      _showError('Please select a hostel.');
      return;
    }

    setState(() => _saving = true);

    final hostel = _selectedHostel!;
    final room = Room(
      id: widget.room?.id ?? '',
      hostelId: hostel.id,
      hostelName: hostel.hostelName,
      hostelCode: hostel.hostelCode,
      roomNumber: _roomNumber.text.trim(),
      type: _type,
      capacity: int.tryParse(_capacity.text.trim()) ?? 1,
      price: double.tryParse(_price.text.trim()) ?? 0,
      available: _available,
      booked: widget.room?.booked ?? 0,
    );

    final result = _isEdit
        ? await widget.service.updateRoom(room)
        : await widget.service.addRoom(room);

    setState(() => _saving = false);
    if (!mounted) return;

    final success = _isEdit
        ? (result as ({bool success, String? error})).success
        : (result as ({String? id, String? error})).id != null;
    final error = _isEdit
        ? (result as ({bool success, String? error})).error
        : (result as ({String? id, String? error})).error;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit ? 'Room updated' : 'Room added'),
        backgroundColor: _C.green,
      ));
    } else {
      _showError(error ?? 'Something went wrong.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _C.red),
    );
  }

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
          _isEdit ? 'Edit Room' : 'Add Room',
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
                      _isEdit ? 'Save Changes' : 'Add Room',
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
            children: [
              // ── Hostel selector ──────────────────────────
              _Section(
                title: 'Hostel',
                icon: Icons.apartment_rounded,
                children: [
                  _HostelDropdown(
                    hostels: widget.hostels,
                    selectedId: _selectedHostelId,
                    onChanged: (id) => setState(() => _selectedHostelId = id),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Room Details ─────────────────────────────
              _Section(
                title: 'Room Details',
                icon: Icons.bed_rounded,
                children: [
                  Row(children: [
                    Expanded(
                      child: _Field(
                        label: 'Room Number *',
                        controller: _roomNumber,
                        hint: 'e.g. A1, 101',
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeDropdown(
                        value: _type,
                        onChanged: (v) => setState(() => _type = v ?? 'Single'),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(
                      child: _Field(
                        label: 'Price (GHS) *',
                        controller: _price,
                        hint: 'e.g. 1200',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        label: 'Capacity (slots) *',
                        controller: _capacity,
                        hint: 'e.g. 2',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = int.tryParse(v);
                          if (n == null || n < 1) return 'Min 1';
                          return null;
                        },
                      ),
                    ),
                  ]),

                  const SizedBox(height: 14),

                  // Availability toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _C.pageBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _C.border),
                    ),
                    child: Row(children: [
                      const Icon(Icons.toggle_on_outlined,
                          size: 18, color: _C.textLight),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Available for booking',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _C.textDark)),
                            Text(
                              _available
                                  ? 'Students can book this room'
                                  : 'Room is hidden from students',
                              style: const TextStyle(
                                  fontSize: 11, color: _C.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _available,
                        onChanged: (v) => setState(() => _available = v),
                        activeColor: _C.green,
                      ),
                    ]),
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
                children: children,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// REUSABLE FIELD
// ─────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

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
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
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
// HOSTEL DROPDOWN
// ─────────────────────────────────────────────────────────────
class _HostelDropdown extends StatelessWidget {
  const _HostelDropdown({
    required this.hostels,
    required this.selectedId,
    required this.onChanged,
  });
  final List<Hostel> hostels;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Hostel *',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.textDark)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: selectedId,
            onChanged: onChanged,
            validator: (v) => v == null ? 'Please select a hostel' : null,
            style: const TextStyle(fontSize: 13, color: _C.textDark),
            decoration: InputDecoration(
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
            ),
            items: hostels
                .map((h) => DropdownMenuItem(
                      value: h.id,
                      child: Text(h.hostelName),
                    ))
                .toList(),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────
// TYPE DROPDOWN
// ─────────────────────────────────────────────────────────────
class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  static const _types = [
    'Single',
    'Single Ensuite',
    'Double',
    'Double Ensuite',
    'Triple',
    'Triple Ensuite',
    'Quad',
    'Studio',
    'Suite',
    'Dormitory',
    'Chamber and Hall',
    'Other',
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Room Type *',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.textDark)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13, color: _C.textDark),
            decoration: InputDecoration(
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
            ),
            items: _types
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
          ),
        ],
      );
}
