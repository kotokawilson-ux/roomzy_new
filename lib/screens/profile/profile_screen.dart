// lib/profile/profile_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Main ProfileScreen StatefulWidget: animation controllers, Firestore stream,
// auth actions, and the top-level build / scaffold.
// Imports all other profile_*.dart files.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'profile_constants.dart';
import 'profile_upload.dart';
import 'profile_widgets.dart';
import 'profile_hero.dart';
import 'profile_cards.dart';
import 'profile_settings.dart';
import 'profile_sheets.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  ProfileScreen
// ══════════════════════════════════════════════════════════════════════════════
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  // ── Firebase ────────────────────────────────────────────────────────────────
  final _auth = FirebaseAuth.instance;
  final _store = FirebaseFirestore.instance;

  User? get _user => _auth.currentUser;
  String get _uid => _user?.uid ?? '';

  // ── Animation controllers ───────────────────────────────────────────────────
  late final AnimationController _fadeCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _progressCtrl;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _shimmerAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _progressAnim;

  // ── Upload state ────────────────────────────────────────────────────────────
  bool _uploading = false;
  double _uploadProgress = 0;

  // ── Notifications toggle ────────────────────────────────────────────────────
  bool _notificationsOn = true;

  // ── Completion progress (driven by Firestore snapshot) ─────────────────────
  double _completionTarget = 0;

  // ── Referral code (cached to avoid re-generating on every rebuild) ──────────
  String? _referralCode;

  // ── Unread notification count ───────────────────────────────────────────────
  int _unread = 0;

  // ── ImagePicker ─────────────────────────────────────────────────────────────
  final _picker = ImagePicker();

  // ── Firestore stream ─────────────────────────────────────────────────────────
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream;

  // ── Rate-limit guard for _fetchUnread ────────────────────────────────────────
  // FIX #9 (preview): prevents _fetchUnread firing on every snapshot.
  DateTime? _lastUnreadFetch;

  // ────────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initStream();
    _fetchUnread();
  }

  // ── Animation setup ─────────────────────────────────────────────────────────
  void _initAnimations() {
    // Section fade-in (runs once on mount)
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Shimmer on loyalty bar (runs forever while screen is visible)
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _shimmerAnim = _shimmerCtrl;

    // Pulse ring behind avatar
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Profile completion ring (animated to new value on each snapshot)
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _progressAnim = CurvedAnimation(
      parent: _progressCtrl,
      curve: Curves.elasticOut,
    );
  }

  // ── Firestore stream ─────────────────────────────────────────────────────────
  void _initStream() {
    _profileStream = _store.collection('users').doc(_uid).snapshots();
  }

  // ── Unread count ─────────────────────────────────────────────────────────────
  // FIX #1: Added `if (!mounted) return` after every await.
  // FIX #9 (preview): Guard added here; full throttle logic applied in build().
  Future<void> _fetchUnread() async {
    if (_uid.isEmpty) return;

    final snap = await _store
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .count()
        .get();

    // ✅ FIX #1: widget may have been disposed while the query was in flight
    if (!mounted) return;

    setState(() => _unread = snap.count ?? 0);
    _lastUnreadFetch = DateTime.now();
  }

  // ── Completion progress ──────────────────────────────────────────────────────
  /// Called once per Firestore snapshot (via addPostFrameCallback so it never
  /// interrupts a build pass).
  void _scheduleProgressUpdate(Map<String, dynamic> data) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ FIX #1: callback fires asynchronously — widget may be gone by then
      if (!mounted) return;

      final count = completionCount(data, _user?.email ?? '');
      final target = count / kCompletionLabels.length;

      // Only restart the animation when the value actually changes.
      if ((target - _completionTarget).abs() < 0.001) return;
      setState(() => _completionTarget = target);
      _progressCtrl
        ..stop()
        ..forward(from: 0);
    });
  }

  // ── Referral code ────────────────────────────────────────────────────────────
  // FIX #1: Added `if (!mounted) return` after every await.
  Future<void> _ensureReferral(Map<String, dynamic> data) async {
    if (_uid.isEmpty) return;

    final existing = data['referralCode'] as String?;
    if (existing != null && existing.isNotEmpty) {
      if (_referralCode != existing) {
        // ✅ FIX #1: even this sync setState is inside a method that may be
        // called from a postFrameCallback — guard defensively.
        if (!mounted) return;
        setState(() => _referralCode = existing);
      }
      return;
    }

    // Generate and persist a new code
    final code = generateReferralCode(_uid);

    // ✅ FIX #1: setState before await is fine; guard after the write
    if (!mounted) return;
    setState(() => _referralCode = code);

    await _store.collection('users').doc(_uid).set(
      {'referralCode': code},
      SetOptions(merge: true),
    );

    // ✅ FIX #1: the Firestore write is async — guard after it completes
    if (!mounted) return;
  }

  // ── Avatar upload ────────────────────────────────────────────────────────────
  // FIX #1: Added `if (!mounted) return` after every await, including inside
  // the onProgress callback and in the finally block.
  Future<void> _pickAndUpload() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );

    // ✅ FIX #1: image picker is async — user may have left the screen
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();

    // ✅ FIX #1: readAsBytes is async
    if (!mounted) return;

    final filename = picked.name;

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    try {
      final url = await cloudinaryUpload(
        bytes,
        filename,
        onProgress: (p) {
          // ✅ FIX #1: progress callback fires repeatedly during upload;
          // widget could be disposed between ticks
          if (!mounted) return;
          setState(() => _uploadProgress = p);
        },
      );

      // ✅ FIX #1: cloudinaryUpload is async
      if (!mounted) return;

      // Append timestamp to bust Flutter's image cache
      final bustedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      await _store.collection('users').doc(_uid).set(
        {'photoUrl': bustedUrl},
        SetOptions(merge: true),
      );

      // ✅ FIX #1: Firestore write is async
      if (!mounted) return;

      await _user?.updatePhotoURL(bustedUrl);

      // ✅ FIX #1: updatePhotoURL is async
      if (!mounted) return;

      _showSnack('Photo updated ✓', success: true);
    } on UploadValidationException catch (e) {
      // ✅ FIX #1: catch block also reached after awaits
      if (!mounted) return;
      _showSnack(e.message);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Upload failed. Please try again.');
      debugPrint('Avatar upload error: $e');
    } finally {
      // ✅ FIX #1: finally always runs — guard before setState
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  // ── Snackbar helper ───────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool success = false}) {
    // ✅ FIX #1: _showSnack is called from async methods — guard at entry
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: success ? kGreen : kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────────
  // FIX #1: Added `if (!mounted) return` after every await.
  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmText: 'Log Out',
      isDestructive: false,
    );

    // ✅ FIX #1: dialog is async
    if (confirmed != true || !mounted) return;

    await _auth.signOut();

    // ✅ FIX #1: signOut is async
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, KRoutes.login);
  }

  // ── Delete account ────────────────────────────────────────────────────────────
  // FIX #1: Added `if (!mounted) return` after every await.
  Future<void> _deleteAccount() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Account',
      message: 'This permanently deletes your account and all data. '
          'This cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );

    // ✅ FIX #1: dialog is async
    if (confirmed != true || !mounted) return;

    try {
      await _store.collection('users').doc(_uid).delete();

      // ✅ FIX #1: Firestore delete is async
      if (!mounted) return;

      await _user?.delete();

      // ✅ FIX #1: Firebase Auth delete is async
      if (!mounted) return;

      Navigator.pushReplacementNamed(context, KRoutes.login);
    } on FirebaseAuthException catch (e) {
      // ✅ FIX #1: catch block reached after awaits
      if (!mounted) return;
      _showSnack(
        e.code == 'requires-recent-login'
            ? 'Please log out and log back in before deleting your account.'
            : 'Could not delete account: ${e.message}',
      );
    }
  }

  // ── Notifications toggle ──────────────────────────────────────────────────────
  // FIX #1: Added `if (!mounted) return` after the Firestore write.
  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsOn = value);

    await _store.collection('users').doc(_uid).set(
      {'notificationsEnabled': value},
      SetOptions(merge: true),
    );

    // ✅ FIX #1: Firestore write is async — guard in case widget was disposed
    // while the write was in flight (e.g. user navigated away quickly)
    if (!mounted) return;
  }

  // ── dispose ───────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _profileStream,
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? {};

            // Side-effects triggered by a new snapshot (never during build).
            // FIX #9 (preview): _fetchUnread is now throttled — only fires
            // when data changes AND at least 2 min have passed since last fetch.
            if (snapshot.hasData) {
              _scheduleProgressUpdate(data);
              _ensureReferral(data);

              // Sync notifications toggle from Firestore
              final notifPref = data['notificationsEnabled'] as bool?;
              if (notifPref != null && notifPref != _notificationsOn) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  // ✅ FIX #1: postFrameCallback is async
                  if (!mounted) return;
                  setState(() => _notificationsOn = notifPref);
                });
              }

              // Throttled unread fetch: only re-fetch when enough time has
              // passed since the last call (avoids a Firestore read on every
              // single document snapshot).
              final shouldFetch = _lastUnreadFetch == null ||
                  DateTime.now().difference(_lastUnreadFetch!) >
                      const Duration(minutes: 2);
              if (shouldFetch) _fetchUnread();
            }

            final name =
                data['name'] as String? ?? _user?.displayName ?? 'User';
            final email = data['email'] as String? ?? _user?.email ?? '';
            final photoUrl = data['photoUrl'] as String? ?? _user?.photoURL;
            final phone = data['phone'] as String? ?? '';
            final role = data['role'] as String? ?? 'Student';
            final points = (data['loyaltyPoints'] as num?)?.toInt() ?? 0;
            final bookings = (data['totalBookings'] as num?)?.toInt() ?? 0;
            final saved = (data['savedCount'] as num?)?.toInt() ?? 0;
            final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;

            return FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Hero header ──────────────────────────────────────────
                  ProfileHero(
                    name: name,
                    email: email,
                    photoUrl: photoUrl,
                    role: role,
                    bookings: bookings,
                    saved: saved,
                    rating: rating,
                    unread: _unread,
                    uploading: _uploading,
                    uploadProgress: _uploadProgress,
                    pulseAnim: _pulseAnim,
                    onAvatarTap: _pickAndUpload,
                    onNotifTap: () =>
                        Navigator.pushNamed(context, '/notifications'),
                    onShareTap: () => showReferralSheet(
                      context,
                      referralCode: _referralCode ?? generateReferralCode(_uid),
                    ),
                  ),

                  // ── Body sections ────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Completion card
                        ProfileCompletionCard(
                          data: data,
                          email: email,
                          progressAnim: _progressAnim,
                          completionTarget: _completionTarget,
                          onEditTap: () => showEditProfileSheet(
                            context,
                            uid: _uid,
                            data: data,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Loyalty card
                        ProfileLoyaltyCard(
                          points: points,
                          shimmerAnim: _shimmerAnim,
                        ),
                        const SizedBox(height: 20),

                        // Quick actions grid
                        ProfileQuickActions(
                          onTap: (route) => Navigator.pushNamed(context, route),
                        ),
                        const SizedBox(height: 28),

                        // Settings sections
                        ProfileSettings(
                          notificationsOn: _notificationsOn,
                          onNotifToggle: _toggleNotifications,
                          onLogout: _logout,
                          onDeleteAccount: _deleteAccount,
                          onTapRoute: (route) =>
                              Navigator.pushNamed(context, route),
                          uid: _uid,
                          data: data,
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}
