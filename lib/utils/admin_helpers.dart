import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/admin_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL FIRESTORE INSTANCE
// ─────────────────────────────────────────────────────────────────────────────

final db = FirebaseFirestore.instance;

// ─────────────────────────────────────────────────────────────────────────────
// DATE FORMATTER
// ─────────────────────────────────────────────────────────────────────────────

String fmtDate(DateTime dt) {
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
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIRM DELETE DIALOG
// ─────────────────────────────────────────────────────────────────────────────

Future<void> confirmDelete(
    BuildContext context, String collection, String id) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text(
        'Confirm Delete',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: const Text('This action cannot be undone. Are you sure?'),
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
  if (confirm == true) {
    await db.collection(collection).doc(id).delete();
  }
}
