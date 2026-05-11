import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../utils/admin_helpers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const _kGreen = Color(0xFF1B4332);
const _kBg = Color(0xFFF2F4F0);
const _kPageSize = 50;

// ─────────────────────────────────────────────────────────────────────────────
// ACTION METADATA
// ─────────────────────────────────────────────────────────────────────────────

enum _ActionType { create, update, delete, login, logout, other }

class _ActionMeta {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;
  const _ActionMeta({
    required this.color,
    required this.bg,
    required this.icon,
    required this.label,
  });
}

const _actionMeta = <_ActionType, _ActionMeta>{
  _ActionType.create: _ActionMeta(
      color: Color(0xFF166534),
      bg: Color(0xFFDCFCE7),
      icon: Icons.add_circle_outline_rounded,
      label: 'Created'),
  _ActionType.update: _ActionMeta(
      color: Color(0xFF1D4ED8),
      bg: Color(0xFFDBEAFE),
      icon: Icons.edit_outlined,
      label: 'Updated'),
  _ActionType.delete: _ActionMeta(
      color: Color(0xFFB91C1C),
      bg: Color(0xFFFEE2E2),
      icon: Icons.delete_outline_rounded,
      label: 'Deleted'),
  _ActionType.login: _ActionMeta(
      color: Color(0xFF92400E),
      bg: Color(0xFFFEF3C7),
      icon: Icons.login_rounded,
      label: 'Login'),
  _ActionType.logout: _ActionMeta(
      color: Color(0xFF374151),
      bg: Color(0xFFF3F4F6),
      icon: Icons.logout_rounded,
      label: 'Logout'),
  _ActionType.other: _ActionMeta(
      color: Color(0xFF6B21A8),
      bg: Color(0xFFF3E8FF),
      icon: Icons.info_outline_rounded,
      label: 'Action'),
};

_ActionType _detectType(String action) {
  final a = action.toLowerCase();
  if (a.contains('creat') || a.contains('add') || a.contains('new')) {
    return _ActionType.create;
  }
  if (a.contains('updat') ||
      a.contains('edit') ||
      a.contains('modif') ||
      a.contains('chang')) {
    return _ActionType.update;
  }
  if (a.contains('delet') || a.contains('remov')) return _ActionType.delete;
  if (a.contains('login') || a.contains('sign in')) return _ActionType.login;
  if (a.contains('logout') || a.contains('sign out')) return _ActionType.logout;
  return _ActionType.other;
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER MODEL
// ─────────────────────────────────────────────────────────────────────────────

class _Filter {
  String search;
  _ActionType? actionType;
  DateTime? fromDate;
  DateTime? toDate;

  _Filter({this.search = '', this.actionType, this.fromDate, this.toDate});

  bool get isActive =>
      search.isNotEmpty ||
      actionType != null ||
      fromDate != null ||
      toDate != null;

  bool matches(Map<String, dynamic> d) {
    if (search.isNotEmpty) {
      final q = search.toLowerCase();
      final hit = [d['userEmail'], d['action'], d['details']]
          .any((v) => (v ?? '').toString().toLowerCase().contains(q));
      if (!hit) return false;
    }
    if (actionType != null &&
        _detectType((d['action'] ?? '').toString()) != actionType) {
      return false;
    }
    final ts = d['timestamp'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      if (fromDate != null && dt.isBefore(fromDate!)) return false;
      if (toDate != null && dt.isAfter(toDate!.add(const Duration(days: 1)))) {
        return false;
      }
    }
    return true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY LOG PANE
// ─────────────────────────────────────────────────────────────────────────────

class ActivityLogPane extends StatefulWidget {
  const ActivityLogPane({super.key});

  @override
  State<ActivityLogPane> createState() => _ActivityLogPaneState();
}

class _ActivityLogPaneState extends State<ActivityLogPane>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _filter = _Filter();

  StreamSubscription<QuerySnapshot>? _sub;
  List<QueryDocumentSnapshot> _allDocs = [];
  bool _isLive = true;
  bool _isLoading = true;
  String? _error;

  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _loadingMore = false;

  final Set<String> _newIds = {};
  bool _firstLoad = true;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(_pulseCtrl);
    _startStream();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Stream ────────────────────────────────────────────────────────────────
  void _startStream() {
    _sub?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
      _allDocs = [];
      _lastDoc = null;
      _hasMore = true;
      _firstLoad = true;
    });

    _sub = db
        .collection('activityLog')
        .orderBy('timestamp', descending: true)
        .limit(_kPageSize)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final incoming = snap.docs;

        if (!_firstLoad) {
          final existingIds = _allDocs.map((d) => d.id).toSet();
          final newEntries =
              incoming.where((d) => !existingIds.contains(d.id)).toList();
          if (newEntries.isNotEmpty) {
            final newEntryIds = newEntries.map((d) => d.id).toSet();
            setState(() => _newIds.addAll(newEntryIds));
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) setState(() => _newIds.removeAll(newEntryIds));
            });
          }
        }

        setState(() {
          _allDocs = incoming;
          _isLoading = false;
          _firstLoad = false;
          _hasMore = incoming.length == _kPageSize;
          if (incoming.isNotEmpty) _lastDoc = incoming.last;
        });
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
        }
      },
    );
  }

  void _toggleLive() {
    if (_isLive) {
      _sub?.cancel();
      _sub = null;
      setState(() => _isLive = false);
    } else {
      setState(() => _isLive = true);
      _startStream();
    }
  }

  // ── Load more ─────────────────────────────────────────────────────────────
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await db
          .collection('activityLog')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_kPageSize)
          .get();

      if (!mounted) return;
      setState(() {
        _allDocs = [..._allDocs, ...snap.docs];
        _hasMore = snap.docs.length == _kPageSize;
        if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Export CSV ────────────────────────────────────────────────────────────
  Future<void> _exportCsv(List<QueryDocumentSnapshot> docs) async {
    final buf = StringBuffer();
    buf.writeln('User Email,Action,Details,Timestamp,Type');
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['timestamp'];
      final dateStr = ts is Timestamp
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(ts.toDate())
          : '—';
      final type = _detectType((d['action'] ?? '').toString());
      buf.writeln([
        _csvEscape(d['userEmail'] ?? '—'),
        _csvEscape(d['action'] ?? '—'),
        _csvEscape(d['details'] ?? '—'),
        _csvEscape(dateStr),
        _csvEscape(_actionMeta[type]!.label),
      ].join(','));
    }

    final csvContent = buf.toString();
    final fileName =
        'activity_log_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';

    try {
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: csvContent));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'CSV copied to clipboard (web export — paste into a .csv file)'),
              backgroundColor: _kGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(csvContent, encoding: utf8);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv')],
          subject: 'RoomzyFind Activity Log',
          text: 'Exported ${docs.length} entries — $fileName',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  // ── Delete a single entry ─────────────────────────────────────────────────
  Future<bool> _deleteSingle(QueryDocumentSnapshot doc) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await doc.reference.delete();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Log entry deleted'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete entry: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return false;
    }
  }

  // ── Clear filtered entries ────────────────────────────────────────────────
  Future<void> _clearFiltered(List<QueryDocumentSnapshot> filtered) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Clear Filtered Logs',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content:
            Text('This will permanently delete ${filtered.length} visible log '
                'entries. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Firestore batch limit is 500 — chunk if needed
      const chunkSize = 500;
      for (int i = 0; i < filtered.length; i += chunkSize) {
        final chunk =
            filtered.sublist(i, (i + chunkSize).clamp(0, filtered.length));
        final batch = db.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('${filtered.length} log entries deleted'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── Clear ALL logs ────────────────────────────────────────────────────────
  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Clear All Logs',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content:
            const Text('This will permanently delete ALL activity log entries. '
                'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                const Text('Delete All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      const chunkSize = 500;
      for (int i = 0; i < _allDocs.length; i += chunkSize) {
        final chunk =
            _allDocs.sublist(i, (i + chunkSize).clamp(0, _allDocs.length));
        final batch = db.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      messenger.showSnackBar(
        SnackBar(
          content: const Text('All activity logs cleared'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to clear logs: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── Date picker ───────────────────────────────────────────────────────────
  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          (isFrom ? _filter.fromDate : _filter.toDate) ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _kGreen),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _filter.fromDate = picked;
        } else {
          _filter.toDate = picked;
        }
      });
    }
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Map<_ActionType, int> _computeStats(List<QueryDocumentSnapshot> docs) {
    final m = <_ActionType, int>{};
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final t = _detectType((d['action'] ?? '').toString());
      m[t] = (m[t] ?? 0) + 1;
    }
    return m;
  }

  // ── Top users ─────────────────────────────────────────────────────────────
  List<MapEntry<String, int>> _topUsers(List<QueryDocumentSnapshot> docs) {
    final m = <String, int>{};
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final email = (d['userEmail'] ?? '').toString();
      if (email.isNotEmpty) m[email] = (m[email] ?? 0) + 1;
    }
    final sorted = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allDocs.where((doc) {
      return _filter.matches(doc.data() as Map<String, dynamic>);
    }).toList();

    final stats = _computeStats(_allDocs);
    final topUsers = _topUsers(_allDocs);

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          _LogHeader(
            isLive: _isLive,
            pulseAnim: _pulseAnim,
            totalCount: filtered.length,
            onExport: () => _exportCsv(filtered),
            onToggleLive: _toggleLive,
            hasActiveFilter: _filter.isActive,
            onClearFiltered: () => _clearFiltered(filtered),
            onClearAll: _clearAll,
          ),

          // ── Stats row ─────────────────────────────────────────────────
          _StatsRow(
            stats: stats,
            selectedType: _filter.actionType,
            onTypeTapped: (t) => setState(
                () => _filter.actionType = _filter.actionType == t ? null : t),
          ),

          // ── Top users strip ───────────────────────────────────────────
          if (topUsers.isNotEmpty) _TopUsersStrip(topUsers: topUsers),

          // ── Filter bar ────────────────────────────────────────────────
          _FilterBar(
            searchCtrl: _searchCtrl,
            filter: _filter,
            onSearchChanged: (v) => setState(() => _filter.search = v),
            onTypeChanged: (t) => setState(() => _filter.actionType = t),
            onFromDate: () => _pickDate(isFrom: true),
            onToDate: () => _pickDate(isFrom: false),
            onClearDates: () => setState(() {
              _filter.fromDate = null;
              _filter.toDate = null;
            }),
          ),

          // ── Content ───────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _kGreen))
                : _error != null
                    ? _ErrorState(error: _error!)
                    : filtered.isEmpty
                        ? const _EmptyState()
                        : _Timeline(
                            docs: filtered,
                            newIds: _newIds,
                            hasMore: _hasMore,
                            loadingMore: _loadingMore,
                            onLoadMore: _loadMore,
                            onDeleteEntry: _deleteSingle,
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

class _LogHeader extends StatelessWidget {
  const _LogHeader({
    required this.isLive,
    required this.pulseAnim,
    required this.totalCount,
    required this.onExport,
    required this.onToggleLive,
    required this.hasActiveFilter,
    required this.onClearFiltered,
    required this.onClearAll,
  });

  final bool isLive;
  final Animation<double> pulseAnim;
  final int totalCount;
  final VoidCallback onExport;
  final VoidCallback onToggleLive;
  final bool hasActiveFilter;
  final VoidCallback onClearFiltered;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kGreen,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Text(
            'Activity Log',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$totalCount entries',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const Spacer(),

          // ── Live / Paused toggle ──────────────────────────────────────
          GestureDetector(
            onTap: onToggleLive,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withOpacity(0.25), width: 1),
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: pulseAnim,
                    builder: (_, __) => Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLive
                            ? Color.lerp(Colors.greenAccent,
                                Colors.green.shade300, pulseAnim.value)!
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isLive ? 'Live' : 'Paused',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ── Export ────────────────────────────────────────────────────
          GestureDetector(
            onTap: onExport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withOpacity(0.25), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.download_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 5),
                  Text('Export',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ── Clear (popup menu) ────────────────────────────────────────
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'filtered') onClearFiltered();
              if (val == 'all') onClearAll();
            },
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Colors.white,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.red.withOpacity(0.35), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.delete_sweep_rounded,
                      color: Colors.white, size: 13),
                  SizedBox(width: 5),
                  Text('Clear',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            itemBuilder: (_) => [
              if (hasActiveFilter)
                PopupMenuItem(
                  value: 'filtered',
                  child: Row(
                    children: const [
                      Icon(Icons.filter_alt_off_rounded,
                          size: 16, color: Colors.orange),
                      SizedBox(width: 10),
                      Text('Clear filtered entries',
                          style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'all',
                child: Row(
                  children: const [
                    Icon(Icons.delete_forever_rounded,
                        size: 16, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Clear ALL logs',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.stats,
    required this.selectedType,
    required this.onTypeTapped,
  });

  final Map<_ActionType, int> stats;
  final _ActionType? selectedType;
  final ValueChanged<_ActionType> onTypeTapped;

  @override
  Widget build(BuildContext context) {
    final items = _ActionType.values;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: items.map((type) {
          final meta = _actionMeta[type]!;
          final count = stats[type] ?? 0;
          final isSelected = selectedType == type;

          return Expanded(
            child: GestureDetector(
              onTap: () => onTypeTapped(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: meta.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? meta.color.withOpacity(0.7)
                        : Colors.transparent,
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: meta.color.withOpacity(0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(meta.icon, color: meta.color, size: 16),
                    const SizedBox(height: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: meta.color,
                          height: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta.label,
                      style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: meta.color.withOpacity(0.75)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP USERS STRIP
// ─────────────────────────────────────────────────────────────────────────────

class _TopUsersStrip extends StatelessWidget {
  const _TopUsersStrip({required this.topUsers});
  final List<MapEntry<String, int>> topUsers;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          const Text('Most active:',
              style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          ...topUsers.map((entry) {
            final email = entry.key;
            final count = entry.value;
            final letter = email.isNotEmpty ? email[0].toUpperCase() : '?';
            return Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: _kGreen,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(letter,
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    email.split('@').first,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151)),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '($count)',
                    style:
                        const TextStyle(fontSize: 9, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER BAR
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtrl,
    required this.filter,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onFromDate,
    required this.onToDate,
    required this.onClearDates,
  });

  final TextEditingController searchCtrl;
  final _Filter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ActionType?> onTypeChanged;
  final VoidCallback onFromDate;
  final VoidCallback onToDate;
  final VoidCallback onClearDates;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM');
    final hasDateFilter = filter.fromDate != null || filter.toDate != null;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        children: [
          // ── Search ────────────────────────────────────────────────────
          TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
            decoration: InputDecoration(
              hintText: 'Search by user, action or details…',
              hintStyle:
                  const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
              prefixIcon:
                  const Icon(Icons.search, color: Color(0xFF9CA3AF), size: 18),
              suffixIcon: searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          size: 15, color: Color(0xFF9CA3AF)),
                      onPressed: () {
                        searchCtrl.clear();
                        onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kGreen, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Type chips + date pickers ─────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  icon: Icons.list_rounded,
                  color: _kGreen,
                  bg: const Color(0xFFD8F3DC),
                  selected: filter.actionType == null,
                  onTap: () => onTypeChanged(null),
                ),
                const SizedBox(width: 6),
                ..._ActionType.values.map((type) {
                  final meta = _actionMeta[type]!;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: meta.label,
                      icon: meta.icon,
                      color: meta.color,
                      bg: meta.bg,
                      selected: filter.actionType == type,
                      onTap: () => onTypeChanged(
                          filter.actionType == type ? null : type),
                    ),
                  );
                }),
                const SizedBox(width: 4),
                const VerticalDivider(
                    width: 16, thickness: 1, color: Color(0xFFE5E7EB)),
                const SizedBox(width: 4),
                _DateChip(
                  label: filter.fromDate != null
                      ? 'From: ${fmt.format(filter.fromDate!)}'
                      : 'From date',
                  icon: Icons.calendar_today_outlined,
                  onTap: onFromDate,
                  active: filter.fromDate != null,
                ),
                const SizedBox(width: 6),
                _DateChip(
                  label: filter.toDate != null
                      ? 'To: ${fmt.format(filter.toDate!)}'
                      : 'To date',
                  icon: Icons.event_outlined,
                  onTap: onToDate,
                  active: filter.toDate != null,
                ),
                if (hasDateFilter) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onClearDates,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.red.shade200, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.close,
                              size: 12, color: Colors.red.shade600),
                          const SizedBox(width: 3),
                          Text('Clear dates',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade600,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? bg : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : const Color(0xFFE5E7EB),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12, color: selected ? color : const Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? color : const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.active,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFD8F3DC) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? _kGreen.withOpacity(0.4) : const Color(0xFFE5E7EB),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12, color: active ? _kGreen : const Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? _kGreen : const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMELINE
// ─────────────────────────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.docs,
    required this.newIds,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onDeleteEntry,
  });

  final List<QueryDocumentSnapshot> docs;
  final Set<String> newIds;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final Future<bool> Function(QueryDocumentSnapshot) onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    // Group by date
    final groups = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['timestamp'];
      String dateKey = 'Unknown';
      if (ts is Timestamp) {
        final dt = ts.toDate();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final docDay = DateTime(dt.year, dt.month, dt.day);
        if (docDay == today) {
          dateKey = 'Today';
        } else if (docDay == yesterday) {
          dateKey = 'Yesterday';
        } else {
          dateKey = DateFormat('EEEE, dd MMM yyyy').format(dt);
        }
      }
      groups.putIfAbsent(dateKey, () => []).add(doc);
    }

    final dateKeys = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: dateKeys.length + 1,
      itemBuilder: (_, i) {
        // ── Load more footer ─────────────────────────────────────────
        if (i == dateKeys.length) {
          if (loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: CircularProgressIndicator(
                      color: _kGreen, strokeWidth: 2)),
            );
          }
          if (hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: GestureDetector(
                  onTap: onLoadMore,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: const Color(0xFFD1D5DB), width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.expand_more_rounded,
                            size: 16, color: _kGreen),
                        SizedBox(width: 6),
                        Text('Load more',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _kGreen)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                '${docs.length} entries total — all loaded',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ),
          );
        }

        // ── Date group ───────────────────────────────────────────────
        final key = dateKeys[i];
        final dayDocs = groups[key]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(key,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child:
                          Divider(color: Colors.grey.shade300, thickness: 0.8)),
                  const SizedBox(width: 8),
                  Text('${dayDocs.length} events',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
            ...dayDocs.asMap().entries.map((entry) {
              final idx = entry.key;
              final doc = entry.value;
              final isNew = newIds.contains(doc.id);
              final isLast = idx == dayDocs.length - 1;

              return Dismissible(
                key: ValueKey(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: Colors.red.shade600, size: 20),
                      const SizedBox(width: 6),
                      Text('Delete',
                          style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      title: const Text('Delete Entry',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      content: const Text('Remove this log entry permanently?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                          child: const Text('Delete',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (_) => onDeleteEntry(doc),
                child: _TimelineEntry(doc: doc, isNew: isNew, isLast: isLast),
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMELINE ENTRY
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineEntry extends StatefulWidget {
  const _TimelineEntry({
    required this.doc,
    required this.isNew,
    required this.isLast,
  });
  final QueryDocumentSnapshot doc;
  final bool isNew;
  final bool isLast;

  @override
  State<_TimelineEntry> createState() => _TimelineEntryState();
}

class _TimelineEntryState extends State<_TimelineEntry> {
  bool _expanded = false;
  bool _copied = false;

  Future<void> _copyEntry(Map<String, dynamic> d) async {
    final ts = d['timestamp'];
    final map = {
      'id': widget.doc.id,
      'userEmail': d['userEmail'] ?? '',
      'action': d['action'] ?? '',
      'details': d['details'] ?? '',
      'timestamp': ts is Timestamp
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(ts.toDate())
          : '',
    };
    await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(map)));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final email = (d['userEmail'] ?? '—').toString();
    final action = (d['action'] ?? '—').toString();
    final details = (d['details'] ?? '').toString();
    final type = _detectType(action);
    final meta = _actionMeta[type]!;

    final ts = d['timestamp'];
    String timeStr = '—';
    String fullDateStr = '';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      timeStr = DateFormat('HH:mm').format(dt);
      fullDateStr = DateFormat('dd MMM yyyy, HH:mm:ss').format(dt);
    }

    final letter = email.isNotEmpty ? email[0].toUpperCase() : '?';
    final hasLongDetails = details.length > 80;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline dot + connector ──────────────────────────────
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: meta.bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: meta.color.withOpacity(0.4), width: 1.5),
                  ),
                  child: Icon(meta.icon, size: 13, color: meta.color),
                ),
                if (!widget.isLast)
                  Expanded(
                    child: Center(
                      child:
                          Container(width: 1.5, color: const Color(0xFFE5E7EB)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ── Card ─────────────────────────────────────────────────
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: widget.isNew ? meta.bg.withOpacity(0.5) : Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: widget.isNew
                      ? meta.color.withOpacity(0.4)
                      : const Color(0xFFE5E7EB),
                  width: widget.isNew ? 1.2 : 0.6,
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top row ─────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: meta.bg, shape: BoxShape.circle),
                          child: Center(
                            child: Text(letter,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: meta.color)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(email,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827)),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (widget.isNew)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.shade700,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('NEW',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                        GestureDetector(
                          onTap: () => _copyEntry(d),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              _copied
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.copy_outlined,
                              size: 14,
                              color: _copied
                                  ? Colors.green.shade600
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 10, color: Color(0xFF9CA3AF)),
                            const SizedBox(width: 3),
                            Text(timeStr,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ── Action badge ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: meta.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: meta.color.withOpacity(0.25), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(meta.icon, size: 11, color: meta.color),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(action,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: meta.color),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),

                    // ── Details (expandable) ─────────────────────────
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: hasLongDetails
                            ? () => setState(() => _expanded = !_expanded)
                            : null,
                        child: Text(
                          details,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                              height: 1.4),
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasLongDetails)
                        GestureDetector(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              _expanded ? 'Show less' : 'Show more',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: _kGreen,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],

                    // ── Full timestamp (expanded) ────────────────────
                    if (_expanded && fullDateStr.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 10, color: Color(0xFF9CA3AF)),
                          const SizedBox(width: 4),
                          Text(fullDateStr,
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xFF9CA3AF))),
                          const Spacer(),
                          Text('ID: ${widget.doc.id.substring(0, 8)}…',
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFFD1D5DB),
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    ],
                  ],
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
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFD8F3DC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.history_rounded, size: 30, color: _kGreen),
          ),
          const SizedBox(height: 14),
          const Text('No activity found',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827))),
          const SizedBox(height: 5),
          const Text('Try adjusting your filters or search',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ERROR STATE
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.cloud_off_rounded,
                  size: 30, color: Colors.red.shade600),
            ),
            const SizedBox(height: 14),
            const Text('Permission Error',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
            const SizedBox(height: 6),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280), height: 1.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Text(
                'Fix: Ensure your Firestore rules allow admin reads on the '
                'activityLog collection, and that your user document has '
                'role == "admin".',
                style: TextStyle(
                    fontSize: 11, color: Color(0xFF92400E), height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
