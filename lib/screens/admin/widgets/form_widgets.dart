import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../constants/admin_theme.dart';
import '../../../utils/admin_helpers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TEXT FORM FIELD
// ─────────────────────────────────────────────────────────────────────────────

class AdminFormField extends StatelessWidget {
  const AdminFormField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard,
    this.readOnly = false,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final bool readOnly;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextDark,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: readOnly,
            keyboardType: keyboard,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 13, color: kTextDark),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: kTextLight, fontSize: 13),
              filled: true,
              fillColor: readOnly ? kSurfaceAlt : kSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kGreen, width: 1.5),
              ),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DROPDOWN FIELD
// ─────────────────────────────────────────────────────────────────────────────

class AdminDropdownField extends StatelessWidget {
  const AdminDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label, value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextDark,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value,
            onChanged: onChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: kSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kBorder),
              ),
            ),
            items: items
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE DROPDOWN
// ─────────────────────────────────────────────────────────────────────────────

class FirestoreDropdown extends StatelessWidget {
  const FirestoreDropdown({
    super.key,
    required this.label,
    required this.collection,
    required this.displayField,
    required this.selectedId,
    required this.onChanged,
  });
  final String label, collection, displayField;
  final String? selectedId;
  final void Function(String? id, QueryDocumentSnapshot? doc) onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextDark,
            ),
          ),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot>(
            stream: db.collection(collection).orderBy(displayField).snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              // Guard against selectedId not existing in current docs
              final validId =
                  docs.any((d) => d.id == selectedId) ? selectedId : null;
              return DropdownButtonFormField<String>(
                value: validId,
                hint: const Text(
                  'Select...',
                  style: TextStyle(color: kTextLight, fontSize: 13),
                ),
                onChanged: (id) => onChanged(
                  id,
                  id != null ? docs.firstWhere((d) => d.id == id) : null,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: kSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                ),
                items: docs.map((d) {
                  final name =
                      (d.data() as Map)[displayField]?.toString() ?? d.id;
                  return DropdownMenuItem(
                    value: d.id,
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      );
}
