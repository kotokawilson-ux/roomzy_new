// lib/screens/admin/panes/settings_pane.dart
// ─────────────────────────────────────────────────────────────────────────────
// RoomzyFind — Admin Settings Pane
// Controls: payment provider, commission, platform features, system status
// API keys are managed on Vercel dashboard — never stored here
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// ── Colour tokens (match your existing theme) ─────────────────────────────────
const _kGreen = Color(0xFF1B4332);
const _kGreenAccent = Color(0xFF2D6A4F);
const _kGreenLight = Color(0xFF4ADE80);
const _kSurface = Color(0xFFFFFFFF);
const _kBg = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE5E7EB);
const _kTextDark = Color(0xFF1F2937);
const _kTextMid = Color(0xFF374151);
const _kTextLight = Color(0xFF6B7280);
const _kTextMuted = Color(0xFF9CA3AF);
const _kOrange = Color(0xFFEA580C);
const _kRed = Color(0xFFDC2626);
const _kBlue = Color(0xFF2563EB);

const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';

final _db = FirebaseFirestore.instance;

bool _isMobile(BuildContext ctx) => MediaQuery.of(ctx).size.width < 600;

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS PANE — root widget
// ─────────────────────────────────────────────────────────────────────────────

class SettingsPane extends StatelessWidget {
  const SettingsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('settings').doc('platform').snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        return SingleChildScrollView(
          padding: EdgeInsets.all(mobile ? 14 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page header ──────────────────────────────────────────────
              _PageHeader(),
              SizedBox(height: mobile ? 20 : 24),

              // ── 1. Payment Provider ──────────────────────────────────────
              _PaymentProviderSection(
                  currentProvider:
                      data['payment_provider']?.toString() ?? 'paystack'),
              SizedBox(height: mobile ? 20 : 28),

              // ── 2. Commission ────────────────────────────────────────────
              _CommissionSection(
                  currentRate:
                      (data['commission_percent'] as num?)?.toDouble() ?? 0.0),
              SizedBox(height: mobile ? 20 : 28),

              // ── 3. Platform Features ─────────────────────────────────────
              _FeaturesSection(data: data),
              SizedBox(height: mobile ? 20 : 28),

              // ── 4. System Status ─────────────────────────────────────────
              const _SystemStatusSection(),
              SizedBox(height: mobile ? 20 : 28),

              // ── 5. Backend / Vercel info ─────────────────────────────────
              const _BackendInfoSection(),
              SizedBox(height: mobile ? 20 : 28),

              // ── 6. About ─────────────────────────────────────────────────
              const _AboutSection(),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Row(children: [
      Container(
        width: mobile ? 38 : 44,
        height: mobile ? 38 : 44,
        decoration: BoxDecoration(
          color: _kGreenAccent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.settings_outlined,
            color: _kGreenAccent, size: mobile ? 18 : 22),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Settings',
            style: TextStyle(
                fontSize: mobile ? 18 : 20,
                fontWeight: FontWeight.w800,
                color: _kTextDark)),
        Text('Platform configuration & controls',
            style: TextStyle(fontSize: mobile ? 11 : 12, color: _kTextLight)),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.title, this.sub});
  final IconData icon;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 15, color: _kGreenAccent),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _kTextDark)),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: _kBorder, height: 1)),
      ]),
      if (sub != null) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 23),
          child: Text(sub!,
              style:
                  const TextStyle(fontSize: 12, color: _kTextLight, height: 1.5)),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD WRAPPER
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ??
          EdgeInsets.all(_isMobile(context) ? 14 : 16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. PAYMENT PROVIDER SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentProviderSection extends StatefulWidget {
  const _PaymentProviderSection({required this.currentProvider});
  final String currentProvider;

  @override
  State<_PaymentProviderSection> createState() =>
      _PaymentProviderSectionState();
}

class _PaymentProviderSectionState extends State<_PaymentProviderSection> {
  bool _saving = false;
  String? _success;
  String? _error;

  Future<void> _switchProvider(String newProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Switch to ${newProvider == 'hubtel' ? 'Hubtel' : 'Paystack'}?',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _kTextDark),
        ),
        content: Text(
          newProvider == 'hubtel'
              ? 'All new payments will process through Hubtel. Landlords receive money within 5 minutes of student payment.\n\nMake sure your Hubtel credentials are set on Vercel before switching.'
              : 'All new payments will process through Paystack. Landlord settlement takes 24–48 hrs.',
          style:
              const TextStyle(fontSize: 13, color: _kTextLight, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: _kTextLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreenAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Confirm',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    try {
      await _db.collection('settings').doc('platform').set({
        'payment_provider': newProvider,
        'provider_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _success =
          'Switched to ${newProvider == 'hubtel' ? 'Hubtel' : 'Paystack'} successfully.');
    } catch (e) {
      setState(() => _error = 'Failed to switch: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final provider = widget.currentProvider;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(
        icon: Icons.credit_card_outlined,
        title: 'Payment Provider',
        sub:
            'Switch which payment processor handles student payments. API keys are managed securely on Vercel — not stored here.',
      ),
      const SizedBox(height: 12),
      _Card(
        child: Column(children: [
          // Provider toggle cards
          Row(children: [
            // Paystack
            Expanded(
              child: _ProviderCard(
                name: 'Paystack',
                subtitle: 'T+1 / T+2 settlement',
                icon: Icons.credit_card_outlined,
                isActive: provider == 'paystack',
                isSaving: _saving,
                onTap: provider == 'paystack'
                    ? null
                    : () => _switchProvider('paystack'),
              ),
            ),
            const SizedBox(width: 10),
            // Hubtel
            Expanded(
              child: _ProviderCard(
                name: 'Hubtel',
                subtitle: 'Instant payout (~5 min)',
                icon: Icons.bolt_outlined,
                isActive: provider == 'hubtel',
                isSaving: _saving,
                onTap: provider == 'hubtel'
                    ? null
                    : () => _switchProvider('hubtel'),
              ),
            ),
          ]),

          const SizedBox(height: 12),

          // Security note
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: _kGreenAccent.withOpacity(0.2)),
            ),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 13, color: _kGreenAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'To update API keys: go to vercel.com → your project → Settings → Environment Variables. Add PAYSTACK_SECRET_KEY or HUBTEL_CLIENT_ID / HUBTEL_CLIENT_SECRET / HUBTEL_MERCHANT_ACCOUNT then redeploy.',
                  style: TextStyle(
                      fontSize: mobile ? 10 : 11,
                      color: _kGreenAccent,
                      height: 1.5),
                ),
              ),
            ]),
          ),

          if (_success != null) ...[
            const SizedBox(height: 10),
            _AlertBanner(
                message: _success!,
                color: _kGreenAccent,
                icon: Icons.check_circle_outline),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            _AlertBanner(
                message: _error!,
                color: _kRed,
                icon: Icons.error_outline),
          ],
        ]),
      ),
    ]);
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.isActive,
    required this.isSaving,
    required this.onTap,
  });
  final String name;
  final String subtitle;
  final IconData icon;
  final bool isActive;
  final bool isSaving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return GestureDetector(
      onTap: isSaving ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(mobile ? 12 : 14),
        decoration: BoxDecoration(
          color: isActive
              ? _kGreenAccent.withOpacity(0.06)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? _kGreenAccent : _kBorder,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isActive
                    ? _kGreenAccent.withOpacity(0.12)
                    : _kBorder.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  size: 15,
                  color: isActive ? _kGreenAccent : _kTextMuted),
            ),
            const Spacer(),
            if (isActive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _kGreenAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Active',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _kGreenAccent)),
              )
            else if (isSaving)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kTextMuted)),
          ]),
          const SizedBox(height: 10),
          Text(name,
              style: TextStyle(
                  fontSize: mobile ? 13 : 14,
                  fontWeight: FontWeight.w700,
                  color: isActive ? _kGreenAccent : _kTextDark)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 10,
                  color: isActive
                      ? _kGreenAccent.withOpacity(0.7)
                      : _kTextMuted)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. COMMISSION SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _CommissionSection extends StatefulWidget {
  const _CommissionSection({required this.currentRate});
  final double currentRate;

  @override
  State<_CommissionSection> createState() => _CommissionSectionState();
}

class _CommissionSectionState extends State<_CommissionSection> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  String? _success;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.currentRate.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final val = double.tryParse(_ctrl.text.trim());
    if (val == null || val < 0 || val > 50) {
      setState(() => _error = 'Enter a value between 0 and 50.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await _db.collection('settings').doc('platform').set({
        'commission_percent': val,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _success =
          'Commission set to ${val.toStringAsFixed(0)}%. Applies to all new bookings.');
    } catch (e) {
      setState(() => _error = 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final rate = double.tryParse(_ctrl.text) ?? widget.currentRate;
    final landlordPct = (100 - rate).clamp(0, 100);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(
        icon: Icons.percent_rounded,
        title: 'Commission Rate',
        sub:
            'Platform fee taken from each payment. Set to 0% now — change when ready to earn revenue.',
      ),
      const SizedBox(height: 12),
      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Rate display
          Container(
            padding: EdgeInsets.all(mobile ? 14 : 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kGreen, _kGreenAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Current rate',
                      style: TextStyle(
                          color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('${rate.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: mobile ? 32 : 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    'GHS 1000 payment → Landlord GHS ${(1000 * landlordPct / 100).toStringAsFixed(0)} · RoomzyFind GHS ${(1000 * rate / 100).toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 10),
                  ),
                ]),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.percent_rounded,
                    color: Colors.white, size: 24),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // Edit row
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,2}$'))
                ],
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                    fontSize: mobile ? 18 : 22,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark),
                decoration: InputDecoration(
                  suffixText: '%',
                  suffixStyle: TextStyle(
                      fontSize: mobile ? 14 : 18,
                      fontWeight: FontWeight.w700,
                      color: _kTextLight),
                  hintText: '0',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _kBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _kBorder)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: _kGreenAccent, width: 1.5)),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : const Icon(Icons.save_rounded,
                        size: 16, color: Colors.white),
                label: Text(_saving ? 'Saving…' : 'Save',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreenAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ]),

          if (_success != null) ...[
            const SizedBox(height: 10),
            _AlertBanner(
                message: _success!,
                color: _kGreenAccent,
                icon: Icons.check_circle_outline),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            _AlertBanner(
                message: _error!,
                color: _kRed,
                icon: Icons.error_outline),
          ],

          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: _kOrange.withOpacity(0.3)),
            ),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Icon(Icons.info_outline_rounded,
                  size: 13, color: _kOrange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Changes apply to new bookings only. Existing bookings keep the rate that was set when they were created.',
                  style: TextStyle(
                      fontSize: 11,
                      color: _kOrange,
                      height: 1.5),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. PLATFORM FEATURES SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({required this.data});
  final Map<String, dynamic> data;

  Future<void> _toggle(String field, bool value) async {
    await _db.collection('settings').doc('platform').set(
      {field: value, 'updated_at': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final features = [
      (
        'bookings_enabled',
        'Student Bookings',
        'Allow students to make new bookings',
        Icons.home_outlined,
        data['bookings_enabled'] as bool? ?? true,
      ),
      (
        'chat_enabled',
        'In-app Chat',
        'Messaging between students and landlords',
        Icons.chat_bubble_outline_rounded,
        data['chat_enabled'] as bool? ?? true,
      ),
      (
        'move_in_enabled',
        'Move-in Confirmation',
        'Move-in date confirmation notifications',
        Icons.calendar_today_outlined,
        data['move_in_enabled'] as bool? ?? true,
      ),
      (
        'registrations_enabled',
        'New Registrations',
        'Allow new students to sign up',
        Icons.person_add_outlined,
        data['registrations_enabled'] as bool? ?? true,
      ),
      (
        'payments_enabled',
        'Payments',
        'Allow payment processing (emergency kill switch)',
        Icons.payment_outlined,
        data['payments_enabled'] as bool? ?? true,
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(
        icon: Icons.toggle_on_outlined,
        title: 'Platform Features',
        sub: 'Enable or disable features across the entire platform instantly.',
      ),
      const SizedBox(height: 12),
      _Card(
        padding: EdgeInsets.zero,
        child: Column(
          children: features.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            final isLast = i == features.length - 1;
            final isFirst = i == 0;
            return _FeatureRow(
              field: f.$1,
              label: f.$2,
              sub: f.$3,
              icon: f.$4,
              value: f.$5,
              isFirst: isFirst,
              isLast: isLast,
              onChanged: (v) => _toggle(f.$1, v),
            );
          }).toList(),
        ),
      ),
    ]);
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.field,
    required this.label,
    required this.sub,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.isFirst = false,
    this.isLast = false,
  });
  final String field;
  final String label;
  final String sub;
  final IconData icon;
  final bool value;
  final void Function(bool) onChanged;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: mobile ? 14 : 16,
          vertical: mobile ? 12 : 14),
      decoration: BoxDecoration(
        border: !isLast
            ? const Border(bottom: BorderSide(color: _kBorder))
            : null,
        borderRadius: isFirst
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : isLast
                ? const BorderRadius.vertical(
                    bottom: Radius.circular(14))
                : null,
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: value
                ? _kGreenAccent.withOpacity(0.10)
                : _kBorder.withOpacity(0.5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon,
              size: 17,
              color: value ? _kGreenAccent : _kTextMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                style: TextStyle(
                    fontSize: mobile ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: _kTextDark)),
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: _kTextLight)),
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: _kGreenAccent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. SYSTEM STATUS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _SystemStatusSection extends StatelessWidget {
  const _SystemStatusSection();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel(
        icon: Icons.monitor_heart_outlined,
        title: 'System Status',
        sub: 'Live status of all platform services.',
      ),
      const SizedBox(height: 12),
      _Card(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _StatusRow(
              label: 'Backend (Vercel)',
              icon: Icons.cloud_outlined,
              status: 'Online',
              isOnline: true,
              isFirst: true),
          _StatusRow(
              label: 'Firestore Database',
              icon: Icons.storage_outlined,
              status: 'Connected',
              isOnline: true),
          _StatusRow(
              label: 'Payment Webhook',
              icon: Icons.webhook_outlined,
              status: 'Receiving',
              isOnline: true),
          _StatusRow(
              label: 'OneSignal Push',
              icon: Icons.notifications_outlined,
              status: 'Active',
              isOnline: true),
          _StatusRow(
              label: 'Cloudinary (Images)',
              icon: Icons.cloud_upload_outlined,
              status: 'Active',
              isOnline: true),
          _StatusRow(
              label: 'Firebase Auth',
              icon: Icons.lock_outline_rounded,
              status: 'Active',
              isOnline: true,
              isLast: true),
        ]),
      ),
    ]);
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.icon,
    required this.status,
    required this.isOnline,
    this.isFirst = false,
    this.isLast = false,
  });
  final String label;
  final IconData icon;
  final String status;
  final bool isOnline;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: mobile ? 14 : 16,
          vertical: mobile ? 12 : 13),
      decoration: BoxDecoration(
        border: !isLast
            ? const Border(bottom: BorderSide(color: _kBorder))
            : null,
        borderRadius: isFirst
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : isLast
                ? const BorderRadius.vertical(
                    bottom: Radius.circular(14))
                : null,
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: _kTextLight),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: mobile ? 12 : 13, color: _kTextDark)),
        ),
        Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isOnline
                  ? const Color(0xFF22C55E)
                  : _kRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(status,
              style: TextStyle(
                  fontSize: mobile ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: isOnline ? _kTextDark : _kRed)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. BACKEND / VERCEL INFO SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _BackendInfoSection extends StatelessWidget {
  const _BackendInfoSection();

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel(
        icon: Icons.dns_outlined,
        title: 'Backend Configuration',
        sub:
            'API keys are never stored in this app. Manage them directly on Vercel.',
      ),
      const SizedBox(height: 12),
      _Card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Backend URL
          _InfoRow(
            label: 'Backend URL',
            value: _kBackendUrl,
            canCopy: true,
          ),
          const SizedBox(height: 10),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 10),

          // Env vars guide
          Text('Environment Variables on Vercel',
              style: TextStyle(
                  fontSize: mobile ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: _kTextDark)),
          const SizedBox(height: 10),

          _EnvVarRow(
            key_: 'PAYSTACK_SECRET_KEY',
            desc: 'Paystack secret key (sk_live_...)',
            provider: 'paystack',
          ),
          _EnvVarRow(
            key_: 'HUBTEL_CLIENT_ID',
            desc: 'Hubtel client ID',
            provider: 'hubtel',
          ),
          _EnvVarRow(
            key_: 'HUBTEL_CLIENT_SECRET',
            desc: 'Hubtel client secret',
            provider: 'hubtel',
          ),
          _EnvVarRow(
            key_: 'HUBTEL_MERCHANT_ACCOUNT',
            desc: 'Hubtel merchant account number',
            provider: 'hubtel',
          ),
          _EnvVarRow(
            key_: 'FIREBASE_SERVICE_ACCOUNT',
            desc: 'Firebase admin SDK credentials',
            provider: 'system',
          ),

          const SizedBox(height: 10),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 10),

          // Link to Vercel
          GestureDetector(
            onTap: () {
              // openLink('https://vercel.com/dashboard');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kGreenAccent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _kGreenAccent.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.open_in_new_rounded,
                    size: 14, color: _kGreenAccent),
                const SizedBox(width: 8),
                Text('Open Vercel Dashboard',
                    style: TextStyle(
                        fontSize: mobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: _kGreenAccent)),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 12, color: _kGreenAccent),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.label,
      required this.value,
      this.canCopy = false});
  final String label;
  final String value;
  final bool canCopy;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Row(children: [
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: _kTextLight)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: mobile ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: _kTextDark),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
      if (canCopy)
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 2),
              backgroundColor: _kGreenAccent,
            ));
          },
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _kGreenAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.copy_outlined,
                size: 13, color: _kGreenAccent),
          ),
        ),
    ]);
  }
}

class _EnvVarRow extends StatelessWidget {
  const _EnvVarRow({
    required this.key_,
    required this.desc,
    required this.provider,
  });
  final String key_;
  final String desc;
  final String provider; // 'paystack' | 'hubtel' | 'system'

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (provider) {
      'paystack' => (_kBlue, 'Paystack'),
      'hubtel' => (_kGreenAccent, 'Hubtel'),
      _ => (_kTextMuted, 'System'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Text(key_,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                      fontFamily: 'monospace')),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ]),
            Text(desc,
                style: const TextStyle(
                    fontSize: 10, color: _kTextMuted)),
          ]),
        ),
        const Text('••••••••',
            style: TextStyle(fontSize: 12, color: _kTextMuted)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. ABOUT SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel(
        icon: Icons.info_outline_rounded,
        title: 'About',
      ),
      const SizedBox(height: 12),
      _Card(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _AboutRow(
              label: 'App', value: 'RoomzyFind', isFirst: true),
          _AboutRow(label: 'Version', value: '1.0.0'),
          _AboutRow(label: 'Platform', value: 'Flutter (Android · iOS · Windows)'),
          _AboutRow(label: 'Backend', value: 'Node.js / Vercel'),
          _AboutRow(label: 'Database', value: 'Firebase Firestore'),
          _AboutRow(
              label: 'Environment',
              value: 'Production',
              isLast: true,
              valueColor: _kGreenAccent),
        ]),
      ),
    ]);
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.label,
    required this.value,
    this.isFirst = false,
    this.isLast = false,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool isFirst;
  final bool isLast;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: mobile ? 14 : 16,
          vertical: mobile ? 11 : 13),
      decoration: BoxDecoration(
        border: !isLast
            ? const Border(bottom: BorderSide(color: _kBorder))
            : null,
        borderRadius: isFirst
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : isLast
                ? const BorderRadius.vertical(
                    bottom: Radius.circular(14))
                : null,
      ),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: mobile ? 12 : 13,
                  color: _kTextLight)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: mobile ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _kTextDark)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  const _AlertBanner(
      {required this.message,
      required this.color,
      required this.icon});
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style:
                      TextStyle(fontSize: 12, color: color))),
        ]),
      );
}