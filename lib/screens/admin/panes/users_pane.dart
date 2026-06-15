import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../constants/admin_theme.dart';
import '../../../../utils/admin_helpers.dart';
import '../widgets/shared_widgets.dart';
import '../../../../utils/admin_helpers.dart';
import '../../../../utils/activity_logger.dart';
// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String _fmtDate(dynamic ts) {
  if (ts == null) return '—';
  final dt = ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : null);
  if (dt == null) return '—';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
}

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}

// ─────────────────────────────────────────────────────────────────────────────
// USERS PANE  — tabbed: Admins | Students
// ─────────────────────────────────────────────────────────────────────────────

class UsersPane extends StatefulWidget {
  const UsersPane({super.key});

  @override
  State<UsersPane> createState() => _UsersPaneState();
}

class _UsersPaneState extends State<UsersPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this); // was 2
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F0),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          _UsersHeader(
            tab: _tab,
            onAddAdmin: () => _showAdminDialog(context, null),
          ),

          // ── Search bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _SearchBar(
              controller: _searchCtrl,
              hint: _tab.index == 0
                  ? 'Search admins by name or email…'
                  : _tab.index == 1
                      ? 'Search landlords by name, email or phone…'
                      : 'Search students by name, email or phone…',
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),

          // ── Stream + content ─────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: db.collection('users').orderBy('username').snapshots(),
              builder: (_, usersSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: db.collection('landlords').snapshots(),
                  builder: (_, landlordsSnap) {
                    if (usersSnap.connectionState == ConnectionState.waiting ||
                        landlordsSnap.connectionState ==
                            ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: kGreen));
                    }
                    if (usersSnap.hasError) {
                      return Center(
                          child: Text('Users Error: ${usersSnap.error}'));
                    }
                    if (landlordsSnap.hasError) {
                      return Center(
                          child:
                              Text('Landlords Error: ${landlordsSnap.error}'));
                    }

                    final allDocs = usersSnap.data?.docs ?? [];
                    final landlordDocs = landlordsSnap.data?.docs ?? [];

                    // Split users by role
                    var admins = allDocs
                        .where((d) =>
                            ((d.data() as Map)['role'] ?? '')
                                .toString()
                                .toLowerCase() ==
                            'admin')
                        .toList();

                    var students = allDocs.where((d) {
                      final r = ((d.data() as Map)['role'] ?? 'student')
                          .toString()
                          .toLowerCase();
                      return r == 'student';
                    }).toList();

                    // Landlords come from their own collection
                    var landlords = landlordDocs.toList();

                    // Apply search
                    if (_search.isNotEmpty) {
                      admins = admins.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return ['username', 'email'].any((k) =>
                            (data[k]?.toString() ?? '')
                                .toLowerCase()
                                .contains(_search));
                      }).toList();

                      students = students.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return ['username', 'email', 'phone'].any((k) =>
                            (data[k]?.toString() ?? '')
                                .toLowerCase()
                                .contains(_search));
                      }).toList();

                      landlords = landlords.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return ['full_name', 'email', 'phone'].any((k) =>
                            (data[k]?.toString() ?? '')
                                .toLowerCase()
                                .contains(_search));
                      }).toList();
                    }

                    return TabBarView(
                      controller: _tab,
                      children: [
                        _AdminsTab(
                          docs: admins,
                          totalAdmins: allDocs
                              .where((d) =>
                                  ((d.data() as Map)['role'] ?? '')
                                      .toString()
                                      .toLowerCase() ==
                                  'admin')
                              .length,
                          onEdit: (doc) => _showAdminDialog(context, doc),
                          onDelete: (doc) => _confirmDelete(context, doc),
                        ),
                        _LandlordsTab(
                          docs: landlords,
                          totalLandlords: landlordDocs.length,
                          onDelete: (doc) => _confirmDelete(context, doc),
                        ),
                        _StudentsTab(
                          docs: students,
                          totalStudents: allDocs.where((d) {
                            final r = ((d.data() as Map)['role'] ?? 'student')
                                .toString()
                                .toLowerCase();
                            return r == 'student';
                          }).length,
                          onDelete: (doc) => _confirmDelete(context, doc),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Add / Edit Admin dialog ───────────────────────────────────────────────
  void _showAdminDialog(BuildContext ctx, QueryDocumentSnapshot? doc) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _AdminFormDialog(
        existingDoc: doc,
        onSave: (username, email, password) async {
          Navigator.pop(ctx);
          if (doc == null) {
            // Add new admin
            await db.collection('users').add({
              'username': username,
              'email': email,
              'password': password,
              'role': 'admin',
              'createdAt': FieldValue.serverTimestamp(),
            });
            await ActivityLogger.log(
              action: 'Created Admin',
              details: 'Username: $username, Email: $email',
            );

            if (ctx.mounted) {
              _showSnack(ctx, 'Admin "$username" added.', kGreen);
            }
          } else {
            // Edit ex
            // isting

            final updates = <String, dynamic>{
              'username': username,
              'email': email,
            };
            if (password.isNotEmpty) updates['password'] = password;
            await db.collection('users').doc(doc.id).update(updates);
            if (ctx.mounted) {
              _showSnack(ctx, 'Admin "$username" updated.', kGreen);
            }
          }
        },
      ),
    );
  }

  // ── Delete confirm ────────────────────────────────────────────────────────
  void _confirmDelete(BuildContext ctx, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Landlords use full_name, users use username
    final username = data['full_name'] ?? data['username'] ?? 'this user';
    // Detect which collection based on fields
    final isLandlord = data.containsKey('landlord_code');

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _ConfirmDeleteDialog(
        username: username,
        onConfirm: () async {
          Navigator.pop(ctx);
          final collection = isLandlord ? 'landlords' : 'users';
          await db.collection(collection).doc(doc.id).delete();
          if (ctx.mounted) {
            _showSnack(ctx, '$username deleted.', Colors.red.shade600);
          }
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showSnack(BuildContext ctx, String msg, Color color) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER  with tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _UsersHeader extends StatelessWidget {
  const _UsersHeader({required this.tab, required this.onAddAdmin});
  final TabController tab;
  final VoidCallback onAddAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B4332),
      child: Column(
        children: [
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.manage_accounts_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Text(
                  'User Management',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                // Add Admin button — only visible on admin tab
                AnimatedOpacity(
                  opacity: tab.index == 0 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: tab.index != 0,
                    child: GestureDetector(
                      onTap: onAddAdmin,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.4), width: 1),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 14),
                            SizedBox(width: 5),
                            Text('Add Admin',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tab bar
          TabBar(
            controller: tab,
            tabAlignment: TabAlignment.fill,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.55),
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_rounded, size: 15),
                    SizedBox(width: 6),
                    Text('Admins'),
                  ],
                ),
              ),
              Tab(
                // NEW
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.home_work_rounded, size: 15),
                    SizedBox(width: 6),
                    Text('Landlords'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.school_rounded, size: 15),
                    SizedBox(width: 6),
                    Text('Students'),
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
// SEARCH BAR
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar(
      {required this.controller, required this.onChanged, required this.hint});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        prefixIcon:
            const Icon(Icons.search, color: Color(0xFF9CA3AF), size: 19),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon:
                    const Icon(Icons.clear, size: 16, color: Color(0xFF9CA3AF)),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFF1B4332), width: 1.5),
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// LANDLORDS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _LandlordsTab extends StatelessWidget {
  const _LandlordsTab({
    required this.docs,
    required this.totalLandlords,
    required this.onDelete,
  });
  final List<QueryDocumentSnapshot> docs;
  final int totalLandlords;
  final void Function(QueryDocumentSnapshot) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _LandlordStatBanner(total: totalLandlords),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: docs.isEmpty
              ? _EmptyState(
                  icon: Icons.home_work_outlined,
                  title: 'No landlords found (${docs.length})',
                  subtitle: 'totalLandlords: $totalLandlords',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _LandlordCard(
                    index: i,
                    doc: docs[i],
                    onDelete: onDelete,
                  ),
                ),
        ),
      ],
    );
  }
}

class _LandlordStatBanner extends StatelessWidget {
  const _LandlordStatBanner({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A1B9A).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.home_work_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1),
              ),
              const Text('Registered Landlords',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.home_work_rounded, color: Colors.white24, size: 40),
        ],
      ),
    );
  }
}

class _LandlordCard extends StatelessWidget {
  const _LandlordCard({
    required this.index,
    required this.doc,
    required this.onDelete,
  });
  final int index;
  final QueryDocumentSnapshot doc;
  final void Function(QueryDocumentSnapshot) onDelete;

  static const _avatarColors = [
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFAD1457),
    Color(0xFF558B2F),
    Color(0xFF4527A0),
    Color(0xFF00695C),
  ];

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final username = d['full_name'] ?? d['username'] ?? d['fullName'] ?? '—';
    final email = d['email'] ?? '—';
    final phone = d['phone'] ?? '—';
    final joined = _fmtDate(d['createdAt']);
    final avatarColor = _avatarColors[index % _avatarColors.length];

    // Extra landlord-specific fields
    final hostelCount = d['hostelCount']?.toString() ?? '—';
    final verified = d['verified'] == true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: avatarColor.withOpacity(0.12),
                shape: BoxShape.circle,
                border:
                    Border.all(color: avatarColor.withOpacity(0.3), width: 1.5),
              ),
              child: Center(
                child: Text(
                  _initials(username),
                  style: TextStyle(
                      color: avatarColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          username,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Landlord badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E5F5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFCE93D8), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.home_work_rounded,
                                size: 9, color: Colors.purple.shade700),
                            const SizedBox(width: 3),
                            Text('landlord',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.purple.shade700)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Verified badge
                      if (verified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD8F3DC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFF1B4332).withOpacity(0.4),
                                width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded,
                                  size: 9, color: Color(0xFF1B4332)),
                              SizedBox(width: 3),
                              Text('verified',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1B4332))),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined,
                          size: 11, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          email,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 11, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Text(phone,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280))),
                      const Spacer(),
                      const Icon(Icons.calendar_today_outlined,
                          size: 10, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 3),
                      Text(joined,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Delete button
            _ActionIconBtn(
              icon: Icons.person_remove_outlined,
              color: Colors.red.shade600,
              bgColor: Colors.red.shade50,
              onTap: () => onDelete(doc),
            ),
          ],
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// ADMINS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _AdminsTab extends StatelessWidget {
  const _AdminsTab({
    required this.docs,
    required this.totalAdmins,
    required this.onEdit,
    required this.onDelete,
  });
  final List<QueryDocumentSnapshot> docs;
  final int totalAdmins;
  final void Function(QueryDocumentSnapshot) onEdit;
  final void Function(QueryDocumentSnapshot) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 14),
        // Stats banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _AdminStatBanner(total: totalAdmins),
        ),
        const SizedBox(height: 14),

        // Cards
        Expanded(
          child: docs.isEmpty
              ? _EmptyState(
                  icon: Icons.shield_outlined,
                  title: 'No admins found',
                  subtitle: 'Try a different search or add a new admin',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _AdminCard(
                    doc: docs[i],
                    onEdit: onEdit,
                    onDelete: onDelete,
                  ),
                ),
        ),
      ],
    );
  }
}

class _AdminStatBanner extends StatelessWidget {
  const _AdminStatBanner({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1B4332),
            const Color(0xFF2D6A4F),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4332).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1),
              ),
              const Text('Total Admins',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          const Text(
            'Super Admin Panel',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
  });
  final QueryDocumentSnapshot doc;
  final void Function(QueryDocumentSnapshot) onEdit;
  final void Function(QueryDocumentSnapshot) onDelete;

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final username = d['username'] ?? '—';
    final email = d['email'] ?? '—';
    final joined = _fmtDate(d['createdAt']);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF1B4332).withOpacity(0.15), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  _initials(username),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          username,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.purple.shade200, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_rounded,
                                size: 9, color: Colors.purple.shade700),
                            const SizedBox(width: 3),
                            Text('admin',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.purple.shade700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 10, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 3),
                      Text(
                        'Joined $joined',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action buttons
            Column(
              children: [
                _ActionIconBtn(
                  icon: Icons.edit_rounded,
                  color: const Color(0xFF1B4332),
                  bgColor: const Color(0xFFD8F3DC),
                  onTap: () => onEdit(doc),
                ),
                const SizedBox(height: 8),
                _ActionIconBtn(
                  icon: Icons.delete_outline_rounded,
                  color: Colors.red.shade600,
                  bgColor: Colors.red.shade50,
                  onTap: () => onDelete(doc),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDENTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _StudentsTab extends StatelessWidget {
  const _StudentsTab({
    required this.docs,
    required this.totalStudents,
    required this.onDelete,
  });
  final List<QueryDocumentSnapshot> docs;
  final int totalStudents;
  final void Function(QueryDocumentSnapshot) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 14),
        // Stats row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _StudentStatBanner(total: totalStudents),
        ),
        const SizedBox(height: 14),

        // Cards
        Expanded(
          child: docs.isEmpty
              ? _EmptyState(
                  icon: Icons.school_outlined,
                  title: 'No students found',
                  subtitle: 'Try adjusting your search',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StudentCard(
                    index: i,
                    doc: docs[i],
                    onDelete: onDelete,
                  ),
                ),
        ),
      ],
    );
  }
}

class _StudentStatBanner extends StatelessWidget {
  const _StudentStatBanner({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.school_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1),
              ),
              const Text('Registered Students',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.people_alt_rounded, color: Colors.white24, size: 40),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.index,
    required this.doc,
    required this.onDelete,
  });
  final int index;
  final QueryDocumentSnapshot doc;
  final void Function(QueryDocumentSnapshot) onDelete;

  static const _avatarColors = [
    Color(0xFF1565C0),
    Color(0xFF00695C),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF283593),
    Color(0xFF37474F),
  ];

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final username = d['username'] ?? '—';
    final email = d['email'] ?? '—';
    final phone = d['phone'] ?? '—';
    final joined = _fmtDate(d['createdAt']);
    final avatarColor = _avatarColors[index % _avatarColors.length];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: avatarColor.withOpacity(0.12),
                shape: BoxShape.circle,
                border:
                    Border.all(color: avatarColor.withOpacity(0.3), width: 1.5),
              ),
              child: Center(
                child: Text(
                  _initials(username),
                  style: TextStyle(
                      color: avatarColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined,
                          size: 11, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          email,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 11, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Text(
                        phone,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                      const Spacer(),
                      const Icon(Icons.calendar_today_outlined,
                          size: 10, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 3),
                      Text(
                        joined,
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Delete only for students
            _ActionIconBtn(
              icon: Icons.person_remove_outlined,
              color: Colors.red.shade600,
              bgColor: Colors.red.shade50,
              onTap: () => onDelete(doc),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION ICON BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _ActionIconBtn extends StatelessWidget {
  const _ActionIconBtn({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN FORM DIALOG  (Add / Edit)
// ─────────────────────────────────────────────────────────────────────────────

class _AdminFormDialog extends StatefulWidget {
  const _AdminFormDialog({
    required this.existingDoc,
    required this.onSave,
  });
  final QueryDocumentSnapshot? existingDoc;
  final void Function(String username, String email, String password) onSave;

  @override
  State<_AdminFormDialog> createState() => _AdminFormDialogState();
}

class _AdminFormDialogState extends State<_AdminFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _emailCtrl;
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  bool get isEdit => widget.existingDoc != null;

  @override
  void initState() {
    super.initState();
    final d = widget.existingDoc != null
        ? widget.existingDoc!.data() as Map<String, dynamic>
        : <String, dynamic>{};
    _usernameCtrl = TextEditingController(text: d['username'] ?? '');
    _emailCtrl = TextEditingController(text: d['email'] ?? '');
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8F3DC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.shield_rounded,
                          color: Color(0xFF1B4332), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isEdit ? 'Edit Admin' : 'Add New Admin',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827)),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Username
                _FormField(
                  label: 'Username',
                  controller: _usernameCtrl,
                  hint: 'Enter username',
                  icon: Icons.person_outline,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),

                // Email
                _FormField(
                  label: 'Email',
                  controller: _emailCtrl,
                  hint: 'Enter email address',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Password
                _PasswordField(
                  controller: _passwordCtrl,
                  obscure: _obscure,
                  isEdit: isEdit,
                  onToggle: () => setState(() => _obscure = !_obscure),
                  validator: (v) {
                    if (!isEdit && (v == null || v.isEmpty)) {
                      return 'Password required for new admin';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                          side: const BorderSide(
                              color: Color(0xFFE5E7EB), width: 1.2),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            widget.onSave(
                              _usernameCtrl.text.trim(),
                              _emailCtrl.text.trim(),
                              _passwordCtrl.text,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B4332),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                        ),
                        child: Text(isEdit ? 'Save Changes' : 'Add Admin',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            prefixIcon: Icon(icon, size: 17, color: const Color(0xFF9CA3AF)),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF1B4332), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.isEdit,
    required this.onToggle,
    this.validator,
  });
  final TextEditingController controller;
  final bool obscure;
  final bool isEdit;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Password',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151))),
            if (isEdit) ...[
              const SizedBox(width: 6),
              Text('(leave blank to keep current)',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
          decoration: InputDecoration(
            hintText: isEdit ? 'New password (optional)' : 'Enter password',
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            prefixIcon: const Icon(Icons.lock_outline,
                size: 17, color: Color(0xFF9CA3AF)),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 17,
                color: const Color(0xFF9CA3AF),
              ),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF1B4332), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIRM DELETE DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmDeleteDialog extends StatelessWidget {
  const _ConfirmDeleteDialog({
    required this.username,
    required this.onConfirm,
    required this.onCancel,
  });
  final String username;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline,
                  color: Colors.red.shade600, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirm Deletion',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to delete "$username"? This cannot be undone.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
                color: const Color(0xFFD8F3DC),
                borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 30, color: const Color(0xFF1B4332)),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827))),
          const SizedBox(height: 5),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }
}
