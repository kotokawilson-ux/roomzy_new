import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../constants/admin_theme.dart';
import 'shared_widgets.dart';
import 'table_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GENERIC CRUD PANE
// ─────────────────────────────────────────────────────────────────────────────

class CrudPane extends StatelessWidget {
  const CrudPane({
    super.key,
    required this.title,
    required this.search,
    required this.onSearchChanged,
    required this.stream,
    required this.columns,
    required this.rowBuilder,
    required this.filterFn,
    this.onAdd,
    this.actionBuilder,
    this.statusColumnIndex,
  });

  final String title, search;
  final ValueChanged<String> onSearchChanged;
  final Stream<QuerySnapshot> stream;
  final List<String> columns;
  final List<String> Function(QueryDocumentSnapshot) rowBuilder;
  final bool Function(QueryDocumentSnapshot, String) filterFn;
  final VoidCallback? onAdd;
  final Widget Function(QueryDocumentSnapshot)? actionBuilder;
  final int? statusColumnIndex;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 480;

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel(title),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SearchBox(
                              value: search,
                              onChanged: onSearchChanged,
                            ),
                          ),
                          if (onAdd != null) ...[
                            const SizedBox(width: 8),
                            _AddButton(onAdd: onAdd),
                          ],
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: SectionLabel(title)),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 120,
                        maxWidth: 220,
                      ),
                      child: SearchBox(
                        value: search,
                        onChanged: onSearchChanged,
                      ),
                    ),
                    if (onAdd != null) ...[
                      const SizedBox(width: 12),
                      _AddButton(onAdd: onAdd),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // ── Table container ───────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: StreamBuilder<QuerySnapshot>(
                stream: stream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const CardLoading(height: 200);
                  }
                  if (snap.hasError) {
                    return EmptyCard(
                      message: 'Error: ${snap.error}',
                      height: 120,
                    );
                  }

                  var docs = snap.data?.docs ?? [];

                  if (search.isNotEmpty) {
                    docs = docs
                        .where((d) => filterFn(d, search.toLowerCase()))
                        .toList();
                  }

                  if (docs.isEmpty) {
                    return EmptyCard(
                      message: 'No ${title.toLowerCase()} found',
                      height: 120,
                    );
                  }

                  // LayoutBuilder gives TableHeader/TableDataRow a finite
                  // width so their internal Expanded widgets work correctly.
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final tableWidth = constraints.maxWidth;
                      return Column(
                        children: [
                          TableHeader(
                            columns: columns,
                            tableWidth: tableWidth,
                          ),
                          ...docs.map((doc) {
                            final cells = rowBuilder(doc);
                            return TableDataRow(
                              cells: cells.sublist(0, cells.length - 1),
                              statusColumnIndex: statusColumnIndex,
                              tableWidth: tableWidth,
                              trailing: actionBuilder != null
                                  ? actionBuilder!(doc)
                                  : null,
                            );
                          }),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      );
}

class _AddButton extends StatelessWidget {
  const _AddButton({this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add, size: 18, color: Colors.white),
        label: const Text('Add New', style: TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
}
