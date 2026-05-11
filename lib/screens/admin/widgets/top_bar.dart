import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../constants/admin_theme.dart';
import '../admin_section.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CLOUDINARY CONFIG
// ─────────────────────────────────────────────────────────────────────────────

const _kCloudName = 'dfv9yibba';
const _kUploadPreset = 'ml_default';

Future<String?> _uploadToCloudinary({
  required Uint8List bytes,
  required String filename,
  String folder = 'avatars',
}) async {
  final uri =
      Uri.parse('https://api.cloudinary.com/v1_1/$_kCloudName/image/upload');
  final request = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _kUploadPreset
    ..fields['folder'] = folder
    ..files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
  try {
    final response = await request.send();
    final body = await response.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode == 200) return json['secure_url'] as String?;
    return null;
  } catch (e) {
    debugPrint('Cloudinary upload error: $e');
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMESTAMP HELPERS
// ─────────────────────────────────────────────────────────────────────────────

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is String && value.isNotEmpty) {
    try {
      final cleaned = value
          .replaceAll(' at ', ' ')
          .replaceFirst(RegExp(r'\s+UTC[+-]\d+$'), '');
      return DateTime.tryParse(cleaned);
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _formatTime(dynamic value) {
  final dt = _toDateTime(value);
  if (dt == null) return '';
  return timeago.format(dt);
}

// ─────────────────────────────────────────────────────────────────────────────
// BREAKPOINTS  (phone < 550, tablet 550–899, desktop ≥ 900)
// ─────────────────────────────────────────────────────────────────────────────

bool _isPhone(BuildContext ctx) => MediaQuery.of(ctx).size.width < 550;
bool _isTablet(BuildContext ctx) {
  final w = MediaQuery.of(ctx).size.width;
  return w >= 550 && w < 900;
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

/// Place this widget at the top of every admin page / scaffold.
///
/// Required props
/// • [section]              – current [AdminSection] (drives the breadcrumb label)
/// • [onMenuTap]            – called when the hamburger icon is tapped (phone)
/// • [onNavigateToSection]  – called when "View all" / "Open Live Chat" is tapped
///
/// Integration example (in your admin shell):
/// ```dart
/// TopBar(
///   section: _currentSection,
///   onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
///   onNavigateToSection: (s) => setState(() => _currentSection = s),
/// )
/// ```
class TopBar extends StatefulWidget {
  const TopBar({
    super.key,
    required this.section,
    required this.onMenuTap,
    required this.onNavigateToSection,
  });

  final AdminSection section;
  final VoidCallback onMenuTap;
  final void Function(AdminSection) onNavigateToSection;

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  final _profileLink = LayerLink();
  final _notifLink = LayerLink();
  final _msgLink = LayerLink();

  OverlayEntry? _profileOverlay;
  OverlayEntry? _notifOverlay;
  OverlayEntry? _msgOverlay;

  // ── Unread badge streams ─────────────────────────────────────────────────

  Stream<int> get _unreadNotifCount => FirebaseFirestore.instance
      .collection('activityLog')
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length);

  Stream<int> get _unreadMsgCount => FirebaseFirestore.instance
      .collection('messages')
      .where('toAdmin', isEqualTo: true)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length);

  // ── Overlay helpers ───────────────────────────────────────────────────────

  void _closeAll() {
    _profileOverlay?.remove();
    _profileOverlay = null;
    _notifOverlay?.remove();
    _notifOverlay = null;
    _msgOverlay?.remove();
    _msgOverlay = null;
  }

  OverlayEntry _buildOverlay({
    required LayerLink link,
    required double desiredWidth,
    required Widget child,
  }) {
    return OverlayEntry(
      builder: (ctx) {
        final screenW = MediaQuery.of(ctx).size.width;
        final safeW = desiredWidth.clamp(0.0, screenW - 24);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeAll,
              ),
            ),
            CompositedTransformFollower(
              link: link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 8),
              child: Material(
                color: Colors.transparent,
                child: SizedBox(width: safeW, child: child),
              ),
            ),
          ],
        );
      },
    );
  }

  void _toggleProfile(BuildContext ctx) {
    if (_profileOverlay != null) {
      _closeAll();
      return;
    }
    _closeAll();
    _profileOverlay = _buildOverlay(
      link: _profileLink,
      desiredWidth: 290,
      child: _ProfileDropdown(onClose: _closeAll),
    );
    Overlay.of(ctx).insert(_profileOverlay!);
  }

  void _toggleNotif(BuildContext ctx) {
    if (_notifOverlay != null) {
      _closeAll();
      return;
    }
    _closeAll();
    final w = MediaQuery.of(ctx).size.width;
    _notifOverlay = _buildOverlay(
      link: _notifLink,
      desiredWidth: w < 400 ? w - 32 : 340,
      child: _NotificationPanel(
        onClose: _closeAll,
        // ✅ navigates to the Activity Log page
        onViewAll: () {
          _closeAll();
          widget.onNavigateToSection(AdminSection.activityLog);
        },
      ),
    );
    Overlay.of(ctx).insert(_notifOverlay!);
  }

  void _toggleMsg(BuildContext ctx) {
    if (_msgOverlay != null) {
      _closeAll();
      return;
    }
    _closeAll();
    final w = MediaQuery.of(ctx).size.width;
    _msgOverlay = _buildOverlay(
      link: _msgLink,
      desiredWidth: w < 400 ? w - 32 : 320,
      child: _MessagesPanel(
        onClose: _closeAll,
        // ✅ navigates to the Live Chat page
        onOpenChat: () {
          _closeAll();
          widget.onNavigateToSection(AdminSection.liveChat);
        },
      ),
    );
    Overlay.of(ctx).insert(_msgOverlay!);
  }

  @override
  void dispose() {
    _closeAll();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final phone = _isPhone(context);
    final tablet = _isTablet(context);
    final showBreadcrumb = !phone; // tablet + desktop
    final showNameText = !phone && !tablet; // desktop only

    return Container(
      // ✅ Always visible on every screen size; height adapts
      height: phone ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 20),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(bottom: BorderSide(color: kBorder)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // ── Hamburger (phone only) ──────────────────────────────────────
          if (phone) ...[
            GestureDetector(
              onTap: widget.onMenuTap,
              child: const Icon(Icons.menu_rounded, size: 22, color: kTextDark),
            ),
            const SizedBox(width: 12),
          ],

          // ── Breadcrumb / page title ─────────────────────────────────────
          Expanded(
            child: Row(
              children: [
                if (showBreadcrumb) ...[
                  const Icon(Icons.grid_view_rounded,
                      size: 15, color: kTextMuted),
                  const SizedBox(width: 6),
                  const Text('Admin',
                      style: TextStyle(fontSize: 13, color: kTextMuted)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 14, color: kTextMuted),
                  ),
                ],
                Flexible(
                  child: Text(
                    widget.section.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: phone ? 15 : 14,
                      fontWeight: FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Messages icon ───────────────────────────────────────────────
          CompositedTransformTarget(
            link: _msgLink,
            child: StreamBuilder<int>(
              stream: _unreadMsgCount,
              builder: (_, snap) => _TopBarIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                badgeCount: (snap.data ?? 0) > 0 ? snap.data : null,
                onTap: () => _toggleMsg(context),
              ),
            ),
          ),

          SizedBox(width: phone ? 2 : 6),

          // ── Notifications icon ──────────────────────────────────────────
          CompositedTransformTarget(
            link: _notifLink,
            child: StreamBuilder<int>(
              stream: _unreadNotifCount,
              builder: (_, snap) => _TopBarIconButton(
                icon: Icons.notifications_none_rounded,
                badgeCount: (snap.data ?? 0) > 0 ? snap.data : null,
                onTap: () => _toggleNotif(context),
              ),
            ),
          ),

          SizedBox(width: phone ? 6 : 12),

          if (!phone) ...[
            Container(width: 1, height: 28, color: kBorder),
            const SizedBox(width: 12),
          ],

          // ── Admin avatar ────────────────────────────────────────────────
          CompositedTransformTarget(
            link: _profileLink,
            child: _AdminAvatar(
              compact: !showNameText,
              onTap: () => _toggleProfile(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ICON BUTTON WITH BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _TopBarIconButton extends StatefulWidget {
  const _TopBarIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount,
  });
  final IconData icon;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  State<_TopBarIconButton> createState() => _TopBarIconButtonState();
}

class _TopBarIconButtonState extends State<_TopBarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _hovered ? kGreen.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(widget.icon,
                  size: 20, color: _hovered ? kGreen : kTextMuted),
              if (widget.badgeCount != null && widget.badgeCount! > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.badgeCount! > 9 ? 4 : 5,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE24B4A),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      widget.badgeCount! > 99 ? '99+' : '${widget.badgeCount}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN AVATAR BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _AdminAvatar extends StatefulWidget {
  const _AdminAvatar({required this.onTap, this.compact = false});
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_AdminAvatar> createState() => _AdminAvatarState();
}

class _AdminAvatarState extends State<_AdminAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 6 : 12, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? kGreen.withOpacity(0.07) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            border:
                Border.all(color: _hovered ? kGreen.withOpacity(0.3) : kBorder),
          ),
          child: StreamBuilder<DocumentSnapshot>(
            stream: uid != null
                ? FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots()
                : null,
            builder: (_, snap) {
              final data = snap.data?.data() as Map<String, dynamic>? ?? {};
              final photoUrl = data['photoUrl'] as String?;
              final name = (data['username'] as String?)?.trim() ?? 'Admin';
              final initials = _initials(name);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AvatarCircle(
                      photoUrl: photoUrl, initials: initials, size: 32),
                  if (!widget.compact) ...[
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.length > 20 ? '${name.substring(0, 20)}…' : name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kTextDark),
                        ),
                        const Text('Administrator',
                            style: TextStyle(fontSize: 10, color: kTextMuted)),
                      ],
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: kTextMuted),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _initials(String name) {
  if (name.isEmpty) return 'A';
  return name
      .split(' ')
      .where((e) => e.isNotEmpty)
      .take(2)
      .map((e) => e[0].toUpperCase())
      .join();
}

// ─────────────────────────────────────────────────────────────────────────────
// AVATAR CIRCLE
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.photoUrl,
    required this.initials,
    this.size = 40,
  });
  final String? photoUrl;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kGreen.withOpacity(0.12),
        border: Border.all(color: kGreen.withOpacity(0.4), width: 1.5),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? Image.network(
                photoUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) {
                  if (prog == null) return child;
                  return Center(
                    child: SizedBox(
                      width: size * 0.4,
                      height: size * 0.4,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kGreen),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => _initialsWidget(),
              )
            : _initialsWidget(),
      ),
    );
  }

  Widget _initialsWidget() => Center(
        child: Text(
          initials,
          style: TextStyle(
              color: kGreen,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.38),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE DROPDOWN
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileDropdown extends StatefulWidget {
  const _ProfileDropdown({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_ProfileDropdown> createState() => _ProfileDropdownState();
}

class _ProfileDropdownState extends State<_ProfileDropdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _editing = false;
  bool _uploading = false;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
    _loadProfile();
  }

  void _loadProfile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
      if (!mounted) return;
      final d = doc.data() ?? {};
      _nameCtrl.text = d['username'] as String? ?? '';
      _emailCtrl.text = d['email'] as String? ??
          FirebaseAuth.instance.currentUser?.email ??
          '';
      _phoneCtrl.text = d['phone'] as String? ?? '';
    });
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 400);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final filename = picked.name.isNotEmpty
          ? picked.name
          : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await _uploadToCloudinary(bytes: bytes, filename: filename);
      if (url != null) {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'photoUrl': url});
        if (mounted) _snack('Photo updated!', kGreen);
      } else {
        throw Exception('Upload returned null URL');
      }
    } catch (e) {
      if (mounted) _snack('Upload failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'username': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
    });
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _changePassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (mounted) _snack('Password reset email sent!', kGreen);
    widget.onClose();
  }

  Future<void> _logout() async {
    widget.onClose();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290, minWidth: 220),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 20, offset: Offset(0, 8)),
            ],
          ),
          child: StreamBuilder<DocumentSnapshot>(
            stream: uid != null
                ? FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots()
                : null,
            builder: (_, snap) {
              final data = snap.data?.data() as Map<String, dynamic>? ?? {};
              final photoUrl = data['photoUrl'] as String?;
              final name = (data['username'] as String?)?.trim() ?? 'Admin';
              final email = data['email'] as String? ??
                  FirebaseAuth.instance.currentUser?.email ??
                  '';
              final initials = _initials(name);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kGreen.withOpacity(0.12),
                          kGreen.withOpacity(0.04)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            _AvatarCircle(
                                photoUrl: photoUrl,
                                initials: initials,
                                size: 56),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _uploading ? null : _pickAndUpload,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                      color: kGreen, shape: BoxShape.circle),
                                  child: _uploading
                                      ? const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : const Icon(Icons.camera_alt_rounded,
                                          size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: kTextDark)),
                              const SizedBox(height: 2),
                              Text(email,
                                  style: const TextStyle(
                                      fontSize: 11, color: kTextMuted),
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: kGreen.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20)),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield_rounded,
                                        color: kGreen, size: 10),
                                    SizedBox(width: 4),
                                    Text('Administrator',
                                        style: TextStyle(
                                            color: kGreen,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Edit form ────────────────────────────────────────────
                  if (_editing)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _EditField(
                              ctrl: _nameCtrl,
                              label: 'Display Name',
                              icon: Icons.person_outline_rounded),
                          const SizedBox(height: 8),
                          _EditField(
                              ctrl: _phoneCtrl,
                              label: 'Phone',
                              icon: Icons.phone_outlined),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _editing = false),
                                  style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10)),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _saveProfile,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: kGreen,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10)),
                                  child: const Text('Save',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // ── Menu items ───────────────────────────────────────────
                  if (!_editing) ...[
                    _MenuItem(
                        icon: Icons.edit_outlined,
                        label: 'Edit Profile',
                        onTap: () => setState(() => _editing = true)),
                    _MenuItem(
                        icon: Icons.camera_alt_outlined,
                        label: 'Upload Photo',
                        onTap: _pickAndUpload),
                    _MenuItem(
                        icon: Icons.lock_outline_rounded,
                        label: 'Change Password',
                        onTap: _changePassword),
                    const Divider(height: 1, color: kBorder),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MENU ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? kTextDark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.color != null
                    ? Colors.redAccent.withOpacity(0.07)
                    : kGreen.withOpacity(0.06))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: color),
              const SizedBox(width: 10),
              Text(widget.label,
                  style: TextStyle(
                      fontSize: 13, color: color, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT FIELD
// ─────────────────────────────────────────────────────────────────────────────

class _EditField extends StatelessWidget {
  const _EditField(
      {required this.ctrl, required this.label, required this.icon});
  final TextEditingController ctrl;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13, color: kTextDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: kTextMuted),
        prefixIcon: Icon(icon, size: 16, color: kTextMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kGreen, width: 1.5)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION PANEL
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel({
    required this.onClose,
    required this.onViewAll,
  });
  final VoidCallback onClose;
  final VoidCallback onViewAll; // ✅ navigates to ActivityLog

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _markAllRead() {
    FirebaseFirestore.instance
        .collection('activityLog')
        .where('read', isEqualTo: false)
        .get()
        .then((snap) {
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) batch.update(doc.reference, {'read': true});
      batch.commit();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 440),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 20, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Text('Notifications',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: kTextDark)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _markAllRead,
                      child: const Text('Mark all read',
                          style: TextStyle(
                              fontSize: 11,
                              color: kGreen,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: kTextMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: kBorder),

              // ── List ──────────────────────────────────────────────────────
              Flexible(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('activityLog')
                      .orderBy('timestamp', descending: true)
                      .limit(20)
                      .snapshots(),
                  builder: (_, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: CircularProgressIndicator(color: kGreen)),
                      );
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('No notifications',
                                style: TextStyle(color: kTextMuted))),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: kBorder),
                      itemBuilder: (_, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        final action = d['action'] as String? ?? 'Activity';
                        final details = d['details'] as String? ?? '';
                        final timeStr = _formatTime(d['timestamp']);
                        final isUnread = d['read'] == false;
                        return _NotificationTile(
                            action: action,
                            details: details,
                            time: timeStr,
                            isUnread: isUnread);
                      },
                    );
                  },
                ),
              ),

              // ── Footer ────────────────────────────────────────────────────
              const Divider(height: 1, color: kBorder),
              TextButton(
                onPressed: widget.onViewAll, // ✅ actually navigates
                child: const Text('View all activity logs',
                    style: TextStyle(
                        color: kGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.action,
    required this.details,
    required this.time,
    this.isUnread = false,
  });
  final String action, details, time;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isUnread ? kGreen.withOpacity(0.04) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: kGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.notifications_active_rounded,
                color: kGreen, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action,
                    style: TextStyle(
                        fontWeight:
                            isUnread ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 12.5,
                        color: kTextDark)),
                if (details.isNotEmpty)
                  Text(details,
                      style: const TextStyle(fontSize: 11, color: kTextMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (time.isNotEmpty)
            Text(time, style: const TextStyle(fontSize: 10, color: kTextMuted)),
          if (isUnread) ...[
            const SizedBox(width: 4),
            Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 3),
                decoration:
                    const BoxDecoration(color: kGreen, shape: BoxShape.circle)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MESSAGES PANEL
// ─────────────────────────────────────────────────────────────────────────────

class _MessagesPanel extends StatefulWidget {
  const _MessagesPanel({
    required this.onClose,
    required this.onOpenChat,
  });
  final VoidCallback onClose;
  final VoidCallback onOpenChat; // ✅ navigates to LiveChat

  @override
  State<_MessagesPanel> createState() => _MessagesPanelState();
}

class _MessagesPanelState extends State<_MessagesPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 20, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Text('Messages',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: kTextDark)),
                    const Spacer(),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: kTextMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: kBorder),

              // ── List ──────────────────────────────────────────────────────
              Flexible(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('messages')
                      .where('toAdmin', isEqualTo: true)
                      .orderBy('timestamp', descending: true)
                      .limit(20)
                      .snapshots(),
                  builder: (_, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: CircularProgressIndicator(color: kGreen)),
                      );
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  size: 32, color: kTextMuted),
                              SizedBox(height: 8),
                              Text('No messages yet',
                                  style: TextStyle(color: kTextMuted)),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: kBorder),
                      itemBuilder: (_, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        final sender = d['senderName'] as String? ?? 'User';
                        final text = d['text'] as String? ?? '';
                        final unread = d['read'] == false;
                        final timeStr = _formatTime(d['timestamp']);
                        final initials =
                            sender.isNotEmpty ? sender[0].toUpperCase() : 'U';
                        return GestureDetector(
                          onTap: widget
                              .onOpenChat, // ✅ tapping a message opens chat
                          child: _MessageTile(
                              sender: sender,
                              text: text,
                              time: timeStr,
                              unread: unread,
                              initials: initials),
                        );
                      },
                    );
                  },
                ),
              ),

              // ── Footer ────────────────────────────────────────────────────
              const Divider(height: 1, color: kBorder),
              TextButton(
                onPressed: widget.onOpenChat, // ✅ actually navigates
                child: const Text('Open Live Chat',
                    style: TextStyle(
                        color: kGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.sender,
    required this.text,
    required this.time,
    required this.unread,
    required this.initials,
  });
  final String sender, text, time, initials;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AvatarCircle(photoUrl: null, initials: initials, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(sender,
                          style: TextStyle(
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w500,
                              fontSize: 12.5,
                              color: kTextDark)),
                    ),
                    if (time.isNotEmpty)
                      Text(time,
                          style:
                              const TextStyle(fontSize: 10, color: kTextMuted)),
                    if (unread) ...[
                      const SizedBox(width: 6),
                      Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                              color: kGreen, shape: BoxShape.circle)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(text,
                    style: const TextStyle(fontSize: 11, color: kTextMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USER-SIDE LIVE CHAT WIDGET
// ─────────────────────────────────────────────────────────────────────────────
//
// Drop this widget anywhere on the user side (e.g. inside a Scaffold body or
// as a floating chat bubble sheet).
//
// It:
//   • reads / writes to  messages/{auto-id}
//   • marks  toAdmin: true  so admin sees them in the TopBar badge
//   • marks  read: false    so the badge count updates in real-time
//   • when the user sends a message it is immediately marked read: false
//   • when admin replies, mark messages with toAdmin: false, toUser: true
//
// Firestore document schema:
//   {
//     senderName : String,   // user's display name
//     senderId   : String,   // user's UID
//     text       : String,
//     timestamp  : Timestamp,
//     toAdmin    : bool,     // true  → user → admin
//     toUser     : bool,     // true  → admin → user
//     read       : bool,
//     sessionId  : String,   // groups messages into one chat session
//   }

class UserLiveChatWidget extends StatefulWidget {
  const UserLiveChatWidget({super.key});

  @override
  State<UserLiveChatWidget> createState() => _UserLiveChatWidgetState();
}

class _UserLiveChatWidgetState extends State<UserLiveChatWidget> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _name => FirebaseAuth.instance.currentUser?.displayName ?? 'User';

  // Each user gets one stable session per UID for simplicity.
  // For multiple sessions, generate a unique sessionId elsewhere.
  String get _sessionId => 'session_$_uid';

  Stream<QuerySnapshot> get _messages => FirebaseFirestore.instance
      .collection('messages')
      .where('sessionId', isEqualTo: _sessionId)
      .orderBy('timestamp')
      .snapshots();

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'senderName': _name,
        'senderId': _uid,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'toAdmin': true,
        'toUser': false,
        'read': false,
        'sessionId': _sessionId,
      });
      // scroll to bottom
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Message list ──────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _messages,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('Send a message to start chatting.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final text = d['text'] as String? ?? '';
                  final isMe = d['toAdmin'] == true; // sent by user
                  final timeStr = _formatTime(d['timestamp']);
                  return _ChatBubble(text: text, isMe: isMe, time: timeStr);
                },
              );
            },
          ),
        ),

        // ── Input bar ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle:
                        const TextStyle(fontSize: 13, color: Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                            color: Color(0xFF22C55E), width: 1.5)),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _sending
                        ? const Color(0xFF22C55E).withOpacity(0.5)
                        : const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.isMe,
    required this.time,
  });
  final String text;
  final bool isMe;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF22C55E) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text,
                style: TextStyle(
                    fontSize: 13.5,
                    color: isMe ? Colors.white : const Color(0xFF111827))),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(time,
                  style: TextStyle(
                      fontSize: 10,
                      color:
                          isMe ? Colors.white.withOpacity(0.7) : Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
