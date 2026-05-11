import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../constants/admin_theme.dart';
import '../../../../utils/admin_helpers.dart';
import '../widgets/dialog_widgets.dart';
import '../widgets/form_widgets.dart';
import '../widgets/shared_widgets.dart';
import '../../../../utils/activity_logger.dart';
// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

bool _isPhone(BuildContext context) => MediaQuery.of(context).size.width < 600;

double _dialogWidth(BuildContext context, {double maxPx = 500}) {
  final w = MediaQuery.of(context).size.width;
  if (w < 600) return w * 0.95;
  if (w < 900) return w * 0.75;
  return maxPx.clamp(0.0, w * 0.55);
}

double _dialogMaxHeight(BuildContext context) {
  final h = MediaQuery.of(context).size.height;
  return _isPhone(context) ? h * 0.92 : h * 0.85;
}

// ─────────────────────────────────────────────────────────────────────────────
// SCHOOLS PANE
// ─────────────────────────────────────────────────────────────────────────────

class SchoolsPane extends StatefulWidget {
  const SchoolsPane({super.key});

  @override
  State<SchoolsPane> createState() => _SchoolsPaneState();
}

class _SchoolsPaneState extends State<SchoolsPane> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_isPhone(context) ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header + search — stable, never inside StreamBuilder ───────────
          _SchoolsHeader(
            search: _search,
            onSearch: (v) => setState(() => _search = v),
            onAdd: _openAdd,
          ),
          const SizedBox(height: 20),

          // ── Stream ─────────────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('schools').orderBy('full_name').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const CardLoading(height: 200);
              }
              if (snap.hasError) {
                return EmptyCard(message: 'Error: ${snap.error}', height: 120);
              }

              var docs = snap.data?.docs ?? [];

              if (_search.isNotEmpty) {
                final q = _search.toLowerCase();
                docs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return [
                    'full_name',
                    'short_name',
                    'town',
                    'school_code'
                  ].any((k) =>
                      (data[k]?.toString() ?? '').toLowerCase().contains(q));
                }).toList();
              }

              if (docs.isEmpty) {
                return const EmptyCard(
                    message: 'No schools found', height: 160);
              }

              return _SchoolGrid(
                itemCount: docs.length,
                itemBuilder: (i) => _SchoolCard(
                  doc: docs[i],
                  onEdit: () => _openEdit(docs[i]),
                  onDelete: () async {
                    final schoolData = docs[i].data() as Map<String, dynamic>;
                    final schoolName =
                        schoolData['full_name']?.toString() ?? 'Unknown';
                    await ActivityLogger.log(
                      action: 'Deleted School',
                      details: 'School: $schoolName',
                    );
                    confirmDelete(context, 'schools', docs[i].id);
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _openAdd() => showDialog(
        context: context,
        builder: (_) => _SchoolDialog(parentContext: context),
      );

  void _openEdit(QueryDocumentSnapshot doc) => showDialog(
        context: context,
        builder: (_) => _SchoolDialog(doc: doc, parentContext: context),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _SchoolsHeader extends StatelessWidget {
  const _SchoolsHeader({
    required this.search,
    required this.onSearch,
    required this.onAdd,
  });
  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;

      if (w < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('All Schools'),
            const SizedBox(height: 10),
            SearchBox(value: search, onChanged: onSearch),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: _AddBtn(onTap: onAdd)),
          ],
        );
      }

      if (w < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('All Schools'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: SearchBox(value: search, onChanged: onSearch)),
              const SizedBox(width: 8),
              _AddBtn(onTap: onAdd),
            ]),
          ],
        );
      }

      return Row(children: [
        const Expanded(child: SectionLabel('All Schools')),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: 120, maxWidth: w < 800 ? 180 : 260),
          child: SearchBox(value: search, onChanged: onSearch),
        ),
        const SizedBox(width: 12),
        _AddBtn(onTap: onAdd),
      ]);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE CARD GRID
// ─────────────────────────────────────────────────────────────────────────────

class _SchoolGrid extends StatelessWidget {
  const _SchoolGrid({
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final int cols = w < 560 ? 1 : (w < 900 ? 2 : 3);
      const double gap = 16;
      final cardW = (w - gap * (cols - 1)) / cols;

      final rows = <Widget>[];
      for (var i = 0; i < itemCount; i += cols) {
        final rowChildren = <Widget>[];
        for (var j = 0; j < cols; j++) {
          if (j > 0) rowChildren.add(const SizedBox(width: gap));
          if (i + j < itemCount) {
            rowChildren.add(SizedBox(width: cardW, child: itemBuilder(i + j)));
          } else {
            rowChildren.add(SizedBox(width: cardW));
          }
        }
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowChildren,
        ));
      }

      return Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) const SizedBox(height: gap),
          ],
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCHOOL CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SchoolCard extends StatelessWidget {
  const _SchoolCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
  });
  final QueryDocumentSnapshot doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;

    final fullName =
        (d['full_name']?.toString().isNotEmpty == true) ? d['full_name'] : '—';
    final shortName = (d['short_name']?.toString().isNotEmpty == true)
        ? d['short_name']
        : '—';
    final town = (d['town']?.toString().isNotEmpty == true) ? d['town'] : '—';
    final code = (d['school_code']?.toString().isNotEmpty == true)
        ? d['school_code']
        : 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Card header ─────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.school_rounded, color: kGreen, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kTextDark),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shortName,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kGreen.withOpacity(0.85),
                          letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 10),
            const Divider(height: 1, color: kBorder),
            const SizedBox(height: 10),

            // ── Info rows ───────────────────────────────────────────────────
            _InfoRow(label: 'Code', value: code),
            _InfoRow(label: 'Town', value: town),

            const SizedBox(height: 12),

            // ── Action buttons ──────────────────────────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                _CardBtn(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: Colors.orange,
                  onTap: onEdit,
                ),
                _CardBtn(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: Colors.red,
                  onTap: onDelete,
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
// SCHOOL ADD / EDIT DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _SchoolDialog extends StatefulWidget {
  const _SchoolDialog({this.doc, required this.parentContext});
  final QueryDocumentSnapshot? doc;
  final BuildContext parentContext;

  @override
  State<_SchoolDialog> createState() => _SchoolDialogState();
}

class _SchoolDialogState extends State<_SchoolDialog> {
  final _fullName = TextEditingController();
  final _shortName = TextEditingController();
  final _town = TextEditingController();
  final _code = TextEditingController();

  bool _saving = false;
  String? _validationError;

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final d = widget.doc!.data() as Map<String, dynamic>;
      _fullName.text = d['full_name'] ?? '';
      _shortName.text = d['short_name'] ?? '';
      _town.text = d['town'] ?? '';
      _code.text = d['school_code'] ?? '';
    }
    _shortName.addListener(_genCode);
    _town.addListener(_genCode);
  }

  // Auto-generate school code: SHORTNAME-TOWN (e.g. UG-ACCRA)
  void _genCode() {
    if (_isEdit) return;
    final s = _shortName.text.trim().toUpperCase();
    final t = _town.text.trim().replaceAll(' ', '').toUpperCase();
    if (s.isNotEmpty && t.isNotEmpty) {
      _code.text = '$s-$t';
    } else if (s.isNotEmpty) {
      _code.text = s;
    }
  }

  Future<void> _save() async {
    final fullNameVal = _fullName.text.trim();
    final shortNameVal = _shortName.text.trim();
    final townVal = _town.text.trim();

    if (fullNameVal.isEmpty || shortNameVal.isEmpty || townVal.isEmpty) {
      setState(() {
        final missing = [
          if (fullNameVal.isEmpty) 'Full Name',
          if (shortNameVal.isEmpty) 'Short Name',
          if (townVal.isEmpty) 'Town',
        ];
        _validationError = 'Required: ${missing.join(', ')}';
      });
      return;
    }

    setState(() {
      _saving = true;
      _validationError = null;
    });

    final data = <String, dynamic>{
      'full_name': fullNameVal,
      'short_name': shortNameVal,
      'town': townVal,
      'school_code': _code.text.trim(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEdit) {
        await db.collection('schools').doc(widget.doc!.id).update(data);
        // ✅ ADD THIS
        await ActivityLogger.log(
          action: 'Updated School',
          details: 'School: $fullNameVal ($shortNameVal)',
        );
      } else {
        data['created_at'] = FieldValue.serverTimestamp();
        await db.collection('schools').add(data);
        // ✅ ADD THIS
        await ActivityLogger.log(
          action: 'Created School',
          details: 'School: $fullNameVal, Town: $townVal',
        );
      }
      if (!mounted) return;
      final parentCtx = widget.parentContext;
      final message = _isEdit
          ? 'School Updated Successfully!'
          : 'School Added Successfully!';
      Navigator.of(context).pop();
      _showSuccessToast(parentCtx, message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationError = 'Save failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dw = _dialogWidth(context, maxPx: 500);
    final dh = _dialogMaxHeight(context);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: _isPhone(context) ? 8 : 24,
        vertical: _isPhone(context) ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dw,
        height: dh,
        child: Column(
          children: [
            dialogHeader(_isEdit ? 'Edit School' : 'Add School'),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_validationError != null)
                      _ValidationBanner(_validationError!),
                    AdminFormField(
                      label: 'Full School Name *',
                      controller: _fullName,
                      hint: 'e.g. University of Ghana',
                    ),
                    const SizedBox(height: 12),
                    AdminFormField(
                      label: 'Short Name *',
                      controller: _shortName,
                      hint: 'e.g. UG, KNUST, UCC',
                    ),
                    const SizedBox(height: 12),
                    AdminFormField(
                      label: 'Town *',
                      controller: _town,
                      hint: 'e.g. Legon, Kumasi, Cape Coast',
                    ),
                    const SizedBox(height: 12),
                    AdminFormField(
                      label: 'School Code',
                      controller: _code,
                      hint: 'Auto-generated',
                      readOnly: true,
                    ),
                  ],
                ),
              ),
            ),
            dialogFooter(context, _saving, _save),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _shortName.removeListener(_genCode);
    _town.removeListener(_genCode);
    _fullName.dispose();
    _shortName.dispose();
    _town.dispose();
    _code.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VALIDATION BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUCCESS TOAST
// ─────────────────────────────────────────────────────────────────────────────

void _showSuccessToast(BuildContext context, String message) {
  final overlay = Navigator.of(context).overlay;
  if (overlay == null) return;
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (_) =>
        _SuccessToast(message: message, onDone: () => entry.remove()),
  );

  overlay.insert(entry);
}

class _SuccessToast extends StatefulWidget {
  const _SuccessToast({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;

  @override
  State<_SuccessToast> createState() => _SuccessToastState();
}

class _SuccessToastState extends State<_SuccessToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onDone();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toastPadding = _isPhone(context) ? 16.0 : 0.0;

    return Positioned(
      top: 40,
      left: toastPadding,
      right: toastPadding,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF03b352), Color(0xFF028802)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                '$label:',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextLight),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12, color: kTextDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

class _CardBtn extends StatelessWidget {
  const _CardBtn({
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      );
}

class _AddBtn extends StatelessWidget {
  const _AddBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 18, color: Colors.white),
        label: const Text('Add New', style: TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}
