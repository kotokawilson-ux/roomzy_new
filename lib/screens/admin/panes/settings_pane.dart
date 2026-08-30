// lib/screens/admin/panes/settings_pane.dart
// ─────────────────────────────────────────────────────────────────────────────
// RoomzyFind — Admin Settings Pane (merged, cleaned up)
//
// Writes to Firestore docs that gate real behavior elsewhere in the app:
//   • settings/platform       → commission_percent (read live by
//                                hostel_detail_screen's booking flow &
//                                revenue_pane), bookings_enabled,
//                                chat_enabled, move_in_enabled,
//                                registrations_enabled, payments_enabled
//   • settings/booking_policy → auto_cancel_hours, reminder_days_before
//   • settings/payouts        → require_admin_approval, review_threshold,
//                                max_single_payout (read by the payout API)
//   • settings/system         → maintenance_mode, maintenance_message
//   • settings/notifications  → push_enabled, notify_admin_new_booking,
//                                notify_admin_on_refund
//   • settings/site_stats     → stats (array of 4 {number,label} maps) —
//                                read live by AboutSection._buildStats on
//                                the public site via a Firestore stream.
//   • settings/site_images    → hero_images (list of URLs, home carousel),
//                                hostels_hero_image (single URL) — read
//                                live by HeroSection and HostelsHero on the
//                                public site via Firestore streams.
//
// NOTE — Firestore rules: settings/site_stats and settings/site_images are
// rendered on public pages (About, Home hero, Hostels search) that logged-
// out visitors can see. The blanket `settings/{id} → allow read: if
// isSignedIn()` rule blocks that. firestore.rules needs explicit public-read
// carve-outs for exactly those two docs — see the accompanying rules file.
// Every other settings/* doc (Paystack keys, payouts, platform switches,
// etc.) stays signed-in-only, which is correct since those are never read
// by public/unauthenticated pages.
//
// REMOVED from the earlier drafts, on purpose:
//   • Paystack/Hubtel provider switcher — Hubtel isn't implemented anywhere
//     in the backend (charge.js, submit-otp.js, paystack.js are all
//     Paystack-only). Flipping that flag would silently break payments
//     since nothing would read/act on "hubtel". Provider is shown as a
//     read-only fact instead, in System Info.
//   • The fake "System Status" panel — it hardcoded every service to a
//     green "Online" dot with no actual check behind it. An admin panel
//     that always says everything is fine is worse than no panel.
//
// Fully responsive: 1 column on mobile, 2-column grid on tablet/desktop.
//
// IMPORTANT — toggles that still need a reader wired up elsewhere:
//   settings/platform.bookings_enabled      → check in hostel_detail_screen
//                                              before allowing a new booking
//   settings/platform.payments_enabled      → check in _proceedToPayment /
//                                              charge.js before calling
//                                              Paystack (emergency kill switch)
//   settings/platform.chat_enabled          → check wherever the chat screen
//                                              is entered
//   settings/platform.registrations_enabled → check in the sign-up flow
//   settings/platform.move_in_enabled       → check wherever move-in
//                                              confirmation is triggered
//   settings/system.maintenance_mode        → check at app startup /
//                                              go_router redirect
//   settings/booking_policy.*               → needs a scheduled Cloud
//                                              Function to act on it
//   settings/payouts.*                      → read server-side inside
//                                              initiateLandlordPayout.js
//   settings/site_stats.stats               → already read live by
//                                              AboutSection._buildStats
//   settings/site_images.*                  → already read live by
//                                              HeroSection & HostelsHero
// This pane stores the values correctly; it does not by itself enforce them
// (site_stats and site_images are the exceptions — those are already wired
// end-to-end, provided the Firestore rules allow public read on them).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
// ─────────────────────────────────────────────────────────────────────────────
// THEME TOKENS
// ─────────────────────────────────────────────────────────────────────────────

const _kGreen = Color(0xFF1B4332);
const _kGreenAccent = Color(0xFF2D6A4F);
const _kBg = Color(0xFFF2F4F0);
const _kSurface = Color(0xFFFFFFFF);
const _kSurfaceAlt = Color(0xFFF9FAFB);
const _kBorder = Color(0xFFE5E7EB);
const _kTextDark = Color(0xFF111827);
const _kTextMid = Color(0xFF374151);
const _kTextLight = Color(0xFF6B7280);
const _kTextMuted = Color(0xFF9CA3AF);
const _kOrange = Color(0xFFEA580C);
const _kRed = Color(0xFFDC2626);
const _kBlue = Color(0xFF2563EB);
const _kPurple = Color(0xFF7C3AED);

const _kBackendUrl = 'https://roomzy-backend-eight.vercel.app/api';

bool _isMobile(BuildContext c) => MediaQuery.of(c).size.width < 640;

final _db = FirebaseFirestore.instance;

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PANE
// ─────────────────────────────────────────────────────────────────────────────

class SettingsPane extends StatefulWidget {
  const SettingsPane({super.key});

  @override
  State<SettingsPane> createState() => _SettingsPaneState();
}

class _SettingsPaneState extends State<SettingsPane> {
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic> _platform = {};
  Map<String, dynamic> _bookingPolicy = {};
  Map<String, dynamic> _payouts = {};
  Map<String, dynamic> _system = {};
  Map<String, dynamic> _notifications = {};
  Map<String, dynamic> _siteStats = {};
  Map<String, dynamic> _siteImages = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _db.collection('settings').doc('platform').get(),
        _db.collection('settings').doc('booking_policy').get(),
        _db.collection('settings').doc('payouts').get(),
        _db.collection('settings').doc('system').get(),
        _db.collection('settings').doc('notifications').get(),
        _db.collection('settings').doc('site_stats').get(),
        _db.collection('settings').doc('site_images').get(),
      ]);
      if (!mounted) return;
      setState(() {
        _platform = results[0].data() ?? {};
        _bookingPolicy = results[1].data() ?? {};
        _payouts = results[2].data() ?? {};
        _system = results[3].data() ?? {};
        _notifications = results[4].data() ?? {};
        _siteStats = results[5].data() ?? {};
        _siteImages = results[6].data() ?? {};
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _kGreenAccent));
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: _kRed, size: 32),
              const SizedBox(height: 10),
              Text('Couldn\'t load settings\n$_loadError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _kTextLight, fontSize: 12)),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _loadAll,
                style: ElevatedButton.styleFrom(backgroundColor: _kGreenAccent),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final mobile = _isMobile(context);
    final twoCol = !mobile;

    return Container(
      color: _kBg,
      child: Column(
        children: [
          const _Header(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              color: _kGreenAccent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(mobile ? 14 : 24),
                child: _ResponsiveSectionGrid(
                  twoCol: twoCol,
                  sections: [
                    _PaystackConfigSection(),
                    _PaymentProviderSection(initial: _platform),
                    _PlatformFeaturesSection(initial: _platform),
                    _BookingPolicySection(initial: _bookingPolicy),
                    _PayoutSafetySection(initial: _payouts),
                    _MaintenanceSection(initial: _system),
                    _NotificationsSection(initial: _notifications),
                    _SiteStatsSection(initial: _siteStats),
                    _SiteImagesSection(initial: _siteImages), // ← restored
                  ],
                  fullWidthTrailing: const _SystemInfoCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Container(
      color: _kGreen,
      padding: EdgeInsets.fromLTRB(mobile ? 14 : 24, 16, mobile ? 14 : 24, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.settings_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: mobile ? 16 : 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              Text('Controls that affect the live system',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.72), fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE GRID — 1 col mobile, 2 col tablet/desktop, plus a full-width slot
// ─────────────────────────────────────────────────────────────────────────────

class _ResponsiveSectionGrid extends StatelessWidget {
  final bool twoCol;
  final List<Widget> sections;
  final Widget? fullWidthTrailing;
  const _ResponsiveSectionGrid({
    required this.twoCol,
    required this.sections,
    this.fullWidthTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (!twoCol) {
      children.addAll(sections.map((s) =>
          Padding(padding: const EdgeInsets.only(bottom: 16), child: s)));
    } else {
      for (var i = 0; i < sections.length; i += 2) {
        final second = i + 1 < sections.length ? sections[i + 1] : null;
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: sections[i]),
              const SizedBox(width: 16),
              Expanded(child: second ?? const SizedBox()),
            ],
          ),
        ));
      }
    }

    if (fullWidthTrailing != null) {
      children.add(fullWidthTrailing!);
    }

    return Column(children: children);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED CARD SHELL + FORM CONTROLS
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<Widget> children;
  final Widget? footer;
  const _SettingsCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _kTextDark)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(description,
              style: const TextStyle(
                  fontSize: 12, color: _kTextLight, height: 1.5)),
          const SizedBox(height: 16),
          ...children,
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool saving;
  final bool saved;
  final VoidCallback onTap;
  final Color color;
  const _SaveButton({
    required this.saving,
    required this.saved,
    required this.onTap,
    this.color = _kGreenAccent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: saving ? null : onTap,
        icon: saving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(saved ? Icons.check_rounded : Icons.save_rounded,
                size: 16, color: Colors.white),
        label: Text(
          saving ? 'Saving…' : (saved ? 'Saved' : 'Save changes'),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: saved ? const Color(0xFF16A34A) : color,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final String suffix;
  final TextEditingController ctrl;
  const _NumberField(
      {required this.label, required this.ctrl, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMid)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))
            ],
            decoration: InputDecoration(
              suffixText: suffix.isEmpty ? null : suffix,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              filled: true,
              fillColor: _kSurfaceAlt,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _kGreenAccent, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool busy;
  const _SwitchRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark)),
              Text(sublabel,
                  style: const TextStyle(fontSize: 11, color: _kTextLight)),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _kGreenAccent)),
          ),
        Switch(
          value: value,
          activeColor: _kGreenAccent,
          onChanged: busy ? null : onChanged,
        ),
      ]),
    );
  }
}

void _showSnack(BuildContext context, String msg, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: isError ? _kRed : _kGreenAccent,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    margin: const EdgeInsets.all(16),
  ));
}

// 1. PAYSTACK CONFIGURATION
// ─────────────────────────────────────────────────────────────────────────────
//
// Security model — please read before wiring the backend:
//   • settings/paystack_public  → mode (test/live) + publishable keys.
//     Publishable keys are DESIGNED to be public, safe to store/read here.
//   • settings/paystack_secret  → secret keys. Firestore rule must be
//     WRITE-ONLY for admins: `allow write: if isAdmin(); allow read: if
//     false;`. The Flutter app can set/replace the key but can NEVER read
//     it back — that's intentional, not a bug in this widget.
//   • settings/paystack_meta    → non-secret flags mirroring "is a secret
//     key currently set" so the UI can show a status badge without ever
//     touching the real value.
//   • Your Node backend reads the secret via the Admin SDK
//     (db.collection('settings').doc('paystack_secret').get()), which
//     bypasses Firestore rules entirely — so it can read what the client
//     cannot. This still requires editing paystack.js to fetch the key
//     dynamically instead of from process.env at module load. Not done
//     here yet — send that file over and it'll be wired in properly.
// ─────────────────────────────────────────────────────────────────────────────

class _PaystackConfigSection extends StatefulWidget {
  const _PaystackConfigSection();

  @override
  State<_PaystackConfigSection> createState() => _PaystackConfigSectionState();
}

class _PaystackConfigSectionState extends State<_PaystackConfigSection> {
  bool _loading = true;
  String _mode = 'test'; // 'test' | 'live'
  late final TextEditingController _pubTestCtrl;
  late final TextEditingController _pubLiveCtrl;
  final _secretTestCtrl = TextEditingController();
  final _secretLiveCtrl = TextEditingController();
  bool _secretTestSet = false;
  bool _secretLiveSet = false;
  bool _editingSecretTest = false;
  bool _editingSecretLive = false;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pubTestCtrl = TextEditingController();
    _pubLiveCtrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _db.collection('settings').doc('paystack_public').get(),
        _db.collection('settings').doc('paystack_meta').get(),
      ]);
      final pub = results[0].data() ?? {};
      final meta = results[1].data() ?? {};
      if (!mounted) return;
      setState(() {
        _mode = pub['mode']?.toString() ?? 'test';
        _pubTestCtrl.text = pub['public_key_test']?.toString() ?? '';
        _pubLiveCtrl.text = pub['public_key_live']?.toString() ?? '';
        _secretTestSet = meta['secret_key_test_set'] as bool? ?? false;
        _secretLiveSet = meta['secret_key_live_set'] as bool? ?? false;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _pubTestCtrl.dispose();
    _pubLiveCtrl.dispose();
    _secretTestCtrl.dispose();
    _secretLiveCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final batch = _db.batch();

      final pubRef = _db.collection('settings').doc('paystack_public');
      batch.set(
          pubRef,
          {
            'mode': _mode,
            'public_key_test': _pubTestCtrl.text.trim(),
            'public_key_live': _pubLiveCtrl.text.trim(),
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      // Only write a secret field if the admin actually typed a new one —
      // an empty/untouched field must never overwrite an existing key.
      final secretUpdates = <String, dynamic>{};
      final metaUpdates = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (_editingSecretTest && _secretTestCtrl.text.trim().isNotEmpty) {
        secretUpdates['secret_key_test'] = _secretTestCtrl.text.trim();
        metaUpdates['secret_key_test_set'] = true;
      }
      if (_editingSecretLive && _secretLiveCtrl.text.trim().isNotEmpty) {
        secretUpdates['secret_key_live'] = _secretLiveCtrl.text.trim();
        metaUpdates['secret_key_live_set'] = true;
      }

      if (secretUpdates.isNotEmpty) {
        secretUpdates['updated_at'] = FieldValue.serverTimestamp();
        batch.set(_db.collection('settings').doc('paystack_secret'),
            secretUpdates, SetOptions(merge: true));
      }
      if (metaUpdates.length > 1) {
        batch.set(_db.collection('settings').doc('paystack_meta'), metaUpdates,
            SetOptions(merge: true));
      }

      await batch.commit();

      // Clear the plaintext secret fields from memory immediately after
      // a successful save — never let a typed key linger in a controller.
      setState(() {
        if (_editingSecretTest && _secretTestCtrl.text.trim().isNotEmpty) {
          _secretTestSet = true;
        }
        if (_editingSecretLive && _secretLiveCtrl.text.trim().isNotEmpty) {
          _secretLiveSet = true;
        }
        _secretTestCtrl.clear();
        _secretLiveCtrl.clear();
        _editingSecretTest = false;
        _editingSecretLive = false;
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Save failed: $e';
        });
      }
    }
  }

  Widget _secretField({
    required String label,
    required bool isSet,
    required bool editing,
    required TextEditingController ctrl,
    required VoidCallback onEditToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kTextMid)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isSet ? _kGreenAccent : _kTextMuted).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(isSet ? 'Set' : 'Not set',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: isSet ? _kGreenAccent : _kTextMuted)),
            ),
          ]),
          const SizedBox(height: 6),
          if (!editing)
            InkWell(
              onTap: onEditToggle,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: _kSurfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      isSet ? '••••••••••••••••••••' : 'No key set',
                      style: TextStyle(
                          fontSize: 13,
                          letterSpacing: isSet ? 2 : 0,
                          color: isSet ? _kTextMid : _kTextMuted),
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 15, color: _kTextLight),
                ]),
              ),
            )
          else
            Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'sk_${_mode}_...',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    filled: true,
                    fillColor: _kSurfaceAlt,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _kGreenAccent, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  ctrl.clear();
                  onEditToggle();
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                color: _kTextLight,
                tooltip: 'Cancel',
              ),
            ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _SettingsCard(
        icon: Icons.credit_card_outlined,
        color: _kBlue,
        title: 'Paystack Configuration',
        description: 'Loading…',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        ],
      );
    }

    return _SettingsCard(
      icon: Icons.credit_card_outlined,
      color: _kBlue,
      title: 'Paystack Configuration',
      description: 'Manage keys here instead of editing code. Secret keys are '
          'write-only — once saved, this screen can never display them '
          'again, only whether one is set. The backend must read the '
          'active secret key via the Admin SDK to actually use it.',
      children: [
        // mode switch
        Row(children: [
          Expanded(
            child: _ModeChip(
              label: 'Test mode',
              selected: _mode == 'test',
              color: _kOrange,
              onTap: () => setState(() => _mode = 'test'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ModeChip(
              label: 'Live mode',
              selected: _mode == 'live',
              color: _kGreenAccent,
              onTap: () => setState(() => _mode = 'live'),
            ),
          ),
        ]),
        const SizedBox(height: 14),

        if (_mode == 'live')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kRed.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: _kRed),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live mode charges real money. Double-check the live '
                  'secret key is correct before saving.',
                  style: TextStyle(fontSize: 11.5, color: _kRed),
                ),
              ),
            ]),
          ),

        Text(_mode == 'test' ? 'Test credentials' : 'Live credentials',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _kTextDark)),
        const SizedBox(height: 10),

        _NumberFieldText(
          label: 'Publishable key',
          ctrl: _mode == 'test' ? _pubTestCtrl : _pubLiveCtrl,
          hint: 'pk_${_mode}_...',
        ),
        _secretField(
          label: 'Secret key',
          isSet: _mode == 'test' ? _secretTestSet : _secretLiveSet,
          editing: _mode == 'test' ? _editingSecretTest : _editingSecretLive,
          ctrl: _mode == 'test' ? _secretTestCtrl : _secretLiveCtrl,
          onEditToggle: () => setState(() {
            if (_mode == 'test') {
              _editingSecretTest = !_editingSecretTest;
            } else {
              _editingSecretLive = !_editingSecretLive;
            }
          }),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!,
                style: const TextStyle(fontSize: 11.5, color: _kRed)),
          ),
      ],
      footer: _SaveButton(
          saving: _saving, saved: _saved, onTap: _save, color: _kBlue),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : _kSurfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : _kBorder),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? color : _kTextLight)),
      ),
    );
  }
}

// Plain (non-numeric) text field — publishable keys are alphanumeric, not
// numbers, so this reuses the same visual style as _NumberField without the
// numeric input restriction.
class _NumberFieldText extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController ctrl;
  const _NumberFieldText(
      {required this.label, required this.ctrl, this.hint = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMid)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: hint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              filled: true,
              fillColor: _kSurfaceAlt,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _kGreenAccent, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. PLATFORM FEATURE TOGGLES (instant-write kill switches)
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformFeaturesSection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _PlatformFeaturesSection({required this.initial});

  @override
  State<_PlatformFeaturesSection> createState() =>
      _PlatformFeaturesSectionState();
}

class _PlatformFeaturesSectionState extends State<_PlatformFeaturesSection> {
  late Map<String, bool> _values;
  String? _busyField;

  static const _fields = <(String, String, String, IconData)>[
    (
      'bookings_enabled',
      'Student Bookings',
      'Allow students to start new bookings',
      Icons.home_outlined,
    ),
    (
      'payments_enabled',
      'Payments',
      'Emergency kill switch — stops all payment processing',
      Icons.payment_outlined,
    ),
    (
      'chat_enabled',
      'In-app Chat',
      'Messaging between students, landlords and support',
      Icons.chat_bubble_outline_rounded,
    ),
    (
      'move_in_enabled',
      'Move-in Confirmation',
      'Move-in date confirmation & related notifications',
      Icons.calendar_today_outlined,
    ),
    (
      'registrations_enabled',
      'New Registrations',
      'Allow new students to sign up',
      Icons.person_add_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _values = {
      for (final f in _fields) f.$1: widget.initial[f.$1] as bool? ?? true,
    };
  }

  Future<void> _toggle(String field, bool value) async {
    // If this is the "payments" kill switch being turned OFF, confirm first —
    // it stops revenue immediately for every active booking flow.
    if (field == 'payments_enabled' && value == false) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Disable payments?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          content: const Text(
            'This immediately stops all payment processing platform-wide. '
            'Students will not be able to pay for bookings until you turn '
            'this back on.',
            style: TextStyle(fontSize: 13, color: _kTextLight, height: 1.5),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _kRed),
              child:
                  const Text('Disable', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _busyField = field;
      _values[field] = value; // optimistic
    });
    try {
      await _db.collection('settings').doc('platform').set({
        field: value,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // revert on failure
      if (mounted) {
        setState(() => _values[field] = !value);
        _showSnack(context, 'Failed to update: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busyField = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.toggle_on_outlined,
      color: _kBlue,
      title: 'Platform Feature Switches',
      description:
          'Instant, no separate save step. Each toggle needs a matching '
          'check added where that feature runs (booking screen, payment '
          'call, chat entry point, sign-up flow) to actually enforce it — '
          'this pane stores the flag correctly either way.',
      children: [
        for (final f in _fields)
          _SwitchRow(
            label: f.$2,
            sublabel: f.$3,
            value: _values[f.$1] ?? true,
            busy: _busyField == f.$1,
            onChanged: (v) => _toggle(f.$1, v),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. BOOKING POLICY
// ─────────────────────────────────────────────────────────────────────────────

class _BookingPolicySection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _BookingPolicySection({required this.initial});

  @override
  State<_BookingPolicySection> createState() => _BookingPolicySectionState();
}

class _BookingPolicySectionState extends State<_BookingPolicySection> {
  late final TextEditingController _cancelHoursCtrl;
  late final TextEditingController _reminderDaysCtrl;
  late bool _autoCancelEnabled;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final hours = (widget.initial['auto_cancel_hours'] as num?)?.toInt() ?? 48;
    final reminder =
        (widget.initial['reminder_days_before'] as num?)?.toInt() ?? 3;
    _autoCancelEnabled = widget.initial['auto_cancel_enabled'] == true;
    _cancelHoursCtrl = TextEditingController(text: '$hours');
    _reminderDaysCtrl = TextEditingController(text: '$reminder');
  }

  @override
  void dispose() {
    _cancelHoursCtrl.dispose();
    _reminderDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hours = int.tryParse(_cancelHoursCtrl.text.trim());
    final days = int.tryParse(_reminderDaysCtrl.text.trim());
    if (hours == null || hours < 1) {
      _showSnack(context, 'Enter a valid number of hours', isError: true);
      return;
    }
    if (days == null || days < 0) {
      _showSnack(context, 'Enter a valid number of days', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _db.collection('settings').doc('booking_policy').set({
        'auto_cancel_enabled': _autoCancelEnabled,
        'auto_cancel_hours': hours,
        'reminder_days_before': days,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(context, 'Save failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.event_busy_rounded,
      color: _kOrange,
      title: 'Booking Policy',
      description:
          'Controls when unpaid pending bookings are released back into '
          'availability, and how far ahead of a balance due date students '
          'get reminded. Requires a scheduled backend job to read these '
          'values and act on them — this pane only stores the policy.',
      children: [
        _SwitchRow(
          label: 'Auto-cancel unpaid bookings',
          sublabel: 'Releases the slot if no payment is made in time',
          value: _autoCancelEnabled,
          onChanged: (v) => setState(() => _autoCancelEnabled = v),
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: _autoCancelEnabled ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !_autoCancelEnabled,
            child: _NumberField(
                label: 'Cancel after', ctrl: _cancelHoursCtrl, suffix: 'hours'),
          ),
        ),
        _NumberField(
            label: 'Balance due reminder',
            ctrl: _reminderDaysCtrl,
            suffix: 'days before'),
      ],
      footer: _SaveButton(saving: _saving, saved: _saved, onTap: _save),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. PAYOUT SAFETY
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutSafetySection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _PayoutSafetySection({required this.initial});

  @override
  State<_PayoutSafetySection> createState() => _PayoutSafetySectionState();
}

class _PayoutSafetySectionState extends State<_PayoutSafetySection> {
  late bool _requireApproval;
  late final TextEditingController _reviewThresholdCtrl;
  late final TextEditingController _maxPayoutCtrl;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _requireApproval =
        widget.initial['require_admin_approval'] != false; // default true
    final review =
        (widget.initial['review_threshold'] as num?)?.toDouble() ?? 2000;
    final maxAmt =
        (widget.initial['max_single_payout'] as num?)?.toDouble() ?? 10000;
    _reviewThresholdCtrl =
        TextEditingController(text: review.toStringAsFixed(0));
    _maxPayoutCtrl = TextEditingController(text: maxAmt.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _reviewThresholdCtrl.dispose();
    _maxPayoutCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final review = double.tryParse(_reviewThresholdCtrl.text.trim());
    final maxAmt = double.tryParse(_maxPayoutCtrl.text.trim());
    if (review == null || review < 0) {
      _showSnack(context, 'Enter a valid review threshold', isError: true);
      return;
    }
    if (maxAmt == null || maxAmt <= 0) {
      _showSnack(context, 'Enter a valid max payout amount', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _db.collection('settings').doc('payouts').set({
        'require_admin_approval': _requireApproval,
        'review_threshold': review,
        'max_single_payout': maxAmt,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(context, 'Save failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.shield_rounded,
      color: _kPurple,
      title: 'Payout Safety',
      description:
          'These values should be read server-side by initiateLandlordPayout '
          'before any Paystack Transfer is created — never trust a '
          'client-supplied amount against them. Pairs with tightened '
          'Firestore rules that make payments/payouts backend-write-only.',
      children: [
        _SwitchRow(
          label: 'Require admin approval',
          sublabel:
              'Landlord-initiated payout requests are queued, not sent immediately',
          value: _requireApproval,
          onChanged: (v) => setState(() => _requireApproval = v),
        ),
        _NumberField(
            label: 'Flag for manual review above',
            ctrl: _reviewThresholdCtrl,
            suffix: 'GHS'),
        _NumberField(
            label: 'Maximum single payout',
            ctrl: _maxPayoutCtrl,
            suffix: 'GHS'),
      ],
      footer: _SaveButton(
          saving: _saving, saved: _saved, onTap: _save, color: _kPurple),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. MAINTENANCE MODE
// ─────────────────────────────────────────────────────────────────────────────

class _MaintenanceSection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _MaintenanceSection({required this.initial});

  @override
  State<_MaintenanceSection> createState() => _MaintenanceSectionState();
}

class _MaintenanceSectionState extends State<_MaintenanceSection> {
  late bool _enabled;
  late final TextEditingController _msgCtrl;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial['maintenance_mode'] == true;
    _msgCtrl = TextEditingController(
        text: widget.initial['maintenance_message']?.toString() ??
            "We're making some improvements — check back shortly.");
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Enable maintenance mode?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          content: const Text(
            'This will lock out students and landlords once your app checks '
            'this flag at startup. Admin access is unaffected.',
            style: TextStyle(fontSize: 13, color: _kTextLight, height: 1.5),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _kRed),
              child:
                  const Text('Enable', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _saving = true);
    try {
      await _db.collection('settings').doc('system').set({
        'maintenance_mode': _enabled,
        'maintenance_message': _msgCtrl.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(context, 'Save failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.build_circle_rounded,
      color: _kRed,
      title: 'Maintenance Mode',
      description: 'When enabled, student and landlord apps should check '
          "settings/system.maintenance_mode at startup (e.g. in main.dart's "
          'router redirect) and show a maintenance screen with the message '
          "below instead of the normal app — this pane doesn't enforce that "
          'by itself.',
      children: [
        _SwitchRow(
          label: 'Enable maintenance mode',
          sublabel: 'Blocks student/landlord access, not admin',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 6),
        const Text('Message shown to users',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMid)),
        const SizedBox(height: 6),
        TextField(
          controller: _msgCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(12),
            filled: true,
            fillColor: _kSurfaceAlt,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kRed, width: 1.5)),
          ),
        ),
        if (_enabled) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kRed.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: _kRed),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'This will lock out students and landlords once saved.',
                  style: TextStyle(fontSize: 11.5, color: _kRed),
                ),
              ),
            ]),
          ),
        ],
      ],
      footer: _SaveButton(
          saving: _saving, saved: _saved, onTap: _save, color: _kRed),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. NOTIFICATIONS
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationsSection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _NotificationsSection({required this.initial});

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  late bool _pushEnabled;
  late bool _notifyNewBooking;
  late bool _notifyRefund;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _pushEnabled = widget.initial['push_enabled'] != false; // default true
    _notifyNewBooking = widget.initial['notify_admin_new_booking'] != false;
    _notifyRefund = widget.initial['notify_admin_on_refund'] != false;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _db.collection('settings').doc('notifications').set({
        'push_enabled': _pushEnabled,
        'notify_admin_new_booking': _notifyNewBooking,
        'notify_admin_on_refund': _notifyRefund,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(context, 'Save failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.notifications_active_rounded,
      color: _kBlue,
      title: 'Notifications',
      description:
          'OneSignal push toggle and which admin events trigger a push to '
          'the admin_push_tokens collection.',
      children: [
        _SwitchRow(
          label: 'Push notifications enabled',
          sublabel: 'Master switch for all OneSignal pushes',
          value: _pushEnabled,
          onChanged: (v) => setState(() => _pushEnabled = v),
        ),
        _SwitchRow(
          label: 'Notify admin on new booking',
          sublabel: 'Push sent to admin_push_tokens on every new booking',
          value: _notifyNewBooking,
          onChanged: (v) => setState(() => _notifyNewBooking = v),
        ),
        _SwitchRow(
          label: 'Notify admin on refund',
          sublabel: 'Push sent whenever a refund is processed',
          value: _notifyRefund,
          onChanged: (v) => setState(() => _notifyRefund = v),
        ),
      ],
      footer: _SaveButton(
          saving: _saving, saved: _saved, onTap: _save, color: _kBlue),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. SITE STATS — the four numbers shown in the public "About" section
// ─────────────────────────────────────────────────────────────────────────────
//
// Writes settings/site_stats.stats — an array of exactly 4 {number, label}
// maps, matching the 4 fixed slots AboutSection._buildStats already lays
// out (2x2 on mobile, 1x4 on desktop). Kept to 4 fixed fields rather than
// an add/remove list so the public page's grid never has to change shape.
// AboutSection reads this doc live via a Firestore stream, so edits show
// up on the public site immediately — no redeploy needed.
// ─────────────────────────────────────────────────────────────────────────────

class _SiteStatsSection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _SiteStatsSection({required this.initial});

  @override
  State<_SiteStatsSection> createState() => _SiteStatsSectionState();
}

class _SiteStatsSectionState extends State<_SiteStatsSection> {
  static const _defaults = [
    {'number': '120', 'label': 'Rooms Available'},
    {'number': '75', 'label': 'Happy Residents'},
    {'number': '5', 'label': 'Years of Service'},
    {'number': '20', 'label': 'Staff Members'},
  ];

  late final List<TextEditingController> _numberCtrls;
  late final List<TextEditingController> _labelCtrls;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.initial['stats'];
    final stats = (raw is List && raw.length == 4)
        ? raw.cast<Map<String, dynamic>>()
        : _defaults;
    _numberCtrls = [
      for (final s in stats)
        TextEditingController(text: s['number']?.toString() ?? '')
    ];
    _labelCtrls = [
      for (final s in stats)
        TextEditingController(text: s['label']?.toString() ?? '')
    ];
  }

  @override
  void dispose() {
    for (final c in _numberCtrls) c.dispose();
    for (final c in _labelCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    for (var i = 0; i < 4; i++) {
      if (_numberCtrls[i].text.trim().isEmpty ||
          _labelCtrls[i].text.trim().isEmpty) {
        _showSnack(context, 'Fill in every number and label', isError: true);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await _db.collection('settings').doc('site_stats').set({
        'stats': [
          for (var i = 0; i < 4; i++)
            {
              'number': _numberCtrls[i].text.trim(),
              'label': _labelCtrls[i].text.trim(),
            },
        ],
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(context, 'Save failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.bar_chart_rounded,
      color: _kGreenAccent,
      title: 'Site Stats',
      description:
          'The four numbers shown in the "About" section of the public '
          'site (Rooms Available, Happy Residents, etc.). Edits here '
          'appear on the site immediately — no redeploy needed.',
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == 3 ? 0 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: _NumberFieldText(
                    label: 'Number',
                    ctrl: _numberCtrls[i],
                    hint: 'e.g. 120',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NumberFieldText(
                    label: 'Label',
                    ctrl: _labelCtrls[i],
                    hint: 'e.g. Rooms Available',
                  ),
                ),
              ],
            ),
          ),
      ],
      footer: _SaveButton(
          saving: _saving, saved: _saved, onTap: _save, color: _kGreenAccent),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// CLOUDINARY UPLOAD HELPER — same pattern as rooms_pane.dart's _pickAndUpload,
// duplicated here (private to this file) so Settings doesn't need to import
// across pane files. Same cloud name / upload preset as the rest of the app.
// ─────────────────────────────────────────────────────────────────────────────

const _kSiteImgCloudName = 'dfv9yibba';
const _kSiteImgUploadPreset = 'ml_default';

Future<String?> _siteImgPickAndUpload({String folder = 'site_images'}) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
  );
  if (picked == null) return null;

  final Uint8List bytes = await picked.readAsBytes();
  final filename = picked.name.isNotEmpty
      ? picked.name
      : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_kSiteImgCloudName/image/upload',
  );
  final req = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _kSiteImgUploadPreset
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
    debugPrint('_siteImgPickAndUpload exception: $e');
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SINGLE IMAGE PICKER FIELD — pick from gallery, upload, preview inline.
// Used here for the hostels-search background (one image, one field).
// ─────────────────────────────────────────────────────────────────────────────

class _SingleSiteImagePicker extends StatefulWidget {
  const _SingleSiteImagePicker({
    required this.label,
    required this.controller,
    this.folder = 'site_images',
  });
  final String label;
  final TextEditingController controller;
  final String folder;

  @override
  State<_SingleSiteImagePicker> createState() => _SingleSiteImagePickerState();
}

class _SingleSiteImagePickerState extends State<_SingleSiteImagePicker> {
  bool _uploading = false;

  Future<void> _pick() async {
    setState(() => _uploading = true);
    try {
      final url = await _siteImgPickAndUpload(folder: widget.folder);
      if (url != null && mounted) {
        widget.controller.text = url;
        setState(() {});
      }
    } catch (e) {
      if (mounted) _showSnack(context, 'Upload failed: $e', isError: true);
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
                fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMid)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: _kSurfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                url.isEmpty ? 'No image selected' : url,
                style: TextStyle(
                    fontSize: 11.5,
                    color: url.isEmpty ? _kTextMuted : _kTextMid),
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
            label: Text(_uploading ? '...' : 'Upload',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        if (url.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              url,
              height: 130,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 130,
                      color: _kSurfaceAlt,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
              errorBuilder: (_, __, ___) => Container(
                height: 60,
                decoration: BoxDecoration(
                  color: _kRed.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kRed.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined, color: _kRed, size: 16),
                    const SizedBox(width: 6),
                    Text('Could not load image',
                        style: TextStyle(color: _kRed, fontSize: 11.5)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MULTI IMAGE PICKER — thumbnail strip, "Add Image" uploads + appends,
// tap the × to remove. Used for the home hero carousel.
// ─────────────────────────────────────────────────────────────────────────────

class _MultiSiteImagePicker extends StatefulWidget {
  const _MultiSiteImagePicker({
    required this.label,
    required this.urls,
    required this.onChanged,
    this.folder = 'site_images/hero',
  });
  final String label;
  final List<String> urls;
  final ValueChanged<List<String>> onChanged;
  final String folder;

  @override
  State<_MultiSiteImagePicker> createState() => _MultiSiteImagePickerState();
}

class _MultiSiteImagePickerState extends State<_MultiSiteImagePicker> {
  bool _uploading = false;

  Future<void> _pickMore() async {
    setState(() => _uploading = true);
    try {
      final url = await _siteImgPickAndUpload(folder: widget.folder);
      if (url != null) {
        widget.onChanged([...widget.urls, url]);
      }
    } catch (e) {
      if (mounted) _showSnack(context, 'Upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _remove(int i) {
    final next = [...widget.urls]..removeAt(i);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    const thumb = 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kTextMid)),
          ),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _pickMore,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_photo_alternate_outlined,
                    size: 16, color: Colors.white),
            label: Text(_uploading ? '...' : 'Add Image',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (widget.urls.isEmpty)
          Container(
            height: thumb,
            decoration: BoxDecoration(
              color: _kSurfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: const Center(
              child: Text('No images yet',
                  style: TextStyle(fontSize: 12, color: _kTextMuted)),
            ),
          )
        else
          SizedBox(
            height: thumb,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      widget.urls[i],
                      width: thumb,
                      height: thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: thumb,
                        height: thumb,
                        decoration: BoxDecoration(
                          color: _kRed.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.broken_image_outlined, color: _kRed),
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

// ─────────────────────────────────────────────────────────────────────────────
// 7B. SITE IMAGES — home hero carousel + hostels-search background
// ─────────────────────────────────────────────────────────────────────────────
//
// Same Cloudinary pick-and-upload flow as the Rooms pane's image fields —
// admin taps Upload/Add Image, picks from their device, it uploads and the
// URL fills in automatically. No manual URL pasting required (still works
// if you want to type/paste one directly into the preview box's spot, but
// the primary flow is upload).
//
// Writes settings/site_images:
//   • hero_images        → List<String>, read live by HeroSection.
//   • hostels_hero_image  → single String, read live by HostelsHero.
// ─────────────────────────────────────────────────────────────────────────────

class _SiteImagesSection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _SiteImagesSection({required this.initial});

  @override
  State<_SiteImagesSection> createState() => _SiteImagesSectionState();
}

class _SiteImagesSectionState extends State<_SiteImagesSection> {
  late List<String> _heroUrls;
  late final TextEditingController _hostelsHeroCtrl;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.initial['hero_images'];
    _heroUrls = (raw is List) ? raw.map((e) => e.toString()).toList() : [];
    _hostelsHeroCtrl = TextEditingController(
        text: widget.initial['hostels_hero_image']?.toString() ?? '');
  }

  @override
  void dispose() {
    _hostelsHeroCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_heroUrls.isEmpty) {
      _showSnack(context, 'Add at least one home hero image', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _db.collection('settings').doc('site_images').set({
        'hero_images': _heroUrls,
        'hostels_hero_image': _hostelsHeroCtrl.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(context, 'Save failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.image_outlined,
      color: _kPurple,
      title: 'Site Images',
      description:
          'Home page hero carousel and the hostels-search page background. '
          'Pick an image from your device — it uploads to Cloudinary and '
          'the link fills in automatically, same as the Rooms pane. Edits '
          'appear on the public site immediately after saving.',
      children: [
        _MultiSiteImagePicker(
          label: 'Home hero carousel',
          urls: _heroUrls,
          onChanged: (next) => setState(() => _heroUrls = next),
          folder: 'site_images/hero',
        ),
        const SizedBox(height: 8),
        const Divider(color: _kBorder, height: 24),
        _SingleSiteImagePicker(
          label: 'Hostels-search background (optional)',
          controller: _hostelsHeroCtrl,
          folder: 'site_images/hostels_hero',
        ),
      ],
      footer: _SaveButton(
          saving: _saving, saved: _saved, onTap: _save, color: _kPurple),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// 8. SYSTEM INFO — honest, read-only reference (no fake status claims)
// ─────────────────────────────────────────────────────────────────────────────

class _SystemInfoCard extends StatelessWidget {
  const _SystemInfoCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 0),
      child: _SettingsCard(
        icon: Icons.info_outline_rounded,
        color: _kTextMid,
        title: 'System Info',
        description:
            'Read-only reference. API keys are never stored in this app or '
            'Firestore — they live in Vercel environment variables.',
        children: [
          _InfoRow(label: 'Backend', value: _kBackendUrl, canCopy: true),
          const _InfoRow(
            label: 'Payments provider',
            value: 'Set via Payment Gateway card above',
          ),
          const _InfoRow(label: 'Push provider', value: 'OneSignal'),
          const _InfoRow(label: 'Image hosting', value: 'Cloudinary'),
          const _InfoRow(label: 'Database', value: 'Firebase Firestore'),
          const _InfoRow(label: 'App version', value: '1.0.0'),
          const SizedBox(height: 10),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 10),
          const Text('Env vars set on Vercel (values hidden)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kTextDark)),
          const SizedBox(height: 8),
          const _EnvVarRow(
              key_: 'PAYSTACK_SECRET_KEY', desc: 'Paystack secret key'),
          const _EnvVarRow(
              key_: 'FIREBASE_SERVICE_ACCOUNT',
              desc: 'Firebase Admin SDK credentials'),
          const _EnvVarRow(
              key_: 'ONESIGNAL_REST_API_KEY', desc: 'Server-side push sends'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;
  const _InfoRow(
      {required this.label, required this.value, this.canCopy = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: _kTextLight))),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _kTextDark),
              overflow: TextOverflow.ellipsis),
        ),
        if (canCopy)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              _showSnack(context, 'Copied to clipboard');
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
      ]),
    );
  }
}

class _EnvVarRow extends StatelessWidget {
  final String key_;
  final String desc;
  const _EnvVarRow({required this.key_, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(key_,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                      fontFamily: 'monospace')),
              Text(desc,
                  style: const TextStyle(fontSize: 10, color: _kTextMuted)),
            ],
          ),
        ),
        const Text('••••••••',
            style: TextStyle(fontSize: 12, color: _kTextMuted)),
      ]),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// 1B. PAYMENT PROVIDER SWITCH — the single flag lib/paymentProvider.js reads
// ─────────────────────────────────────────────────────────────────────────────
//
// Writes settings/platform.payment_provider ("paystack" | "moolre").
// getProvider() in the backend reads this live on every charge/verify/OTP
// call, so flipping this takes effect instantly — no redeploy, no app
// update, zero visible change for students/landlords (both show as
// "Mobile Money" either way).
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentProviderSection extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _PaymentProviderSection({required this.initial});

  @override
  State<_PaymentProviderSection> createState() =>
      _PaymentProviderSectionState();
}

class _PaymentProviderSectionState extends State<_PaymentProviderSection> {
  late String _provider; // 'paystack' | 'moolre'
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.initial['payment_provider']?.toString() ?? 'paystack';
  }

  Future<void> _save() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Switch payment gateway?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'Every new student payment will route through '
          '${_provider == 'moolre' ? 'Moolre' : 'Paystack'} immediately after '
          'saving. Existing pending/in-progress payments are not affected.',
          style: const TextStyle(fontSize: 13, color: _kTextLight, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kGreenAccent),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _db.collection('settings').doc('platform').set({
        'payment_provider': _provider,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _saved = true;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(context, 'Save failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.swap_horiz_rounded,
      color: _kGreenAccent,
      title: 'Payment Gateway',
      description: 'Controls which provider handles every student Mobile Money '
          'payment platform-wide. Landlord payouts stay on Paystack '
          'regardless of this setting. Takes effect the moment you save — '
          'no app update needed for students or landlords.',
      children: [
        Row(children: [
          Expanded(
            child: _ModeChip(
              label: 'Paystack',
              selected: _provider == 'paystack',
              color: _kBlue,
              onTap: () => setState(() => _provider = 'paystack'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ModeChip(
              label: 'Moolre',
              selected: _provider == 'moolre',
              color: _kGreenAccent,
              onTap: () => setState(() => _provider = 'moolre'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _kBlue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBlue.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 14, color: _kBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Moolre API credentials (username, public key, account '
                'number, callback secret) live in Vercel environment '
                'variables, not here — same security model as the '
                'Paystack secret key.',
                style: TextStyle(fontSize: 11, color: _kBlue.withOpacity(0.9)),
              ),
            ),
          ]),
        ),
      ],
      footer: _SaveButton(
          saving: _saving, saved: _saved, onTap: _save, color: _kGreenAccent),
    );
  }
}
