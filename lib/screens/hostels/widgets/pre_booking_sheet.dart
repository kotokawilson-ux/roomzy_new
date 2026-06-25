// lib/screens/hostel/widgets/pre_booking_sheet.dart
//
// Pre-booking sheet — teal theme matching RoomzyFind design tokens

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../models/models.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Design tokens (mirrors hostel_detail_screen.dart) ────────────────────────
const _kPrimary = Color(0xFF0F766E);
const _kAccent = Color(0xFF14B8A6);
const _kDark = Color(0xFF0D1B2A);
const _kSurface = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE2E8F0);
const _kTextMuted = Color(0xFF64748B);
const _kTextDim = Color(0xFF94A3B8);
const _kOrange = Color(0xFFEA580C);

// ─── Public entry-point ────────────────────────────────────────────────────────
Future<void> showPreBookingSheet({
  required BuildContext context,
  required Hostel hostel,
  required Room room,
  required UserModel user,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => _PreBookingSheet(hostel: hostel, room: room, user: user),
  );
}

// ─── Sheet ────────────────────────────────────────────────────────────────────
class _PreBookingSheet extends StatefulWidget {
  const _PreBookingSheet({
    required this.hostel,
    required this.room,
    required this.user,
  });
  final Hostel hostel;
  final Room room;
  final UserModel user;

  @override
  State<_PreBookingSheet> createState() => _PreBookingSheetState();
}

class _PreBookingSheetState extends State<_PreBookingSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.username);
    _emailCtrl = TextEditingController(text: widget.user.email);
    _phoneCtrl = TextEditingController(text: widget.user.phone);

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _animCtrl.forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final windowDays = widget.hostel.visitWindowDays.clamp(3, 999);
      final expires = DateTime.now().add(Duration(days: windowDays));

      await FirebaseFirestore.instance.collection('pre_bookings').add({
        'user_id': widget.user.id,
        'student_name': name,
        'email': email,
        'phone': phone,
        'hostel_id': widget.hostel.id,
        'hostel_name': widget.hostel.hostelName,
        'hostel_code': widget.hostel.hostelCode,
        'hostel_phone': widget.hostel.phone, // ← add this
        'landlord_id': widget.hostel.landlordId,
        'room_id': widget.room.id,
        'room_number': widget.room.roomNumber,
        'visit_window_days': windowDays,
        'created_at': FieldValue.serverTimestamp(),
        'expires_at': Timestamp.fromDate(expires),
        'status': 'active',
        'converted_booking_id': null,
        'conversion_method': null,
        'lost_reason': null,
      });

      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: EdgeInsets.only(bottom: bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            top: false,
            child: _submitted ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  // ── Success ───────────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    final days = widget.hostel.visitWindowDays.clamp(3, 999);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // handle
        _Handle(),
        const SizedBox(height: 24),

        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_kPrimary, _kAccent]),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: _kPrimary.withOpacity(0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 20),

        const Text('Interest Registered!',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: _kDark)),
        const SizedBox(height: 10),

        Text(
          'You\'ve shown interest in Room ${widget.room.roomNumber}. '
          'You have $days day${days == 1 ? '' : 's'} to visit and decide.',
          textAlign: TextAlign.center,
          style:
              const TextStyle(fontSize: 14, color: _kTextMuted, height: 1.55),
        ),
        const SizedBox(height: 14),

        // disclaimer
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kOrange.withOpacity(0.25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded, color: _kOrange, size: 16),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'This slot hasn\'t been reserved — it\'s still open to everyone until someone completes a full booking.',
                style: TextStyle(fontSize: 12.5, color: _kOrange, height: 1.5),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        const SizedBox(height: 24),

        // ── Call Hostel button ─────────────────────────────────────────────
        if ((widget.hostel.phone ?? '').isNotEmpty) ...[
          GestureDetector(
            onTap: () {
              final phones = widget.hostel.phone!
                  .split(RegExp(r'[,\s/]+'))
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final number = phones.isNotEmpty ? phones.first : '';
              if (number.isNotEmpty) {
                launchUrl(Uri.parse('tel:$number'));
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFFEFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kPrimary.withOpacity(0.45)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone_rounded, size: 15, color: _kPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'Call Hostel · ${widget.hostel.phone!.split(RegExp(r"[,\s/]+")).first.trim()}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Done',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  // ── Form ──────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    final days = widget.hostel.visitWindowDays.clamp(3, 999);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // handle
            Center(child: _Handle()),
            const SizedBox(height: 20),

            // ── Header ──────────────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kPrimary, _kAccent]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bookmark_add_outlined,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pre-book this Room',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _kDark)),
                      Text(
                        'Room ${widget.room.roomNumber} · ${widget.hostel.hostelName}',
                        style:
                            const TextStyle(fontSize: 12.5, color: _kTextMuted),
                      ),
                    ]),
              ),
            ]),
            const SizedBox(height: 18),

            // ── Visit window pill ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kPrimary.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.timer_outlined, color: _kPrimary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, height: 1.4),
                      children: [
                        TextSpan(
                          text: '$days-day visit window. ',
                          style: const TextStyle(
                              color: _kPrimary, fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(
                          text:
                              'Visit the hostel and decide before it expires.',
                          style: TextStyle(color: _kTextMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Fields ────────────────────────────────────────────────────────────
            _Field(label: 'Full name', controller: _nameCtrl),
            const SizedBox(height: 14),
            _Field(
                label: 'Email',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _Field(
                label: 'Phone',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone),

            // ── Error ─────────────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFDC2626), size: 14),
                const SizedBox(width: 6),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFDC2626), fontSize: 12.5)),
              ]),
            ],

            // ── Disclaimer ────────────────────────────────────────────────────────
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kOrange.withOpacity(0.3)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded,
                    color: _kOrange, size: 14),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'This slot is not reserved. Anyone can book it until full payment is made.',
                    style:
                        TextStyle(fontSize: 11.5, color: _kOrange, height: 1.5),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── CTA ───────────────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: _submitting
                  ? Container(
                      decoration: BoxDecoration(
                        gradient:
                            const LinearGradient(colors: [_kPrimary, _kAccent]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white)),
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient:
                            const LinearGradient(colors: [_kPrimary, _kAccent]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: _kPrimary.withOpacity(0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 5)),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Register Interest',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
            ),
          ]),
    );
  }
}

// ─── Handle ───────────────────────────────────────────────────────────────────
class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

// ─── Field ────────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 14, color: _kDark),
            cursorColor: _kPrimary,
            decoration: InputDecoration(
              filled: true,
              fillColor: _kSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5),
              ),
            ),
          ),
        ],
      );
}

// ─── Active pre-booking countdown card ────────────────────────────────────────
// Drop inside hostel_detail_screen wherever a room card is rendered.
//
//   PreBookingStatusCard(
//     preBooking: _activePreBooking!,
//     onProceed: () { ... },
//     onCancel:  () { ... },
//   )

class PreBookingStatusCard extends StatelessWidget {
  const PreBookingStatusCard({
    super.key,
    required this.preBooking,
    required this.onProceed,
    required this.onCancel,
  });
  final PreBooking preBooking;
  final VoidCallback onProceed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final days = preBooking.daysRemaining;
    final isUrgent = days <= 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUrgent ? const Color(0xFFFFF7ED) : _kPrimary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUrgent
              ? _kOrange.withOpacity(0.4)
              : _kPrimary.withOpacity(0.25),
          width: 1.2,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            isUrgent ? Icons.warning_amber_rounded : Icons.bookmark_rounded,
            color: isUrgent ? _kOrange : _kPrimary,
            size: 17,
          ),
          const SizedBox(width: 8),
          Text(
            isUrgent ? 'Expiring soon!' : 'Pre-booking active',
            style: TextStyle(
                color: isUrgent ? _kOrange : _kPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isUrgent
                  ? _kOrange.withOpacity(0.12)
                  : _kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              days == 0
                  ? 'Expires today'
                  : '$days day${days == 1 ? '' : 's'} left',
              style: TextStyle(
                  color: isUrgent ? _kOrange : _kPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'You\'ve registered interest in Room ${preBooking.roomNumber}. '
          'Visit the hostel to verify, then proceed to book.',
          style:
              const TextStyle(color: _kTextMuted, fontSize: 12.5, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: onProceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Proceed to Book',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _kTextDim.withOpacity(0.5), width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Cancel',
                  style: TextStyle(color: _kTextMuted, fontSize: 13)),
            ),
          ),
        ]),
      ]),
    );
  }
}
