import 'package:flutter/material.dart';

import '../../../constants/admin_theme.dart';
import 'shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TABLE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class TableHeader extends StatelessWidget {
  const TableHeader({
    super.key,
    required this.columns,
    required this.tableWidth, // ← finite width from LayoutBuilder
  });
  final List<String> columns;
  final double tableWidth;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: tableWidth, // ← gives Expanded a bounded parent
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: kSurfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: kBorder)),
          ),
          child: Row(
            children: columns
                .map(
                  (c) => Expanded(
                    child: Text(
                      c,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kTextLight,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLE ROW
// ─────────────────────────────────────────────────────────────────────────────

class TableDataRow extends StatelessWidget {
  const TableDataRow({
    super.key,
    required this.cells,
    required this.tableWidth, // ← finite width from LayoutBuilder
    this.statusColumnIndex,
    this.trailing,
  });
  final List<String> cells;
  final double tableWidth;
  final int? statusColumnIndex;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: tableWidth, // ← gives Expanded a bounded parent
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: kBorder, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              ...List.generate(cells.length, (i) {
                if (statusColumnIndex == i) {
                  return Expanded(child: StatusBadge(cells[i]));
                }
                return Expanded(
                  child: Text(
                    cells[i],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: kTextDark),
                  ),
                );
              }),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      );
}
