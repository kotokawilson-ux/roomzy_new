import 'package:flutter/material.dart';

import '../../../constants/admin_theme.dart';
import 'form_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG HEADER
// ─────────────────────────────────────────────────────────────────────────────

Widget dialogHeader(String title) => Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: kGreen,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG FOOTER
// ─────────────────────────────────────────────────────────────────────────────

Widget dialogFooter(
  BuildContext context,
  bool saving,
  VoidCallback onSave,
) =>
    Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: saving ? null : onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(color: Colors.white),
                  ),
          ),
        ],
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// FORM DIALOG — reusable shell for simple add/edit dialogs
// ─────────────────────────────────────────────────────────────────────────────

class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.saving,
    required this.onSave,
    required this.fields,
    this.extraWidgets,
  });
  final String title;
  final bool saving;
  final VoidCallback onSave;
  final List<AdminFormField> fields;
  final List<Widget>? extraWidgets;

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            children: [
              dialogHeader(title),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      for (int i = 0; i < fields.length; i++) ...[
                        fields[i],
                        if (i < fields.length - 1) const SizedBox(height: 12),
                      ],
                      ...?extraWidgets,
                    ],
                  ),
                ),
              ),
              dialogFooter(context, saving, onSave),
            ],
          ),
        ),
      );
}
