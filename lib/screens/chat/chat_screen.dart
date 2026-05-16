// lib/screens/chat/chat_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENHANCED CHAT SCREEN — Advanced & Modern
// New: accepts GoRouter `extra` map with optional key:
//   {'scrollToMessageId': '<firestoreDocId>'}
// When provided the list scrolls to that message and briefly highlights it.
// ─────────────────────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────────────
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _sending = false;
  bool _isTyping = false;
  bool _isMuted = false;
  bool _isSearching = false;
  String _searchQuery = '';
  Map<String, dynamic>? _replyingTo;

  // ── Scroll-to-message ──────────────────────────────────────────────────────
  /// Message ID passed in from the notification panel via GoRouter extra.
  String? _scrollToMessageId;

  /// After we've scrolled once we set this to true so we don't re-scroll on
  /// every stream update.
  bool _hasScrolledToTarget = false;

  /// The doc ID we are currently highlighting (teal flash).
  String? _highlightedMessageId;

  // ── Typing indicator ───────────────────────────────────────────────────────
  String _currentUid = '';

  // ── Animation Controllers ──────────────────────────────────────────────────
  late AnimationController _fabController;
  late AnimationController _replyBarController;
  late AnimationController _searchBarController;

  // ── Brand Colors ───────────────────────────────────────────────────────────
  static const _teal = Color(0xFF00897B);
  static const _accent = Color(0xFFE8845A);
  static const _bgColor = Color(0xFFF0F4F3);
  static const _darkText = Color(0xFF1A2E2B);

  // ── Firestore helpers ──────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> _messagesRef(String uid) =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(uid)
          .collection('messages');

  // ── Typing status ──────────────────────────────────────────────────────────
  void _updateTypingStatus(String uid, bool typing) {
    if (uid.isEmpty) return;
    FirebaseFirestore.instance
        .collection('chats')
        .doc(uid)
        .set({'studentTyping': typing}, SetOptions(merge: true)).ignore();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _replyBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _searchBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _controller.addListener(() {
      final typing = _controller.text.isNotEmpty;
      if (typing != _isTyping) {
        setState(() => _isTyping = typing);
        typing ? _fabController.forward() : _fabController.reverse();
      }
      _updateTypingStatus(_currentUid, typing);
    });

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read scrollToMessageId from GoRouter extra (only once).
    if (_scrollToMessageId == null) {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map<String, dynamic>) {
        final id = extra['scrollToMessageId'] as String?;
        if (id != null && id.isNotEmpty) {
          _scrollToMessageId = id;
        }
      }
    }
  }

  @override
  void dispose() {
    _updateTypingStatus(_currentUid, false);
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _fabController.dispose();
    _replyBarController.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  // ── Send message ───────────────────────────────────────────────────────────
  Future<void> _send(String uid, String senderName) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    _controller.clear();
    _updateTypingStatus(uid, false);

    final messageData = <String, dynamic>{
      'text': text,
      'senderUid': uid,
      'senderName': senderName,
      'role': 'student',
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
      'status': 'sent',
      'reactions': <String, String>{},
    };

    if (_replyingTo != null) {
      messageData['replyTo'] = _replyingTo;
      _clearReply();
    }

    await _messagesRef(uid).add(messageData);

    await FirebaseFirestore.instance.collection('chats').doc(uid).set({
      'studentUid': uid,
      'studentName': senderName,
      'lastMessage': text,
      'lastUpdated': FieldValue.serverTimestamp(),
      'unreadByAdmin': true,
    }, SetOptions(merge: true));

    await NotificationService.instance.notifyAdmin(
      title: 'New message from $senderName',
      body: text,
      studentUid: uid,
    );

    setState(() => _sending = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// Scroll to a specific message index and briefly highlight it.
  void _scrollToMessageIndex(int index, String docId, int totalDocs) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      // Estimate position: each item is ~72 px on average. This is good enough
      // for a smooth initial jump; the list will correct if the estimate is off.
      const estimatedItemHeight = 72.0;
      const topPadding = 16.0;
      final estimated = topPadding + index * estimatedItemHeight;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final target = estimated.clamp(0.0, maxExtent);

      _scrollController
          .animateTo(target,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic)
          .then((_) {
        // Flash-highlight the target bubble for 1.5 s then clear.
        setState(() => _highlightedMessageId = docId);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _highlightedMessageId = null);
        });
      });
    });
  }

  // ── Reply ──────────────────────────────────────────────────────────────────
  void _setReply(Map<String, dynamic> data, String docId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _replyingTo = {
        'id': docId,
        'text': data['text'],
        'senderName': data['role'] == 'student' ? 'You' : 'Support',
      };
    });
    _replyBarController.forward();
    _inputFocus.requestFocus();
  }

  void _clearReply() {
    setState(() => _replyingTo = null);
    _replyBarController.reverse();
  }

  // ── Delete message ─────────────────────────────────────────────────────────
  Future<void> _deleteMessage(String uid, String docId) async {
    HapticFeedback.heavyImpact();
    await _messagesRef(uid).doc(docId).delete();
  }

  // ── Toggle reaction ────────────────────────────────────────────────────────
  Future<void> _toggleReaction(String uid, String docId, String emoji) async {
    final ref = _messagesRef(uid).doc(docId);
    final snap = await ref.get();
    final reactions = Map<String, String>.from(snap.data()?['reactions'] ?? {});
    if (reactions[uid] == emoji) {
      reactions.remove(uid);
    } else {
      reactions[uid] = emoji;
    }
    await ref.update({'reactions': reactions});
    HapticFeedback.selectionClick();
  }

  // ── Clear chat ─────────────────────────────────────────────────────────────
  Future<void> _clearChat(String uid) async {
    final confirm = await showDialog<bool>(
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
            child:
                const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final batch = FirebaseFirestore.instance.batch();
    final docs = await _messagesRef(uid).get();
    for (final d in docs.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    HapticFeedback.heavyImpact();
  }

  // ── Export chat ────────────────────────────────────────────────────────────
  Future<void> _exportChat(String uid) async {
    final docs = await _messagesRef(uid).orderBy('timestamp').get();
    final buffer = StringBuffer('RoomzyFind Chat Export\n${'─' * 40}\n\n');
    for (final d in docs.docs) {
      final data = d.data();
      final ts = (data['timestamp'] as Timestamp?)?.toDate();
      final time = ts != null ? _formatTime(ts) : '--:--';
      final role = data['role'] == 'student' ? 'You' : 'Support';
      buffer.writeln('[$time] $role: ${data['text']}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Chat copied to clipboard!'),
        backgroundColor: _teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Report ─────────────────────────────────────────────────────────────────
  Future<void> _reportIssue() async {
    final reasons = [
      'Inappropriate content',
      'Spam or harassment',
      'Wrong information',
      'Technical bug',
      'Other',
    ];
    String? selected;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Report an Issue',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Select a reason to help us improve.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ...reasons.map((r) => RadioListTile<String>(
                    value: r,
                    groupValue: selected,
                    onChanged: (v) => setSt(() => selected = v),
                    title: Text(r),
                    activeColor: _teal,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selected == null
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  const Text('Report submitted. Thank you!'),
                              backgroundColor: _teal,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Submit Report',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Three-dot menu ─────────────────────────────────────────────────────────
  void _showMenu(BuildContext context, String uid) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _MenuTile(
              icon: Icons.search_rounded,
              label: 'Search Messages',
              color: _teal,
              onTap: () {
                Navigator.pop(ctx);
                _toggleSearch();
              },
            ),
            _MenuTile(
              icon: _isMuted
                  ? Icons.notifications_rounded
                  : Icons.notifications_off_rounded,
              label: _isMuted ? 'Unmute Notifications' : 'Mute Notifications',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _isMuted = !_isMuted);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        _isMuted ? 'Notifications muted' : 'Notifications on'),
                    backgroundColor: _teal,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
            _MenuTile(
              icon: Icons.file_copy_outlined,
              label: 'Export Chat',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(ctx);
                _exportChat(uid);
              },
            ),
            _MenuTile(
              icon: Icons.delete_outline_rounded,
              label: 'Clear Chat',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(ctx);
                _clearChat(uid);
              },
            ),
            _MenuTile(
              icon: Icons.flag_outlined,
              label: 'Report Issue',
              color: Colors.deepOrange,
              onTap: () {
                Navigator.pop(ctx);
                _reportIssue();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() => _isSearching = !_isSearching);
    if (_isSearching) {
      _searchBarController.forward();
    } else {
      _searchBarController.reverse();
      _searchController.clear();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final userModel = auth.currentUser;

    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }

    final uid = userModel?.id ?? '';
    final name = userModel?.username ?? 'Student';
    _currentUid = uid;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: _buildAppBar(uid),
      body: uid.isEmpty
          ? _buildNotLoggedIn()
          : Column(
              children: [
                SizeTransition(
                  sizeFactor: _searchBarController,
                  child: _buildSearchBar(),
                ),
                Expanded(child: _buildMessageList(uid)),
                SizeTransition(
                  sizeFactor: _replyBarController,
                  child: _replyingTo != null
                      ? _buildReplyBar()
                      : const SizedBox.shrink(),
                ),
                _buildInputBar(uid, name),
              ],
            ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(String uid) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Container(
        decoration: const BoxDecoration(
          color: _teal,
          boxShadow: [
            BoxShadow(
                color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 1.5),
                      ),
                      child: const Icon(Icons.support_agent_rounded,
                          color: Colors.white, size: 22),
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF69F0AE),
                        shape: BoxShape.circle,
                        border: Border.all(color: _teal, width: 1.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'RoomzyFind Support',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF69F0AE),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Online · Usually replies in minutes',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_isMuted)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.notifications_off_rounded,
                        color: Colors.white.withOpacity(0.7), size: 18),
                  ),
                IconButton(
                  icon: Icon(
                    _isSearching
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: _toggleSearch,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => _showMenu(context, uid),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: _teal, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: _isSearching,
              style: const TextStyle(fontSize: 14, color: _darkText),
              decoration: const InputDecoration(
                hintText: 'Search in messages…',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child:
                  const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  // ── Reply bar ──────────────────────────────────────────────────────────────
  Widget _buildReplyBar() {
    if (_replyingTo == null) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyingTo!['senderName'],
                  style: const TextStyle(
                      color: _teal, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingTo!['text'],
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey),
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

  // ── Not logged in ──────────────────────────────────────────────────────────
  Widget _buildNotLoggedIn() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_teal.withOpacity(0.15), _accent.withOpacity(0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline_rounded,
                  color: _teal, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Sign in to chat',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _darkText)),
            const SizedBox(height: 8),
            const Text(
              'Please log in to your account to\naccess support chat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Color(0xFF6B8B87), height: 1.55),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamed('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              child: const Text('Log In',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────
  Widget _buildMessageList(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          _messagesRef(uid).orderBy('timestamp', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _teal));
        }

        var docs = snapshot.data?.docs ?? [];

        if (_searchQuery.isNotEmpty) {
          docs = docs
              .where((d) => (d.data()['text'] as String? ?? '')
                  .toLowerCase()
                  .contains(_searchQuery))
              .toList();
        }

        if (docs.isEmpty) {
          return _searchQuery.isNotEmpty
              ? _buildNoResults()
              : _buildEmptyChat();
        }

        // ── Scroll-to-target logic ───────────────────────────────────────────
        if (_scrollToMessageId != null && !_hasScrolledToTarget) {
          final targetIndex =
              docs.indexWhere((d) => d.id == _scrollToMessageId);
          if (targetIndex != -1) {
            _hasScrolledToTarget = true;
            _scrollToMessageIndex(
                targetIndex, _scrollToMessageId!, docs.length);
          } else {
            // Target not found (maybe filtered out) — just scroll to bottom.
            _hasScrolledToTarget = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _scrollToBottom());
          }
        } else if (_scrollToMessageId == null) {
          // Normal behaviour: scroll to newest message.
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
        }

        return Column(
          children: [
            // Admin typing indicator
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(uid)
                  .snapshots(),
              builder: (_, snap) {
                final data = snap.data?.data() as Map<String, dynamic>?;
                final typing = data?['adminTyping'] == true;
                if (!typing) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _teal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.support_agent_rounded,
                            color: Colors.white, size: 14),
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
                            _TypingDot(delay: 0, color: _teal),
                            _TypingDot(delay: 200, color: _teal),
                            _TypingDot(delay: 400, color: _teal),
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
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data();
                  final isMe = data['role'] == 'student';
                  final text = data['text'] as String? ?? '';
                  final ts = data['timestamp'] as Timestamp?;
                  final time = ts != null ? _formatTime(ts.toDate()) : '';
                  final reactions =
                      Map<String, String>.from(data['reactions'] ?? {});
                  final replyTo = data['replyTo'] as Map<String, dynamic>?;
                  final status = data['status'] as String? ?? 'sent';
                  final isHighlighted = doc.id == _highlightedMessageId;

                  final showDate = i == 0 ||
                      _isDifferentDay(
                        (docs[i - 1].data()['timestamp'] as Timestamp?)
                            ?.toDate(),
                        ts?.toDate(),
                      );

                  return Column(
                    key: ValueKey(doc.id),
                    children: [
                      if (showDate && ts != null) _DateChip(date: ts.toDate()),
                      _SwipeToReply(
                        isMe: isMe,
                        onSwipe: () => _setReply(data, doc.id),
                        child: _ChatBubble(
                          docId: doc.id,
                          uid: uid,
                          text: text,
                          time: time,
                          isMe: isMe,
                          accent: _accent,
                          teal: _teal,
                          animateIn: i == docs.length - 1 &&
                              _scrollToMessageId == null,
                          reactions: reactions,
                          replyTo: replyTo,
                          status: status,
                          searchQuery: _searchQuery,
                          // Flash the bubble with a teal glow when highlighted
                          isHighlighted: isHighlighted,
                          onReply: () => _setReply(data, doc.id),
                          onDelete: () => _deleteMessage(uid, doc.id),
                          onReact: (emoji) =>
                              _toggleReaction(uid, doc.id, emoji),
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

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.grey, size: 48),
          const SizedBox(height: 12),
          Text(
            'No messages matching "$_searchQuery"',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  bool _isDifferentDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.day != b.day || a.month != b.month || a.year != b.year;
  }

  // ── Empty chat ─────────────────────────────────────────────────────────────
  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_teal.withOpacity(0.12), _accent.withOpacity(0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_rounded, color: _teal, size: 38),
            ),
            const SizedBox(height: 20),
            const Text('Start a conversation',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _darkText)),
            const SizedBox(height: 8),
            const Text(
              'Our support team is here to help.\nSend us a message anytime!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Color(0xFF6B8B87), height: 1.55),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _QuickChip(
                    label: '🏠 Booking help',
                    onTap: () =>
                        _controller.text = 'I need help with my booking'),
                _QuickChip(
                    label: '💳 Payment issue',
                    onTap: () => _controller.text = 'I have a payment issue'),
                _QuickChip(
                    label: '🔑 Room access',
                    onTap: () =>
                        _controller.text = 'I need help with room access'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _buildInputBar(String uid, String name) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
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
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5F4),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color:
                      _isTyping ? _teal.withOpacity(0.4) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _inputFocus,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                style: const TextStyle(
                    fontSize: 14.5, color: _darkText, height: 1.4),
                decoration: const InputDecoration(
                  hintText: 'Message support…',
                  hintStyle:
                      TextStyle(color: Color(0xFFAAAAAA), fontSize: 14.5),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _send(uid, name),
                onChanged: (val) => _updateTypingStatus(uid, val.isNotEmpty),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _fabController,
            builder: (context, _) {
              return GestureDetector(
                onTap: _sending ? null : () => _send(uid, name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _isTyping ? _teal : const Color(0xFFE0E0E0),
                    shape: BoxShape.circle,
                    boxShadow: _isTyping
                        ? [
                            BoxShadow(
                              color: _teal.withOpacity(0.35),
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
                          Icons.send_rounded,
                          color: _isTyping
                              ? Colors.white
                              : const Color(0xFF9E9E9E),
                          size: 20,
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
            ? 12
            : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPING INDICATOR DOT
// ─────────────────────────────────────────────────────────────────────────────

class _TypingDot extends StatefulWidget {
  const _TypingDot({required this.delay, required this.color});
  final int delay;
  final Color color;

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
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SWIPE TO REPLY
// ─────────────────────────────────────────────────────────────────────────────

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.child,
    required this.onSwipe,
    required this.isMe,
  });

  final Widget child;
  final VoidCallback onSwipe;
  final bool isMe;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
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
    _snapCtrl.addListener(() {
      setState(() => _dragOffset = _snapAnim.value);
    });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    final delta = widget.isMe ? -d.delta.dx : d.delta.dx;
    if (delta < 0 && _dragOffset <= 0) return;
    setState(() {
      _dragOffset = (_dragOffset + delta).clamp(0, _threshold * 1.3);
    });
    if (_dragOffset >= _threshold && !_triggered) {
      _triggered = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onEnd(DragEndDetails _) {
    if (_triggered) widget.onSwipe();
    _triggered = false;
    _snapFrom = _dragOffset;
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
            opacity: (_dragOffset / _threshold).clamp(0, 1),
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.isMe ? 8 : 0,
                right: widget.isMe ? 0 : 8,
              ),
              child: const Icon(Icons.reply_rounded,
                  color: Color(0xFF00897B), size: 22),
            ),
          ),
          Transform.translate(
            offset: Offset(widget.isMe ? -_dragOffset : _dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAT BUBBLE
// ─────────────────────────────────────────────────────────────────────────────

class _ChatBubble extends StatefulWidget {
  const _ChatBubble({
    required this.docId,
    required this.uid,
    required this.text,
    required this.time,
    required this.isMe,
    required this.accent,
    required this.teal,
    required this.reactions,
    required this.status,
    required this.onReply,
    required this.onDelete,
    required this.onReact,
    this.animateIn = false,
    this.replyTo,
    this.searchQuery = '',
    this.isHighlighted = false,
  });

  final String docId;
  final String uid;
  final String text;
  final String time;
  final bool isMe;
  final Color accent;
  final Color teal;
  final Map<String, String> reactions;
  final String status;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final void Function(String emoji) onReact;
  final bool animateIn;
  final Map<String, dynamic>? replyTo;
  final String searchQuery;

  /// When true the bubble shows a brief teal glow to indicate it was
  /// navigated-to from the notification panel.
  final bool isHighlighted;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const _emojiPalette = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(widget.isMe ? 0.15 : -0.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    widget.animateIn ? _ctrl.forward() : (_ctrl.value = 1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _emojiPalette
                  .map((e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onReact(e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ))
                  .toList(),
            ),
            const Divider(height: 24),
            _MenuTile(
              icon: Icons.reply_rounded,
              label: 'Reply',
              color: const Color(0xFF00897B),
              onTap: () {
                Navigator.pop(ctx);
                widget.onReply();
              },
            ),
            _MenuTile(
              icon: Icons.copy_rounded,
              label: 'Copy Text',
              color: Colors.blueAccent,
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: widget.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Copied to clipboard'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
            if (widget.isMe)
              _MenuTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete Message',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onDelete();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          color: widget.isMe ? Colors.white : const Color(0xFF1A2E2B),
          fontSize: 14.5,
          height: 1.45,
        ),
      );
    }

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;

    while ((idx = lower.indexOf(query, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(
            text: text.substring(start, idx),
            style: TextStyle(
                color: widget.isMe ? Colors.white : const Color(0xFF1A2E2B))));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          color: widget.isMe ? Colors.yellow : Colors.white,
          backgroundColor:
              widget.isMe ? Colors.black26 : const Color(0xFF00897B),
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(
          text: text.substring(start),
          style: TextStyle(
              color: widget.isMe ? Colors.white : const Color(0xFF1A2E2B))));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14.5, height: 1.45),
        children: spans,
      ),
    );
  }

  Widget _statusIcon() {
    switch (widget.status) {
      case 'sending':
        return const Icon(Icons.access_time_rounded,
            size: 13, color: Color(0xFF80CBC4));
      case 'delivered':
        return const Icon(Icons.done_all_rounded,
            size: 13, color: Color(0xFF80CBC4));
      case 'read':
        return const Icon(Icons.done_all_rounded,
            size: 13, color: Color(0xFF26C6DA));
      default:
        return const Icon(Icons.done_rounded,
            size: 13, color: Color(0xFF80CBC4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reactionCounts = <String, int>{};
    for (final e in widget.reactions.values) {
      reactionCounts[e] = (reactionCounts[e] ?? 0) + 1;
    }
    final myReaction = widget.reactions[widget.uid];

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
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.teal, widget.teal.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.support_agent_rounded,
                      color: Colors.white, size: 15),
                ),
                const SizedBox(width: 7),
              ],
              Column(
                crossAxisAlignment: widget.isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (widget.replyTo != null)
                    Container(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.58),
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.isMe
                            ? Colors.black.withOpacity(0.15)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: widget.teal, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.replyTo!['senderName'],
                            style: TextStyle(
                              color: widget.isMe ? Colors.white70 : widget.teal,
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
                  // ── Main bubble — with optional highlight glow ─────────────
                  GestureDetector(
                    onLongPress: () => _showContextMenu(context),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.65),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: widget.isMe
                            ? LinearGradient(
                                colors: [
                                  widget.accent,
                                  widget.accent.withOpacity(0.85),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: widget.isMe ? null : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(widget.isMe ? 20 : 4),
                          bottomRight: Radius.circular(widget.isMe ? 4 : 20),
                        ),
                        // Highlight glow when navigated from notification
                        boxShadow: widget.isHighlighted
                            ? [
                                BoxShadow(
                                  color: widget.teal.withOpacity(0.55),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: (widget.isMe
                                          ? widget.accent
                                          : Colors.black)
                                      .withOpacity(0.12),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: _buildHighlightedText(
                          widget.text, widget.searchQuery),
                    ),
                  ),
                  if (reactionCounts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        children: reactionCounts.entries.map((e) {
                          final isMyReaction = myReaction == e.key;
                          return GestureDetector(
                            onTap: () => widget.onReact(e.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isMyReaction
                                    ? widget.teal.withOpacity(0.15)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isMyReaction
                                      ? widget.teal
                                      : Colors.grey.shade200,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(e.key,
                                      style: const TextStyle(fontSize: 13)),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${e.value}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isMyReaction
                                          ? widget.teal
                                          : Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.time,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFAAAAAA)),
                      ),
                      if (widget.isMe) ...[
                        const SizedBox(width: 4),
                        _statusIcon(),
                      ],
                    ],
                  ),
                ],
              ),
              if (widget.isMe) ...[
                const SizedBox(width: 7),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                      color: Color(0xFFE8E8E8), shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded,
                      color: Color(0xFF888888), size: 15),
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
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _MenuTile extends StatelessWidget {
  const _MenuTile({
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
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      onTap: onTap,
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2F0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF80CBC4), width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF00695C),
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.day == yesterday.day && date.month == yesterday.month) {
      return 'Yesterday';
    }
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
          child: Text(
            _label(),
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF4A7A74),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
