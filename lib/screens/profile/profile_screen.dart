// lib/profile/profile_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Main ProfileScreen StatefulWidget: animation controllers, Firestore stream,
// auth actions, and the top-level build / scaffold.
// Imports all other profile_*.dart files.
//
// Changes from the previous version:
//  • Loading state: shows skeleton cards instead of a flash of empty/default
//    data on the very first frame, before Firestore responds.
//  • Error state: snapshot.hasError is now handled with a retry affordance
//    instead of silently falling back to defaults.
//  • Delete Account now cascade-deletes the notifications subcollection
//    (batched) before removing the user doc and the Auth account, so it
//    doesn't leave orphaned data behind.
//  • Pull-to-refresh on the scroll view.
//  • Hero wiring: edit button opens the edit sheet, Bookings/Saved stat
//    tiles navigate, joinedDate now comes from the real Firebase Auth
//    account-creation timestamp instead of being unused.
// ─────────────────────────────────────────────────────────────────────────────

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

  // ── Account deletion state ──────────────────────────────────────────────────
  bool _deleting = false;

  // ── ImagePicker ─────────────────────────────────────────────────────────────
  final _picker = ImagePicker();

  // ── Firestore stream ─────────────────────────────────────────────────────────
  // Non-final: the error-state retry button re-runs _initStream() to get a
  // fresh Stream instance.
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream;

  // ── Rate-limit guard for _fetchUnread ────────────────────────────────────────
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
  Future<void> _fetchUnread() async {
    if (_uid.isEmpty) return;

    final snap = await _store
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .count()
        .get();

    if (!mounted) return;

    setState(() => _unread = snap.count ?? 0);
    _lastUnreadFetch = DateTime.now();
  }

  // ── Completion progress ──────────────────────────────────────────────────────
  void _scheduleProgressUpdate(Map<String, dynamic> data) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final count = completionCount(data, _user?.email ?? '');
      final target = count / kCompletionLabels.length;

      if ((target - _completionTarget).abs() < 0.001) return;
      setState(() => _completionTarget = target);
      _progressCtrl
        ..stop()
        ..forward(from: 0);
    });
  }

  // ── Referral code ────────────────────────────────────────────────────────────
  Future<void> _ensureReferral(Map<String, dynamic> data) async {
    if (_uid.isEmpty) return;

    final existing = data['referralCode'] as String?;
    if (existing != null && existing.isNotEmpty) {
      if (_referralCode != existing) {
        if (!mounted) return;
        setState(() => _referralCode = existing);
      }
      return;
    }

    final code = generateReferralCode(_uid);

    if (!mounted) return;
    setState(() => _referralCode = code);

    await _store.collection('users').doc(_uid).set(
      {'referralCode': code},
      SetOptions(merge: true),
    );

    if (!mounted) return;
  }

  // ── Avatar upload ────────────────────────────────────────────────────────────
  Future<void> _pickAndUpload() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();

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
          if (!mounted) return;
          setState(() => _uploadProgress = p);
        },
      );

      if (!mounted) return;

      // Append timestamp to bust Flutter's image cache
      final bustedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      await _store.collection('users').doc(_uid).set(
        {'photoUrl': bustedUrl},
        SetOptions(merge: true),
      );

      if (!mounted) return;

      await _user?.updatePhotoURL(bustedUrl);

      if (!mounted) return;

      KToast.show(context, 'Photo updated ✓', type: KToastType.success);
    } on UploadValidationException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Upload failed. Please try again.');
      debugPrint('Avatar upload error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  // ── Snackbar helper (used for errors — successes use KToast) ────────────────
  void _showSnack(String msg, {bool success = false}) {
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
  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmText: 'Log Out',
      isDestructive: false,
    );

    if (confirmed != true || !mounted) return;

    await _auth.signOut();

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, KRoutes.login);
  }

  // ── Delete account ────────────────────────────────────────────────────────────
  // Cascades: Firestore doesn't auto-delete subcollections when you delete a
  // parent doc, so `notifications` under users/{uid} would otherwise be left
  // behind as orphaned data forever. Batch-delete it first (chunked at 500 —
  // Firestore's per-batch write limit), then the user doc, then the Auth
  // account.
  Future<void> _deleteAccount() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Account',
      message: 'This permanently deletes your account and all data. '
          'This cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);

    try {
      await _deleteNotificationsSubcollection();

      if (!mounted) return;

      await _store.collection('users').doc(_uid).delete();

      if (!mounted) return;

      await _user?.delete();

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, KRoutes.login);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.code == 'requires-recent-login'
            ? 'Please log out and log back in before deleting your account.'
            : 'Could not delete account: ${e.message}',
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not delete account. Please try again.');
      debugPrint('Delete account error: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _deleteNotificationsSubcollection() async {
    final notifsRef =
        _store.collection('users').doc(_uid).collection('notifications');

    while (true) {
      final snap = await notifsRef.limit(500).get();
      if (snap.docs.isEmpty) return;

      final batch = _store.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snap.docs.length < 500) return;
    }
  }

  // ── Notifications toggle ──────────────────────────────────────────────────────
  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsOn = value);

    await _store.collection('users').doc(_uid).set(
      {'notificationsEnabled': value},
      SetOptions(merge: true),
    );

    if (!mounted) return;
  }

  // ── Pull to refresh ──────────────────────────────────────────────────────────
  // The profile itself is a live Firestore stream, so a manual refresh isn't
  // needed for its own fields — but the unread count is throttled to avoid
  // hammering Firestore on every snapshot, so a pull-to-refresh forces an
  // immediate re-check instead of waiting out the throttle window.
  Future<void> _handleRefresh() async {
    await _fetchUnread();
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
            // ── Error state ──────────────────────────────────────────────
            if (snapshot.hasError) {
              return _ErrorState(onRetry: () => setState(_initStream));
            }

            // ── Loading state (first frame only, before any data arrives) ──
            final isInitialLoad =
                snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData;
            if (isInitialLoad) {
              return const _LoadingState();
            }

            final data = snapshot.data?.data() ?? {};

            if (snapshot.hasData) {
              _scheduleProgressUpdate(data);
              _ensureReferral(data);

              final notifPref = data['notificationsEnabled'] as bool?;
              if (notifPref != null && notifPref != _notificationsOn) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _notificationsOn = notifPref);
                });
              }

              final shouldFetch = _lastUnreadFetch == null ||
                  DateTime.now().difference(_lastUnreadFetch!) >
                      const Duration(minutes: 2);
              if (shouldFetch) _fetchUnread();
            }

            final name =
                data['name'] as String? ?? _user?.displayName ?? 'User';
            final email = data['email'] as String? ?? _user?.email ?? '';
            final photoUrl = data['photoUrl'] as String? ?? _user?.photoURL;
            final role = data['role'] as String? ?? 'Student';
            final points = (data['loyaltyPoints'] as num?)?.toInt() ?? 0;
            final bookings = (data['totalBookings'] as num?)?.toInt() ?? 0;
            final saved = (data['savedCount'] as num?)?.toInt() ?? 0;
            final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;

            return FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                color: kTeal,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    // ── Hero header ──────────────────────────────────────
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
                      joinedDate: _user?.metadata.creationTime,
                      onAvatarTap: _pickAndUpload,
                      onNotifTap: () =>
                          Navigator.pushNamed(context, '/notifications'),
                      onShareTap: () => showReferralSheet(
                        context,
                        referralCode:
                            _referralCode ?? generateReferralCode(_uid),
                      ),
                      onEditTap: () => showEditProfileSheet(
                        context,
                        uid: _uid,
                        data: data,
                      ),
                      onBookingsTap: () =>
                          Navigator.pushNamed(context, KRoutes.bookings),
                      onSavedTap: () =>
                          Navigator.pushNamed(context, KRoutes.saved),
                    ),

                    // ── Body sections ────────────────────────────────────
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
                            onTap: (route) =>
                                Navigator.pushNamed(context, route),
                          ),
                          const SizedBox(height: 28),

                          // Settings sections
                          ProfileSettings(
                            notificationsOn: _notificationsOn,
                            onNotifToggle: _toggleNotifications,
                            onLogout: _logout,
                            onDeleteAccount: _deleting ? () {} : _deleteAccount,
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
              ),
            );
          },
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  _LoadingState — skeleton shown before the first Firestore snapshot arrives
// ══════════════════════════════════════════════════════════════════════════════
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: const [
            KShimmerCard(height: 110, showAvatar: true),
            SizedBox(height: 20),
            KShimmerCard(height: 90),
            SizedBox(height: 20),
            KShimmerCard(height: 160),
            SizedBox(height: 20),
            KShimmerCard(height: 90),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  _ErrorState — shown when the Firestore stream errors (permission-denied,
//  offline, etc.) instead of silently falling back to empty defaults.
// ══════════════════════════════════════════════════════════════════════════════
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: kTextTertiary),
                const SizedBox(height: 16),
                Text(
                  "Couldn't load your profile",
                  style: KText.labelLg,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Check your connection and try again.',
                  style: KText.bodyXS,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                KButton(
                  label: 'Retry',
                  small: true,
                  icon: Icons.refresh_rounded,
                  onTap: onRetry,
                ),
              ],
            ),
          ),
        ),
      );
}
