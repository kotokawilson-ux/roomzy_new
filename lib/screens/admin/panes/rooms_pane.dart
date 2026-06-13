import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../../utils/activity_logger.dart';
import '../../../../constants/admin_theme.dart';
import '../../../../utils/admin_helpers.dart';
import '../widgets/dialog_widgets.dart';
import '../widgets/form_widgets.dart';
import '../widgets/shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

bool _isPhone(BuildContext context) => MediaQuery.of(context).size.width < 600;

double _dialogWidth(BuildContext context, {double maxPx = 520}) {
  final w = MediaQuery.of(context).size.width;
  if (w < 600) return w * 0.95;
  if (w < 900) return w * 0.80;
  return maxPx.clamp(0.0, w * 0.55);
}

double _dialogMaxHeight(BuildContext context) {
  final h = MediaQuery.of(context).size.height;
  return _isPhone(context) ? h * 0.92 : h * 0.85;
}

// ─────────────────────────────────────────────────────────────────────────────
// CLOUDINARY CONFIG
// ─────────────────────────────────────────────────────────────────────────────

const _kCloudName = 'dfv9yibba';
const _kUploadPreset = 'ml_default';

/// Cross-platform Cloudinary upload — uses [XFile.readAsBytes],
/// no dart:io, works on Web + Android + iOS + Desktop.
Future<String?> _pickAndUpload({String folder = 'rooms'}) async {
  final picker = ImagePicker();
  final XFile? picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
  );
  if (picked == null) return null;

  final Uint8List bytes = await picked.readAsBytes();
  final String filename = picked.name.isNotEmpty
      ? picked.name
      : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_kCloudName/image/upload',
  );

  final req = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _kUploadPreset
    ..fields['folder'] = folder
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

  try {
    final res = await req.send();
    final body = await res.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (res.statusCode == 200) return json['secure_url'] as String?;
    debugPrint('Cloudinary error [${res.statusCode}]: $body');
    return null;
  } catch (e) {
    debugPrint('_pickAndUpload exception: $e');
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SINGLE IMAGE PICKER FIELD
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePickerField extends StatefulWidget {
  const _ImagePickerField({
    required this.label,
    required this.controller,
    this.folder = 'rooms',
  });
  final String label;
  final TextEditingController controller;
  final String folder;

  @override
  State<_ImagePickerField> createState() => _ImagePickerFieldState();
}

class _ImagePickerFieldState extends State<_ImagePickerField> {
  bool _uploading = false;

  Future<void> _pick() async {
    setState(() => _uploading = true);
    try {
      final url = await _pickAndUpload(folder: widget.folder);
      if (url != null && mounted) {
        widget.controller.text = url;
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    final previewH = _isPhone(context) ? 120.0 : 140.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: kBorder),
                borderRadius: BorderRadius.circular(10),
                color: kSurfaceAlt,
              ),
              child: Text(
                url.isEmpty ? 'No image selected' : url,
                style: TextStyle(
                    fontSize: 11, color: url.isEmpty ? kTextLight : kTextDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _pick,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.upload_rounded,
                    size: 16, color: Colors.white),
            label: Text(
              _uploading ? 'Uploading…' : 'Upload',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        if (url.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              url,
              height: previewH,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      height: previewH,
                      color: kSurfaceAlt,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
              errorBuilder: (_, __, ___) => Container(
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: Colors.red.shade400, size: 16),
                    const SizedBox(width: 6),
                    Text('Could not load image',
                        style: TextStyle(
                            color: Colors.red.shade400, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MULTIPLE IMAGES PICKER FIELD
// ─────────────────────────────────────────────────────────────────────────────

class _MultiImagePickerField extends StatefulWidget {
  const _MultiImagePickerField({
    required this.label,
    required this.controller,
    this.folder = 'rooms',
  });
  final String label;
  final TextEditingController controller;
  final String folder;

  @override
  State<_MultiImagePickerField> createState() => _MultiImagePickerFieldState();
}

class _MultiImagePickerFieldState extends State<_MultiImagePickerField> {
  bool _uploading = false;

  List<String> get _urls {
    final raw = widget.controller.text.trim();
    if (raw.isEmpty) return [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _setUrls(List<String> urls) {
    widget.controller.text = urls.join(',');
    setState(() {});
  }

  Future<void> _pickMore() async {
    setState(() => _uploading = true);
    try {
      final url = await _pickAndUpload(folder: widget.folder);
      if (url != null && mounted) {
        final current = _urls;
        current.add(url);
        _setUrls(current);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _remove(int index) {
    final current = _urls;
    current.removeAt(index);
    _setUrls(current);
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    final thumbSize = _isPhone(context) ? 90.0 : 110.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextLight)),
          ),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _pickMore,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_photo_alternate_outlined,
                    size: 16, color: Colors.white),
            label: Text(
              _uploading ? 'Uploading…' : 'Add Image',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (urls.isEmpty)
          Container(
            height: thumbSize,
            decoration: BoxDecoration(
              border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(10),
              color: kSurfaceAlt,
            ),
            child: const Center(
              child: Text('No additional images',
                  style: TextStyle(fontSize: 12, color: kTextLight)),
            ),
          )
        else
          SizedBox(
            height: thumbSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      urls[i],
                      width: thumbSize,
                      height: thumbSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.red.shade300),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _remove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOMS PANE
// ─────────────────────────────────────────────────────────────────────────────

class RoomsPane extends StatefulWidget {
  const RoomsPane({super.key});

  @override
  State<RoomsPane> createState() => _RoomsPaneState();
}

class _RoomsPaneState extends State<RoomsPane> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_isPhone(context) ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          _ResponsiveHeader(
            title: 'All Rooms',
            search: _search,
            onSearch: (v) => setState(() => _search = v),
            onAdd: _openAdd,
          ),
          const SizedBox(height: 20),

          // ── Room cards stream ────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('rooms').orderBy('hostel_name').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const CardLoading(height: 200);
              }
              if (snap.hasError) {
                return EmptyCard(message: 'Error: ${snap.error}', height: 120);
              }

              var docs = snap.data?.docs ?? [];

              // Apply search filter
              if (_search.isNotEmpty) {
                final q = _search.toLowerCase();
                docs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return [
                    'room_number',
                    'hostel_name',
                    'type',
                    'hostel_code'
                  ].any((k) =>
                      (data[k]?.toString() ?? '').toLowerCase().contains(q));
                }).toList();
              }

              if (docs.isEmpty) {
                return const EmptyCard(message: 'No rooms found', height: 160);
              }

              return _ResponsiveGrid(
                itemCount: docs.length,
                itemBuilder: (i) => _RoomCard(
                  doc: docs[i],
                  onEdit: () => _openEdit(docs[i]),
                  onDelete: () async {
                    final roomData = docs[i].data() as Map<String, dynamic>;
                    final roomNum =
                        roomData['room_number']?.toString() ?? 'Unknown';
                    final hostelName =
                        roomData['hostel_name']?.toString() ?? 'Unknown';
                    await ActivityLogger.log(
                      action: 'Deleted Room',
                      details: 'Room: $roomNum, Hostel: $hostelName',
                    );
                    confirmDelete(context, 'rooms', docs[i].id);
                  },
                  onToggle: () => _toggleAvailability(docs[i]),
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
        builder: (_) => _RoomDialog(parentContext: context),
      );

  void _openEdit(QueryDocumentSnapshot doc) => showDialog(
        context: context,
        builder: (_) => _RoomDialog(doc: doc, parentContext: context),
      );

  Future<void> _toggleAvailability(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final current = d['available'] == true || d['available'].toString() == '1';
    await db.collection('rooms').doc(doc.id).update({'available': !current});
    if (!mounted) return;
    final roomNum = d['room_number']?.toString() ?? 'Unknown';
    await ActivityLogger.log(
      action: !current ? 'Enabled Room' : 'Disabled Room',
      details: 'Room $roomNum in ${d['hostel_name'] ?? ''}',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _ResponsiveHeader extends StatelessWidget {
  const _ResponsiveHeader({
    required this.title,
    required this.search,
    required this.onSearch,
    required this.onAdd,
  });
  final String title;
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
            SectionLabel(title),
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
            SectionLabel(title),
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
        Expanded(child: SectionLabel(title)),
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
// phone (<560) → 1 col  |  tablet (<900) → 2 cols  |  desktop → 3 cols
// ─────────────────────────────────────────────────────────────────────────────

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
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
// ROOM CARD
// Mirrors the PHP rooms.php card: room number, hostel, type, capacity,
// price, availability badge, booking status badge, edit + delete actions.
// ─────────────────────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });
  final QueryDocumentSnapshot doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;

    final roomNumber = d['room_number']?.toString() ?? '—';
    final hostelName = d['hostel_name']?.toString() ?? 'N/A';
    final type = d['type']?.toString() ?? '—';
    final capacity = d['capacity']?.toString() ?? '—';
    final price =
        '₵${double.tryParse(d['price']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}';
    final imageUrl = d['image']?.toString() ?? '';

    // Match PHP logic: available == false/0 → booked/unavailable
    final available =
        d['available'] == true || d['available'].toString() == '1';

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Room image ──────────────────────────────────────────────────
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.network(
                imageUrl,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Title ─────────────────────────────────────────────────
                Row(children: [
                  const Icon(Icons.bed_rounded, color: kGreen, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Room $roomNumber',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kTextDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Divider(height: 1, color: kBorder),
                const SizedBox(height: 8),

                // ── Info rows (mirrors PHP <p> fields) ────────────────────
                _InfoRow(label: 'Hostel', value: hostelName),
                _InfoRow(label: 'Type', value: type),
                _InfoRow(label: 'Capacity', value: capacity),

// ── Slot usage bar ───────────────────────────────────────
                Builder(builder: (context) {
                  final booked = (d['booked'] ?? 0) as num;
                  final cap = (d['capacity'] ?? 1) as num;
                  final slotsLeft = (cap - booked).clamp(0, cap).toInt();
                  final progress =
                      cap > 0 ? (booked / cap).clamp(0.0, 1.0) : 0.0;
                  final isFull = booked >= cap;
                  final barColor = isFull
                      ? Colors.red
                      : progress > 0.6
                          ? Colors.orange
                          : Colors.green;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const SizedBox(
                              width: 90,
                              child: Text('Slots:',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: kTextLight)),
                            ),
                            Expanded(
                              child: Text(
                                isFull
                                    ? 'All $cap slot${cap == 1 ? '' : 's'} booked'
                                    : '$booked of $cap slot${cap == 1 ? '' : 's'} booked · $slotsLeft left',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isFull ? Colors.red : kTextDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 5),
                          Padding(
                            padding: const EdgeInsets.only(left: 90),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade200,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(barColor),
                              ),
                            ),
                          ),
                        ]),
                  );
                }),

                _InfoRow(label: 'Price', value: price),

                // ── Availability badge (mirrors PHP badge logic) ──────────
                _BadgeRow(
                  label: 'Availability',
                  badgeLabel: available ? 'Available' : 'Unavailable',
                  color: available ? Colors.green : Colors.red,
                ),

                // ── Booking status badge ──────────────────────────────────
                _BadgeRow(
                  label: 'Booking',
                  badgeLabel: !available
                      ? 'Unavailable'
                      : ((d['booked'] ?? 0) as num) >=
                              ((d['capacity'] ?? 1) as num)
                          ? 'Fully Booked'
                          : 'Has Space',
                  color: !available
                      ? Colors.red
                      : ((d['booked'] ?? 0) as num) >=
                              ((d['capacity'] ?? 1) as num)
                          ? Colors.orange
                          : Colors.blue,
                ),

                const SizedBox(height: 12),

                // ── Action buttons ────────────────────────────────────────
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    _CardBtn(
                      icon: available
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      label: available ? 'Disable' : 'Enable',
                      color: available
                          ? Colors.amber.shade700
                          : const Color(0xFF2D6A4F),
                      onTap: onToggle,
                    ),
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOM DIALOG  — Add / Edit
// Fields: Hostel (dropdown), Room Number, Room Type, Capacity, Price,
//         Available toggle, Main Image, Additional Images
// ─────────────────────────────────────────────────────────────────────────────

class _RoomDialog extends StatefulWidget {
  const _RoomDialog({this.doc, required this.parentContext});
  final QueryDocumentSnapshot? doc;
  final BuildContext parentContext;

  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<_RoomDialog> {
  final _roomNumber = TextEditingController();
  final _capacity = TextEditingController();
  final _price = TextEditingController();
  final _image = TextEditingController();
  final _images = TextEditingController();

  String? _hostelId, _hostelName, _hostelCode;
  String _type = 'Single';
  bool _available = true;
  bool _saving = false;
  String? _validationError;

  bool get _isEdit => widget.doc != null;

  static const _types = [
    'Single',
    'Single Ensuite',
    'Double',
    'Double Ensuite',
    'Triple',
    'Triple Ensuite',
    'Quad',
    'Suite',
    'Studio',
    'Dormitory'
        'Chamber and Hall',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final d = widget.doc!.data() as Map<String, dynamic>;
      _roomNumber.text = d['room_number']?.toString() ?? '';
      _capacity.text = d['capacity']?.toString() ?? '1';
      _price.text = d['price']?.toString() ?? '0';
      _image.text = d['image']?.toString() ?? '';
      _images.text = d['images']?.toString() ?? '';
      _hostelId = d['hostel_id'] as String?;
      _hostelName = d['hostel_name'] as String?;
      _hostelCode = d['hostel_code'] as String?;
      final rawType = d['type']?.toString() ?? 'Single';
      _type = _types.contains(rawType) ? rawType : 'Other';
      _available = d['available'] == true || d['available'].toString() == '1';
    } else {
      _capacity.text = '1';
      _price.text = '0';
    }
  }

  Future<void> _save() async {
    // Validation
    if (_roomNumber.text.trim().isEmpty || _hostelId == null) {
      setState(() {
        final missing = [
          if (_roomNumber.text.trim().isEmpty) 'Room Number',
          if (_hostelId == null) 'Hostel',
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
      'room_number': _roomNumber.text.trim(),
      'hostel_id': _hostelId,
      'hostel_name': _hostelName,
      'hostel_code': _hostelCode,
      'type': _type,
      'capacity': int.tryParse(_capacity.text.trim()) ?? 1,
      'price': double.tryParse(_price.text.trim()) ?? 0,
      'available': _available,
      'image': _image.text.trim(),
      'images': _images.text.trim(),
      'booked': _isEdit ? ((widget.doc!.data() as Map)['booked'] ?? 0) : 0,
      'updated_at': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEdit) {
        await db.collection('rooms').doc(widget.doc!.id).update(data);
        // ✅ ADD THIS
        await ActivityLogger.log(
          action: 'Updated Room',
          details: 'Room ${_roomNumber.text.trim()} in $_hostelName',
        );
      } else {
        data['created_at'] = FieldValue.serverTimestamp();
        await db.collection('rooms').add(data);
        // ✅ ADD THIS
        await ActivityLogger.log(
          action: 'Created Room',
          details: 'Room ${_roomNumber.text.trim()} in $_hostelName',
        );
      }
      if (!mounted) return;
      final parentCtx = widget.parentContext;
      final message =
          _isEdit ? 'Room Updated Successfully!' : 'Room Added Successfully!';
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
    final dw = _dialogWidth(context, maxPx: 520);
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
            dialogHeader(_isEdit ? 'Edit Room' : 'Add Room'),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Validation banner ──────────────────────────────────
                    if (_validationError != null)
                      _ValidationBanner(_validationError!),

                    // ── Hostel dropdown ────────────────────────────────────
                    _sectionLabel('Hostel Details'),
                    FirestoreDropdown(
                      label: 'Hostel *',
                      collection: 'hostels',
                      displayField: 'hostel_name',
                      selectedId: _hostelId,
                      onChanged: (id, doc) => setState(() {
                        _hostelId = id;
                        final m = doc?.data() as Map?;
                        _hostelName = m?['hostel_name'] as String?;
                        _hostelCode = m?['hostel_code'] as String?;
                      }),
                    ),
                    const SizedBox(height: 16),

                    // ── Room info ──────────────────────────────────────────
                    _sectionLabel('Room Information'),
                    AdminFormField(
                      label: 'Room Number *',
                      controller: _roomNumber,
                    ),
                    const SizedBox(height: 12),

                    // Room type dropdown
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Room Type',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kTextLight)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _types.contains(_type) ? _type : 'Single',
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: kBorder),
                            ),
                          ),
                          items: _types
                              .map((t) =>
                                  DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _type = v ?? 'Single'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    AdminFormField(
                      label: 'Capacity',
                      controller: _capacity,
                      keyboard: TextInputType.number,
                    ),
                    const SizedBox(height: 12),

                    AdminFormField(
                      label: 'Price (₵)',
                      controller: _price,
                      keyboard: TextInputType.number,
                    ),
                    const SizedBox(height: 12),

                    // Available toggle
                    Row(children: [
                      const Expanded(
                        child: Text('Available',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kTextDark)),
                      ),
                      Switch(
                        value: _available,
                        activeColor: kGreen,
                        onChanged: (v) => setState(() => _available = v),
                      ),
                      Text(
                        _available ? 'Yes' : 'No',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _available ? Colors.green : Colors.red,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // ── Media ──────────────────────────────────────────────
                    _sectionLabel('Room Images'),
                    _ImagePickerField(
                      label: 'Main Room Image',
                      controller: _image,
                      folder: 'rooms/main',
                    ),
                    const SizedBox(height: 16),
                    _MultiImagePickerField(
                      label: 'Additional Room Images',
                      controller: _images,
                      folder: 'rooms/gallery',
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

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: kTextLight)),
      );

  @override
  void dispose() {
    for (final c in [_roomNumber, _capacity, _price, _image, _images]) {
      c.dispose();
    }
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
            child: Text(message,
                style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
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
      if (mounted)
        _ctrl.reverse().then((_) {
          if (mounted) widget.onDone();
        });
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
                        offset: const Offset(0, 6)),
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

/// Standard label + value row (mirrors PHP <p><strong>Label:</strong> value</p>)
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
              width: 90,
              child: Text('$label:',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextLight)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 12, color: kTextDark),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

/// Label + coloured badge row (mirrors PHP badge spans)
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.label,
    required this.badgeLabel,
    required this.color,
  });
  final String label, badgeLabel;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextLight)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(badgeLabel,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ),
        ]),
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
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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
