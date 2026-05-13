// lib/screens/admin/chat/admin_live_chat_screen.dart
//
// ═══════════════════════════════════════════════════════════════════════════
//  ROOMZYFIND — ADMIN LIVE CHAT  (Advanced, Modern, Production-Ready)
// ═══════════════════════════════════════════════════════════════════════════
//
//  ▸ PLACES TO UPDATE (search the tag 🔧 in this file):
//
//  🔧 1  FIRESTORE PATHS  — chats/{studentUid}/messages
//        If your paths differ, update _messagesRef() and _chatDocRef().
//
//  🔧 3  PUSH NOTIFICATIONS  — _sendPushToStudent() is a stub.
//        Wire it to your Cloud Functions / FCM endpoint.
//
//  🔧 4  UNREAD BADGE SOURCE  — The sidebar badge reads `unreadByAdmin`.
//        Make sure your student chat screen writes that field on send
//        (the provided student chat_screen.dart already does this).
//
//  🔧 5  ADMIN THEME IMPORTS  — Adjust the import paths to match your
//        project structure (kGreen, kGreenAccent from admin_theme.dart).
//
//  🔧 6  ROUTING  — Register this screen in your router / MaterialApp
//        routes map.  Example:  '/admin/chat': (_) => AdminLiveChatScreen()
//
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../constants/admin_theme.dart';

// ── Brand colours (inline so the file is self-contained) ──────────────────
const _kGreen = Color(0xFF1B5E20);
const _kGreenMid = Color(0xFF2E7D32);
const _kGreenAccent = Color(0xFF43A047);
const _kGreenPale = Color(0xFFE8F5E9);
const _kGreenBorder = Color(0xFFA5D6A7);
const _kOrange = Color(0xFFE8845A);
const _kBg = Color(0xFFF5F7F6);
const _kDarkText = Color(0xFF1A2E2B);

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AdminLiveChatScreen extends StatefulWidget {
  const AdminLiveChatScreen({super.key});

  @override
  State<AdminLiveChatScreen> createState() => _AdminLiveChatScreenState();
}

class _AdminLiveChatScreenState extends State<AdminLiveChatScreen>
    with TickerProviderStateMixin {
  // ── Admin identity — always reads live from FirebaseAuth ──────────────
  // FIX: using getters instead of top-level finals so these are always
  // current even if auth state resolves after widget creation.
  String get _adminId => FirebaseAuth.instance.currentUser?.uid ?? 'admin';
  String get _adminName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'Support';

  // ── Selected conversation ──────────────────────────────────────────────
  String? _selectedUid;
  Map<String, dynamic>? _selectedMeta;

  // ── Search ────────────────────────────────────────────────────────────
  final _sidebarSearch = TextEditingController();
  String _sidebarQuery = '';
  bool _showSearch = false;

  // ── Filter tab ────────────────────────────────────────────────────────
  String _filterTab = 'all'; // all | open | resolved

  // ── Animation ─────────────────────────────────────────────────────────
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _sidebarSearch.addListener(() =>
        setState(() => _sidebarQuery = _sidebarSearch.text.toLowerCase()));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _sidebarSearch.dispose();
    super.dispose();
  }

  void _selectConvo(String uid, Map<String, dynamic> meta) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedUid = uid;
      _selectedMeta = meta;
    });
    _slideCtrl.forward(from: 0);
    // Mark messages as read from admin side
    _markAllRead(uid);
  }

  Future<void> _markAllRead(String uid) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(uid)
        .set({'unreadByAdmin': false}, SetOptions(merge: true));
  }

  // 🔧 3 — stub for push notifications
  Future<void> _sendPushToStudent(String uid, String message) async {
    // TODO: call your Cloud Function / FCM here
    // e.g. FirebaseFunctions.instance.httpsCallable('sendPushToUser')
    //   .call({'uid': uid, 'body': message});
  }

  // ── Firestore refs ──────────────────────────────────────────────────────
  // 🔧 1 — update paths if needed
  CollectionReference<Map<String, dynamic>> _messagesRef(String uid) =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(uid)
          .collection('messages');

  DocumentReference<Map<String, dynamic>> _chatDocRef(String uid) =>
      FirebaseFirestore.instance.collection('chats').doc(uid);

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: _kBg,
      body: isWide
          ? Row(children: [
              _buildSidebar(),
              Expanded(child: _buildChatPane()),
            ])
          : _selectedUid == null
              ? _buildSidebar()
              // FIX: WillPopScope is deprecated — replaced with PopScope
              : PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) setState(() => _selectedUid = null);
                  },
                  child: _buildChatPane(),
                ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SIDEBAR
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSidebar() {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(children: [
        _buildSidebarHeader(),
        _buildFilterTabs(),
        Expanded(child: _buildConvoList()),
      ]),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      decoration: const BoxDecoration(
        color: _kGreen,
        boxShadow: [
          BoxShadow(
              color: Color(0x18000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Live Chat',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: .2)),
              ),
              // Unread count badge
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .where('unreadByAdmin', isEqualTo: true)
                    .snapshots(),
                builder: (_, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kOrange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  );
                },
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _showSearch = !_showSearch),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _showSearch
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          // Animated search input
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0, width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 1),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search_rounded,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _sidebarSearch,
                        autofocus: _showSearch,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search students…',
                          hintStyle:
                              TextStyle(color: Colors.white54, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_sidebarQuery.isNotEmpty)
                      GestureDetector(
                        onTap: _sidebarSearch.clear,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Icon(Icons.close_rounded,
                              color: Colors.white54, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            crossFadeState: _showSearch
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final tabs = ['all', 'open', 'resolved'];
    final labels = {'all': 'All', 'open': 'Open', 'resolved': 'Resolved'};
    return Container(
      color: Colors.white,
      child: Row(
        children: tabs.map((t) {
          final active = _filterTab == t;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _filterTab = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? _kGreen : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  labels[t]!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? _kGreen : const Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildConvoList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .orderBy('lastUpdated', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2));
        }
        var docs = snap.data?.docs ?? [];

        // Filter by status
        if (_filterTab != 'all') {
          docs = docs
              .where((d) => (d.data()['status'] ?? 'open') == _filterTab)
              .toList();
        }

        // Filter by search
        if (_sidebarQuery.isNotEmpty) {
          docs = docs
              .where((d) => (d.data()['studentName'] as String? ?? '')
                  .toLowerCase()
                  .contains(_sidebarQuery))
              .toList();
        }

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_rounded,
                    color: Colors.grey.shade300, size: 40),
                const SizedBox(height: 10),
                Text('No conversations',
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final uid = doc.id;
            final name = data['studentName'] as String? ?? 'Unknown';
            final last = data['lastMessage'] as String? ?? '';
            final unread = data['unreadByAdmin'] == true;
            final ts = data['lastUpdated'] as Timestamp?;
            final time = ts != null ? _relativeTime(ts.toDate()) : '';
            final isSelected = _selectedUid == uid;
            final status = data['status'] as String? ?? 'open';

            return _ConvoTile(
              name: name,
              lastMessage: last,
              time: time,
              unread: unread,
              isSelected: isSelected,
              status: status,
              onTap: () => _selectConvo(uid, data),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CHAT PANE
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildChatPane() {
    if (_selectedUid == null) {
      return _buildEmptyState();
    }

    return SlideTransition(
      position: _slideAnim,
      child: _ActiveChatPane(
        uid: _selectedUid!,
        meta: _selectedMeta!,
        adminId: _adminId,
        adminName: _adminName,
        messagesRef: _messagesRef(_selectedUid!),
        chatDocRef: _chatDocRef(_selectedUid!),
        onSendPush: (msg) => _sendPushToStudent(_selectedUid!, msg),
        onBack: () => setState(() => _selectedUid = null),
        onStatusChange: (status) async {
          await _chatDocRef(_selectedUid!).update({'status': status});
          setState(() {});
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kGreenPale,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                color: _kGreen, size: 36),
          ),
          const SizedBox(height: 18),
          const Text('Select a conversation',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _kDarkText)),
          const SizedBox(height: 6),
          const Text('Choose a student chat from the sidebar to reply.',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF9E9E9E))),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd/MM').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ACTIVE CHAT PANE  (stateful, handles messages stream + sending)
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveChatPane extends StatefulWidget {
  const _ActiveChatPane({
    required this.uid,
    required this.meta,
    required this.adminId,
    required this.adminName,
    required this.messagesRef,
    required this.chatDocRef,
    required this.onSendPush,
    required this.onBack,
    required this.onStatusChange,
  });

  final String uid;
  final Map<String, dynamic> meta;
  final String adminId;
  final String adminName;
  final CollectionReference<Map<String, dynamic>> messagesRef;
  final DocumentReference<Map<String, dynamic>> chatDocRef;
  final Future<void> Function(String) onSendPush;
  final VoidCallback onBack;
  final void Function(String) onStatusChange;

  @override
  State<_ActiveChatPane> createState() => _ActiveChatPaneState();
}

class _ActiveChatPaneState extends State<_ActiveChatPane>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  bool _sending = false;
  bool _isTyping = false;
  bool _isSearching = false;
  bool _showInfo = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _replyingTo;

  late AnimationController _replyCtrl;
  late Animation<double> _replyAnim;

  // FIX: typing indicator — timer to auto-clear the adminTyping flag
  Timer? _typingTimer;

  // Quick replies for admin
  static const _quickReplies = [
    '✅ Issue resolved!',
    '⏳ Looking into this now',
    '📞 Can you call us?',
    '🔁 Please try again',
    '📋 Booking confirmed',
  ];

  @override
  void initState() {
    super.initState();
    _replyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _replyAnim =
        CurvedAnimation(parent: _replyCtrl, curve: Curves.easeOutCubic);
    _ctrl.addListener(() {
      // FIX: wire typing indicator on every keystroke
      _onTypingChanged();
      final t = _ctrl.text.isNotEmpty;
      if (t != _isTyping) setState(() => _isTyping = t);
    });
    _searchCtrl.addListener(
        () => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    // FIX: cancel timer and clear adminTyping flag when pane closes
    _typingTimer?.cancel();
    widget.chatDocRef
        .set({'adminTyping': false}, SetOptions(merge: true)).ignore();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _replyCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // FIX: write adminTyping to Firestore so student sees indicator
  void _onTypingChanged() {
    final typing = _ctrl.text.isNotEmpty;
    widget.chatDocRef
        .set({'adminTyping': typing}, SetOptions(merge: true)).ignore();
    _typingTimer?.cancel();
    if (typing) {
      // Auto-clear after 3 s of no input in case dispose() is never called
      _typingTimer = Timer(const Duration(seconds: 3), () {
        widget.chatDocRef
            .set({'adminTyping': false}, SetOptions(merge: true)).ignore();
      });
    }
  }

  // ── Send ───────────────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    _ctrl.clear();

    // Clear typing flag immediately on send
    _typingTimer?.cancel();
    widget.chatDocRef
        .set({'adminTyping': false}, SetOptions(merge: true)).ignore();

    final data = <String, dynamic>{
      'text': text,
      'senderUid': widget.adminId,
      'senderName': widget.adminName,
      'role': 'admin',
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
      'status': 'sent',
      'reactions': <String, String>{},
    };

    if (_replyingTo != null) {
      data['replyTo'] = _replyingTo;
      _clearReply();
    }

    await widget.messagesRef.add(data);
    await widget.chatDocRef.set({
      'lastMessage': text,
      'lastUpdated': FieldValue.serverTimestamp(),
      'unreadByStudent': true,
    }, SetOptions(merge: true));

    // 🔧 3 — push notification to student
    await widget.onSendPush(text);

    setState(() => _sending = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ── Reply ──────────────────────────────────────────────────────────────
  void _setReply(Map<String, dynamic> data, String docId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _replyingTo = {
        'id': docId,
        'text': data['text'],
        'senderName': data['role'] == 'admin'
            ? 'You'
            : widget.meta['studentName'] ?? 'Student',
      };
    });
    _replyCtrl.forward();
    _inputFocus.requestFocus();
  }

  void _clearReply() {
    setState(() => _replyingTo = null);
    _replyCtrl.reverse();
  }

  // ── Delete ────────────────────────────────────────────────────────────
  Future<void> _deleteMessage(String docId) async {
    HapticFeedback.heavyImpact();
    await widget.messagesRef.doc(docId).delete();
  }

  // ── Reactions ─────────────────────────────────────────────────────────
  Future<void> _toggleReaction(String docId, String emoji) async {
    final ref = widget.messagesRef.doc(docId);
    final snap = await ref.get();
    final reactions = Map<String, String>.from(snap.data()?['reactions'] ?? {});
    if (reactions[widget.adminId] == emoji) {
      reactions.remove(widget.adminId);
    } else {
      reactions[widget.adminId] = emoji;
    }
    await ref.update({'reactions': reactions});
    HapticFeedback.selectionClick();
  }

  // ── Status change ──────────────────────────────────────────────────────
  void _showStatusMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const Text('Change Status',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (final s in ['open', 'resolved', 'pending'])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _statusColor(s).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_statusIcon(s), color: _statusColor(s), size: 18),
                ),
                title: Text(s[0].toUpperCase() + s.substring(1),
                    style: const TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onStatusChange(s);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Menu (three-dot) ──────────────────────────────────────────────────
  void _showMenu() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2))),
            _AdminMenuTile(
              icon: Icons.search_rounded,
              label: 'Search Messages',
              color: _kGreen,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _isSearching = !_isSearching);
              },
            ),
            _AdminMenuTile(
              icon: Icons.info_outline_rounded,
              label: 'Student Info',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _showInfo = !_showInfo);
              },
            ),
            _AdminMenuTile(
              icon: Icons.swap_horiz_rounded,
              label: 'Change Status',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(ctx);
                _showStatusMenu();
              },
            ),
            _AdminMenuTile(
              icon: Icons.file_copy_outlined,
              label: 'Export Chat',
              color: Colors.teal,
              onTap: () {
                Navigator.pop(ctx);
                _exportChat();
              },
            ),
            _AdminMenuTile(
              icon: Icons.delete_sweep_outlined,
              label: 'Clear Chat',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(ctx);
                _clearChat();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportChat() async {
    final docs = await widget.messagesRef.orderBy('timestamp').get();
    final buf =
        StringBuffer('RoomzyFind Chat Export — ${widget.meta['studentName']}\n'
            '${'─' * 40}\n\n');
    for (final d in docs.docs) {
      final data = d.data();
      final ts = (data['timestamp'] as Timestamp?)?.toDate();
      final time =
          ts != null ? DateFormat('dd/MM/yyyy HH:mm').format(ts) : '--';
      final role = data['role'] == 'admin' ? 'Admin' : 'Student';
      buf.writeln('[$time] $role: ${data['text']}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      _snack('Chat copied to clipboard!'),
    );
  }

  // FIX: batch delete handles conversations with 500+ messages
  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Chat',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
            'All messages will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;

    // Delete in batches of 500 so large conversations are fully cleared
    while (true) {
      final docs = await widget.messagesRef.limit(500).get();
      if (docs.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in docs.docs) batch.delete(d.reference);
      await batch.commit();
    }
    HapticFeedback.heavyImpact();
  }

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final studentName = widget.meta['studentName'] as String? ?? 'Student';
    final status = widget.meta['status'] as String? ?? 'open';

    return Column(
      children: [
        _buildHeader(studentName, status),
        // Search bar
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _isSearching ? _buildSearchBar() : const SizedBox.shrink(),
        ),
        // Info banner
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _showInfo ? _buildInfoBanner() : const SizedBox.shrink(),
        ),
        Expanded(child: _buildMessages()),
        // Reply bar
        SizeTransition(
          sizeFactor: _replyAnim,
          child:
              _replyingTo != null ? _buildReplyBar() : const SizedBox.shrink(),
        ),
        // Quick replies
        _buildQuickReplies(),
        _buildInputBar(),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _buildHeader(String studentName, String status) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: _kGreen,
        boxShadow: [
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          // Back (mobile)
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white, size: 18),
            onPressed: widget.onBack,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),
          // Avatar
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white.withOpacity(0.18),
                child: Text(
                  _initials(studentName),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF69F0AE),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kGreen, width: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(studentName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _statusColor(status).withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_statusIcon(status),
                              color: Colors.white70, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            status[0].toUpperCase() + status.substring(1),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.meta['studentUid'] != null
                          ? 'UID: ${(widget.meta['studentUid'] as String).substring(0, 8)}…'
                          : '',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Header action buttons
          IconButton(
            icon: Icon(
              _isSearching ? Icons.search_off_rounded : Icons.search_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => setState(() => _isSearching = !_isSearching),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                color: Colors.white, size: 20),
            onPressed: _showMenu,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: _kGreen, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13.5, color: _kDarkText),
              decoration: const InputDecoration(
                hintText: 'Search messages…',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: _searchCtrl.clear,
              child:
                  const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      color: _kGreenPale,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded, color: _kGreen, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Student: ${widget.meta['studentName'] ?? '—'}  •  '
              'UID: ${widget.uid}',
              style: const TextStyle(fontSize: 11.5, color: _kGreenMid),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _showInfo = false),
            child:
                const Icon(Icons.close_rounded, size: 16, color: _kGreenAccent),
          ),
        ],
      ),
    );
  }

  // ── Messages ───────────────────────────────────────────────────────────
  Widget _buildMessages() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.messagesRef.orderBy('timestamp').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2));
        }

        var docs = snap.data?.docs ?? [];

        if (_searchQuery.isNotEmpty) {
          docs = docs
              .where((d) => (d.data()['text'] as String? ?? '')
                  .toLowerCase()
                  .contains(_searchQuery))
              .toList();
        }

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    color: Colors.grey.shade300, size: 44),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No messages matching "$_searchQuery"'
                      : 'No messages yet. Start the conversation!',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ],
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return Column(
          children: [
            // FIX: student typing indicator — reads studentTyping from Firestore
            StreamBuilder<DocumentSnapshot>(
              stream: widget.chatDocRef.snapshots(),
              builder: (_, snap) {
                final data = snap.data?.data() as Map<String, dynamic>?;
                final typing = data?['studentTyping'] == true;
                if (!typing) return const SizedBox.shrink();
                final studentName =
                    widget.meta['studentName'] as String? ?? 'S';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: _kGreenPale,
                        child: Text(
                          _initials(studentName),
                          style: const TextStyle(fontSize: 8, color: _kGreen),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TypingDot(delay: 0),
                            _TypingDot(delay: 200),
                            _TypingDot(delay: 400),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data();
                  final isMe = data['role'] == 'admin';
                  final ts = data['timestamp'] as Timestamp?;
                  final time = ts != null ? _formatTime(ts.toDate()) : '';
                  final reactions =
                      Map<String, String>.from(data['reactions'] ?? {});
                  final replyTo = data['replyTo'] as Map<String, dynamic>?;
                  final status = data['status'] as String? ?? 'sent';

                  final showDate = i == 0 ||
                      _isDiffDay(
                        (docs[i - 1].data()['timestamp'] as Timestamp?)
                            ?.toDate(),
                        ts?.toDate(),
                      );

                  return Column(
                    children: [
                      if (showDate && ts != null) _DateChip(date: ts.toDate()),
                      _SwipeToReply(
                        isMe: isMe,
                        onSwipe: () => _setReply(data, doc.id),
                        child: _AdminChatBubble(
                          docId: doc.id,
                          text: data['text'] as String? ?? '',
                          time: time,
                          isMe: isMe,
                          adminId: widget.adminId,
                          reactions: reactions,
                          replyTo: replyTo,
                          status: status,
                          searchQuery: _searchQuery,
                          animateIn: i == docs.length - 1,
                          studentName: widget.meta['studentName'] as String? ??
                              'Student',
                          onReply: () => _setReply(data, doc.id),
                          onDelete: () => _deleteMessage(doc.id),
                          onReact: (e) => _toggleReaction(doc.id, e),
                          onCopy: () {
                            Clipboard.setData(
                                ClipboardData(text: data['text'] ?? ''));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(_snack('Copied!'));
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReplyBar() {
    if (_replyingTo == null) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: _kGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${_replyingTo!['senderName']}',
                  style: const TextStyle(
                      color: _kGreen,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  _replyingTo!['text'],
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _clearReply,
            child:
                const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReplies() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _quickReplies.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () {
              _ctrl.text = _quickReplies[i];
              _inputFocus.requestFocus();
              _ctrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: _ctrl.text.length));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _kGreenPale,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kGreenBorder),
              ),
              child: Text(
                _quickReplies[i],
                style: const TextStyle(
                    fontSize: 12,
                    color: _kGreenMid,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Emoji/attach
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Icon(Icons.attach_file_rounded,
                color: Colors.grey.shade400, size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5F4),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color:
                      _isTyping ? _kGreen.withOpacity(0.5) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _inputFocus,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                style: const TextStyle(
                    fontSize: 14.5, color: _kDarkText, height: 1.4),
                decoration: const InputDecoration(
                  hintText: 'Reply to student…',
                  hintStyle:
                      TextStyle(color: Color(0xFFAAAAAA), fontSize: 14.5),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _isTyping ? _kGreen : const Color(0xFFE0E0E0),
                shape: BoxShape.circle,
                boxShadow: _isTyping
                    ? [
                        BoxShadow(
                          color: _kGreen.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      _isTyping ? Icons.send_rounded : Icons.mic_rounded,
                      color: _isTyping ? Colors.white : const Color(0xFF9E9E9E),
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  bool _isDiffDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.day != b.day || a.month != b.month || a.year != b.year;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
            ? 12
            : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TYPING INDICATOR DOT  (animated, staggered)
// ─────────────────────────────────────────────────────────────────────────────

class _TypingDot extends StatefulWidget {
  const _TypingDot({required this.delay});
  final int delay; // milliseconds

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(
          color: _kGreenAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CONVERSATION TILE
// ─────────────────────────────────────────────────────────────────────────────

class _ConvoTile extends StatelessWidget {
  const _ConvoTile({
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unread,
    required this.isSelected,
    required this.status,
    required this.onTap,
  });

  final String name, lastMessage, time, status;
  final bool unread, isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: isSelected ? _kGreenPale : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isSelected ? _kGreen : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _kGreenPale,
              child: Text(
                _initials(name),
                style: const TextStyle(
                    color: _kGreen, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: status == 'resolved'
                    ? Colors.grey.shade400
                    : const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ],
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
            color: _kDarkText,
          ),
        ),
        subtitle: Text(
          lastMessage,
          style: TextStyle(
            fontSize: 12,
            color: unread ? _kGreenMid : Colors.grey,
            fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time,
                style: TextStyle(
                    fontSize: 10.5, color: unread ? _kGreen : Colors.grey)),
            const SizedBox(height: 5),
            if (unread)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: _kOrange, shape: BoxShape.circle),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                      fontSize: 9.5,
                      color: _statusColor(status),
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ADMIN CHAT BUBBLE
// ─────────────────────────────────────────────────────────────────────────────

class _AdminChatBubble extends StatefulWidget {
  const _AdminChatBubble({
    required this.docId,
    required this.text,
    required this.time,
    required this.isMe,
    required this.adminId,
    required this.reactions,
    required this.status,
    required this.studentName,
    required this.onReply,
    required this.onDelete,
    required this.onReact,
    required this.onCopy,
    this.animateIn = false,
    this.replyTo,
    this.searchQuery = '',
  });

  final String docId, text, time, status, studentName, adminId;
  final bool isMe, animateIn;
  final Map<String, String> reactions;
  final Map<String, dynamic>? replyTo;
  final String searchQuery;
  final VoidCallback onReply, onDelete, onCopy;
  final void Function(String) onReact;

  @override
  State<_AdminChatBubble> createState() => _AdminChatBubbleState();
}

class _AdminChatBubbleState extends State<_AdminChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const _palette = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(widget.isMe ? 0.12 : -0.12, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    widget.animateIn ? _ctrl.forward() : (_ctrl.value = 1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _longPress(BuildContext ctx) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2))),
            // Emoji row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _palette
                  .map((e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(c);
                          widget.onReact(e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ))
                  .toList(),
            ),
            const Divider(height: 24),
            _AdminMenuTile(
                icon: Icons.reply_rounded,
                label: 'Reply',
                color: _kGreen,
                onTap: () {
                  Navigator.pop(c);
                  widget.onReply();
                }),
            _AdminMenuTile(
                icon: Icons.copy_rounded,
                label: 'Copy',
                color: Colors.blueAccent,
                onTap: () {
                  Navigator.pop(c);
                  widget.onCopy();
                }),
            if (widget.isMe)
              _AdminMenuTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(c);
                    widget.onDelete();
                  }),
          ],
        ),
      ),
    );
  }

  Widget _highlighted(String text, String q) {
    final base = TextStyle(
      color: widget.isMe ? Colors.white : _kDarkText,
      fontSize: 14.5,
      height: 1.45,
    );
    if (q.isEmpty) return Text(text, style: base);

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0, idx;
    while ((idx = lower.indexOf(q, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: base));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: base.copyWith(
          color: widget.isMe ? Colors.yellow : Colors.white,
          backgroundColor: widget.isMe ? Colors.black26 : _kGreen,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + q.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: base));
    }
    return RichText(
        text: TextSpan(
            style: const TextStyle(fontSize: 14.5, height: 1.45),
            children: spans));
  }

  Widget _statusIconWidget() {
    switch (widget.status) {
      case 'sending':
        return const Icon(Icons.access_time_rounded,
            size: 12, color: Color(0xFF80CBC4));
      case 'delivered':
        return const Icon(Icons.done_all_rounded,
            size: 12, color: Color(0xFF80CBC4));
      case 'read':
        return const Icon(Icons.done_all_rounded,
            size: 12, color: Color(0xFF4FC3F7));
      default:
        return const Icon(Icons.done_rounded,
            size: 12, color: Color(0xFF80CBC4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reactionCounts = <String, int>{};
    for (final e in widget.reactions.values) {
      reactionCounts[e] = (reactionCounts[e] ?? 0) + 1;
    }
    final myReaction = widget.reactions[widget.adminId];

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment:
                widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!widget.isMe) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _kGreenPale,
                  child: Text(
                    _initials(widget.studentName),
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: _kGreen),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Column(
                crossAxisAlignment: widget.isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Reply preview
                  if (widget.replyTo != null)
                    Container(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.55),
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.isMe
                            ? Colors.black.withOpacity(0.15)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: const Border(
                            left: BorderSide(color: _kGreen, width: 3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.replyTo!['senderName'],
                            style: TextStyle(
                              color: widget.isMe ? Colors.white70 : _kGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.replyTo!['text'],
                            style: TextStyle(
                              color: widget.isMe ? Colors.white60 : Colors.grey,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  // Main bubble
                  GestureDetector(
                    onLongPress: () => _longPress(context),
                    child: Container(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.62),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: widget.isMe ? null : Colors.white,
                        gradient: widget.isMe
                            ? const LinearGradient(
                                colors: [_kGreen, _kGreenMid],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
                          bottomRight: Radius.circular(widget.isMe ? 4 : 18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (widget.isMe ? _kGreen : Colors.black)
                                .withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: widget.isMe
                            ? null
                            : Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: _highlighted(widget.text, widget.searchQuery),
                    ),
                  ),
                  // Reactions
                  if (reactionCounts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        children: reactionCounts.entries.map((e) {
                          final mine = myReaction == e.key;
                          return GestureDetector(
                            onTap: () => widget.onReact(e.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: mine ? _kGreenPale : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: mine
                                      ? _kGreenBorder
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(e.key,
                                      style: const TextStyle(fontSize: 13)),
                                  const SizedBox(width: 3),
                                  Text('${e.value}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: mine ? _kGreen : Colors.grey,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  // Time + status
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.time,
                          style: const TextStyle(
                              fontSize: 10.5, color: Color(0xFFAAAAAA))),
                      if (widget.isMe) ...[
                        const SizedBox(width: 4),
                        _statusIconWidget(),
                      ],
                    ],
                  ),
                ],
              ),
              if (widget.isMe) ...[
                const SizedBox(width: 7),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _kGreenPale,
                  child: const Icon(Icons.support_agent_rounded,
                      color: _kGreen, size: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SWIPE TO REPLY
// ─────────────────────────────────────────────────────────────────────────────

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply(
      {required this.child, required this.onSwipe, required this.isMe});
  final Widget child;
  final VoidCallback onSwipe;
  final bool isMe;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  bool _triggered = false;
  static const _threshold = 60.0;
  late AnimationController _snapCtrl;
  late Animation<double> _snapAnim;
  double _snapFrom = 0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _snapAnim = Tween<double>(begin: 0, end: 0)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    _snapCtrl.addListener(() => setState(() => _drag = _snapAnim.value));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    final delta = widget.isMe ? -d.delta.dx : d.delta.dx;
    if (delta < 0 && _drag <= 0) return;
    setState(() => _drag = (_drag + delta).clamp(0, _threshold * 1.3));
    if (_drag >= _threshold && !_triggered) {
      _triggered = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onEnd(DragEndDetails _) {
    if (_triggered) widget.onSwipe();
    _triggered = false;
    _snapFrom = _drag;
    _snapAnim = Tween<double>(begin: _snapFrom, end: 0)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    _snapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Stack(
        alignment: widget.isMe ? Alignment.centerLeft : Alignment.centerRight,
        children: [
          Opacity(
            opacity: (_drag / _threshold).clamp(0, 1),
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.isMe ? 8 : 0,
                right: widget.isMe ? 0 : 8,
              ),
              child: const Icon(Icons.reply_rounded, color: _kGreen, size: 20),
            ),
          ),
          Transform.translate(
            offset: Offset(widget.isMe ? -_drag : _drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _AdminMenuTile extends StatelessWidget {
  const _AdminMenuTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      onTap: onTap,
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year)
      return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.day == yesterday.day && date.month == yesterday.month)
      return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFDCEDEB),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(_label(),
              style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF4A7A74),
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// ── Utilities ────────────────────────────────────────────────────────────────

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
}

Color _statusColor(String s) {
  switch (s) {
    case 'resolved':
      return Colors.teal;
    case 'pending':
      return Colors.orange;
    default:
      return _kGreenAccent;
  }
}

IconData _statusIcon(String s) {
  switch (s) {
    case 'resolved':
      return Icons.check_circle_outline_rounded;
    case 'pending':
      return Icons.hourglass_empty_rounded;
    default:
      return Icons.chat_bubble_outline_rounded;
  }
}
