import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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

bool _isTablet(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  return w >= 600 && w < 900;
}

double _dialogWidth(BuildContext context, {double maxPx = 560}) {
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

/// Picks one image from gallery and uploads it to Cloudinary.
/// Uses [XFile.readAsBytes] — works on Web, Android, iOS, Desktop.
/// Returns the secure URL or null if cancelled / failed.
Future<String?> _pickAndUpload({String folder = 'hostels'}) async {
  final picker = ImagePicker();
  final XFile? picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
  );
  if (picked == null) return null;

  // Read file into memory — dart:io-free, works on every platform.
  final Uint8List bytes = await picked.readAsBytes();

  // On Web, picked.path is a blob URL; use picked.name for the filename.
  final String filename = picked.name.isNotEmpty
      ? picked.name
      : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_kCloudName/image/upload',
  );

  final req = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _kUploadPreset
    ..fields['folder'] = folder
    // fromBytes works on all platforms — replaces fromPath which needs dart:io.
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
    this.folder = 'hostels',
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
        Text(
          widget.label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight),
        ),
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
    this.folder = 'hostels',
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
            child: Text(
              widget.label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight),
            ),
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
// HOSTELS PANE
// ─────────────────────────────────────────────────────────────────────────────

class HostelsPane extends StatefulWidget {
  const HostelsPane({super.key});

  @override
  State<HostelsPane> createState() => _HostelsPaneState();
}

class _HostelsPaneState extends State<HostelsPane> {
  String _search = '';
  QueryDocumentSnapshot? _viewingHostel;

  @override
  Widget build(BuildContext context) {
    if (_viewingHostel != null) {
      return _RoomsView(
        hostelDoc: _viewingHostel!,
        onBack: () => setState(() => _viewingHostel = null),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(_isPhone(context) ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResponsiveHeader(
            title: 'All Hostels',
            search: _search,
            onSearch: (v) => setState(() => _search = v),
            onAdd: _openAdd,
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('hostels').orderBy('hostel_name').snapshots(),
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
                    'hostel_name',
                    'hostel_code',
                    'landlord_name',
                    'town',
                    'school_name'
                  ].any((k) =>
                      (data[k]?.toString() ?? '').toLowerCase().contains(q));
                }).toList();
              }

              if (docs.isEmpty) {
                return const EmptyCard(
                    message: 'No hostels found', height: 160);
              }

              return _ResponsiveGrid(
                itemCount: docs.length,
                itemBuilder: (i) => _HostelCard(
                  doc: docs[i],
                  onViewRooms: () => setState(() => _viewingHostel = docs[i]),
                  onEdit: () => _openEdit(docs[i]),
                  onDelete: () async {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final name = data['hostel_name'] ?? 'Unknown';
                    await ActivityLogger.log(
                      action: 'Deleted Hostel',
                      details:
                          'Hostel: $name, Town: ${data['town'] ?? 'Unknown'}',
                    );
                    confirmDelete(context, 'hostels', docs[i].id);
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
        builder: (_) => _HostelDialog(parentContext: context),
      );

  void _openEdit(QueryDocumentSnapshot doc) => showDialog(
        context: context,
        builder: (_) => _HostelDialog(doc: doc, parentContext: context),
      );
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
// HOSTEL CARD
// ─────────────────────────────────────────────────────────────────────────────

class _HostelCard extends StatelessWidget {
  const _HostelCard({
    required this.doc,
    required this.onViewRooms,
    required this.onEdit,
    required this.onDelete,
  });

  final QueryDocumentSnapshot doc;
  final VoidCallback onViewRooms;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;

    final name = d['hostel_name'] ?? '—';
    final code = (d['hostel_code']?.toString().isNotEmpty == true)
        ? d['hostel_code']
        : 'N/A';
    final landlord = (d['landlord_name']?.toString().isNotEmpty == true)
        ? d['landlord_name']
        : 'Unassigned';
    final town = d['town'] ?? '—';
    final rooms = (d['rooms_available'] ?? 0).toString();
    final priceRange = (d['price_range']?.toString().isNotEmpty == true)
        ? d['price_range']
        : '₵0.00';
    final imageUrl = d['image']?.toString() ?? '';

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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.apartment_rounded, color: kGreen, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kTextDark),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 6),
                const Divider(height: 1, color: kBorder),
                const SizedBox(height: 6),
                _InfoRow(label: 'Code', value: code),
                _InfoRow(label: 'Landlord', value: landlord),
                _InfoRow(label: 'Town', value: town),
                _InfoRow(label: 'Rooms', value: rooms),
                _InfoRow(label: 'Price', value: priceRange),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    _CardBtn(
                      icon: Icons.door_front_door_outlined,
                      label: 'Rooms',
                      color: Colors.blue,
                      onTap: onViewRooms,
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
// ROOMS VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _RoomsView extends StatefulWidget {
  const _RoomsView({required this.hostelDoc, required this.onBack});
  final QueryDocumentSnapshot hostelDoc;
  final VoidCallback onBack;

  @override
  State<_RoomsView> createState() => _RoomsViewState();
}

class _RoomsViewState extends State<_RoomsView> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final hostelData = widget.hostelDoc.data() as Map<String, dynamic>;
    final hostelName = hostelData['hostel_name'] ?? 'Hostel';
    final hostelId = widget.hostelDoc.id;

    return SingleChildScrollView(
      padding: EdgeInsets.all(_isPhone(context) ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoomsResponsiveHeader(
            hostelName: hostelName,
            onBack: widget.onBack,
            search: _search,
            onSearch: (v) => setState(() => _search = v),
            onAdd: () => _openAddRoom(widget.hostelDoc),
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('rooms')
                .where('hostel_id', isEqualTo: hostelId)
                .snapshots(),
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
                  return ['room_number', 'type'].any((k) =>
                      (data[k]?.toString() ?? '').toLowerCase().contains(q));
                }).toList();
              }

              if (docs.isEmpty) {
                return const EmptyCard(
                    message: 'No rooms found for this hostel', height: 160);
              }

              return _ResponsiveGrid(
                itemCount: docs.length,
                itemBuilder: (i) => _RoomCard(
                  doc: docs[i],
                  onEdit: () => _openEditRoom(docs[i]),
                  onDelete: () async {
                    final roomData = docs[i].data() as Map<String, dynamic>;
                    final roomNum = roomData['room_number'] ?? 'Unknown';
                    await ActivityLogger.log(
                      action: 'Deleted Room',
                      details: 'Room: $roomNum, Hostel: $hostelName',
                    );
                    confirmDelete(context, 'rooms', docs[i].id);
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

  void _openAddRoom(QueryDocumentSnapshot hostelDoc) => showDialog(
        context: context,
        builder: (_) =>
            _RoomDialog(hostelDoc: hostelDoc, parentContext: context),
      );

  void _openEditRoom(QueryDocumentSnapshot doc) => showDialog(
        context: context,
        builder: (_) => _RoomDialog(
            doc: doc, hostelDoc: widget.hostelDoc, parentContext: context),
      );
}

class _RoomsResponsiveHeader extends StatelessWidget {
  const _RoomsResponsiveHeader({
    required this.hostelName,
    required this.onBack,
    required this.search,
    required this.onSearch,
    required this.onAdd,
  });
  final String hostelName;
  final VoidCallback onBack;
  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final header = _RoomsHeader(hostelName: hostelName, onBack: onBack);

      if (w < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
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
        Expanded(child: header),
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

class _RoomsHeader extends StatelessWidget {
  const _RoomsHeader({required this.hostelName, required this.onBack});
  final String hostelName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: 'Back to Hostels',
            style: IconButton.styleFrom(
              backgroundColor: kSurfaceAlt,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Rooms in $hostelName',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: kTextDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOM CARD
// ─────────────────────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  const _RoomCard({
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

    final roomNumber = d['room_number'] ?? '—';
    final hostelName = d['hostel_name'] ?? '—';
    final type = d['type'] ?? '—';
    final capacity = (d['capacity'] ?? 0).toString();
    final price =
        '₵${double.tryParse(d['price']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}';
    final available =
        d['available'] == true || d['available'].toString() == '1';
    final imageUrl = d['image']?.toString() ?? '';

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
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.network(
                imageUrl,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.bed_rounded, color: kGreen, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Room $roomNumber',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kTextDark),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 6),
                const Divider(height: 1, color: kBorder),
                const SizedBox(height: 6),
                _InfoRow(label: 'Hostel', value: hostelName),
                _InfoRow(label: 'Type', value: type),
                _InfoRow(label: 'Capacity', value: capacity),
                _SlotBar(d: d), // ← add this
                _InfoRow(label: 'Price', value: price),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const SizedBox(
                      width: 90,
                      child: Text('Availability:',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kTextLight)),
                    ),
                    _Badge(
                      label: available ? 'Available' : 'Unavailable',
                      color: available ? Colors.green : Colors.red,
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const SizedBox(
                      width: 90,
                      child: Text('Booking:',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kTextLight)),
                    ),
                    _Badge(
                      label: available ? 'Not Booked' : 'Booked',
                      color: available ? Colors.blue : Colors.orange,
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    _CardBtn(
                      icon: Icons.edit_outlined,
                      label: 'Edit Room',
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

class _SlotBar extends StatelessWidget {
  const _SlotBar({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final booked = (d['booked'] ?? 0) as num;
    final cap = (d['capacity'] ?? 1) as num;
    final slotsLeft = (cap - booked).clamp(0, cap).toInt();
    final progress = cap > 0 ? (booked / cap).clamp(0.0, 1.0) : 0.0;
    final isFull = booked >= cap;
    final barColor = isFull
        ? Colors.red
        : progress > 0.6
            ? Colors.orange
            : Colors.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(
              width: 72,
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
            padding: const EdgeInsets.only(left: 72),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// HOSTEL DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _HostelDialog extends StatefulWidget {
  const _HostelDialog({this.doc, required this.parentContext});
  final QueryDocumentSnapshot? doc;
  final BuildContext parentContext;

  @override
  State<_HostelDialog> createState() => _HostelDialogState();
}

class _HostelDialogState extends State<_HostelDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _address = TextEditingController();
  final _town = TextEditingController();
  final _phone = TextEditingController();
  final _desc = TextEditingController();
  final _momo = TextEditingController();
  final _cash = TextEditingController();
  final _bank = TextEditingController();
  final _other = TextEditingController();
  final _image = TextEditingController();
  final _images = TextEditingController();
  final _googleMap = TextEditingController();
  final _priceRange = TextEditingController();
  final _roomsAvail = TextEditingController();

  String? _landlordId, _landlordName, _landlordCode;
  String? _schoolId, _schoolName, _schoolShortName;
  String _durationType = 'per year';
  String _depositType = 'none';
  final _depositValue = TextEditingController();

  bool _saving = false;
  String? _validationError;

  bool get _isEdit => widget.doc != null;

  static const _durationOptions = [
    'per year',
    'per semester',
    'per month',
    'per Academic year',
  ];

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final d = widget.doc!.data() as Map<String, dynamic>;
      _name.text = d['hostel_name'] ?? '';
      _code.text = d['hostel_code'] ?? '';
      _address.text = d['address'] ?? '';
      _town.text = d['town'] ?? '';
      _phone.text = d['phone'] ?? '';
      _desc.text = d['description'] ?? '';
      _momo.text = d['payment_momo'] ?? '';
      _cash.text = d['payment_cash'] ?? '';
      _bank.text = d['payment_bank'] ?? '';
      _other.text = d['payment_other'] ?? '';
      _image.text = d['image'] ?? '';
      _images.text = d['images'] ?? '';
      _googleMap.text = d['google_map'] ?? '';
      _priceRange.text = d['price_range'] ?? '';
      _roomsAvail.text = (d['rooms_available'] ?? 0).toString();
      _landlordId = d['landlord_id'] as String?;
      _landlordName = d['landlord_name'] as String?;
      _landlordCode = d['landlord_code'] as String?;
      _schoolId = d['school_id'] as String?;
      _schoolName = d['school_name'] as String?;
      _schoolShortName = d['short_name'] as String?;
      _durationType = d['duration_type'] ?? 'per year';
      _depositType = d['deposit_type']?.toString() ?? 'none';
      final dv = (d['deposit_value'] as num?)?.toDouble() ?? 0.0;
      _depositValue.text =
          dv > 0 ? dv.toStringAsFixed(_depositType == 'percent' ? 0 : 2) : '';
    } else {
      _roomsAvail.text = '0';
    }
    _name.addListener(_genCode);
    _depositValue.addListener(() => setState(() {}));
  }

  void _genCode() {
    if (_isEdit) return;
    final n = _name.text.trim().replaceAll(' ', '').toUpperCase();
    if (n.isNotEmpty) _code.text = n.length > 6 ? n.substring(0, 6) : n;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _landlordId == null || _schoolId == null) {
      setState(() {
        final missing = [
          if (_name.text.trim().isEmpty) 'Hostel Name',
          if (_landlordId == null) 'Landlord',
          if (_schoolId == null) 'School',
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
      'hostel_name': _name.text.trim(),
      'hostel_code': _code.text.trim(),
      'address': _address.text.trim(),
      'town': _town.text.trim(),
      'phone': _phone.text.trim(),
      'description': _desc.text.trim(),
      'duration_type': _durationType,
      'payment_momo': _momo.text.trim(),
      'payment_cash': _cash.text.trim(),
      'payment_bank': _bank.text.trim(),
      'payment_other': _other.text.trim(),
      'image': _image.text.trim(),
      'images': _images.text.trim(),
      'google_map': _googleMap.text.trim(),
      'price_range': _priceRange.text.trim(),
      'rooms_available': int.tryParse(_roomsAvail.text.trim()) ?? 0,
      'landlord_id': _landlordId,
      'landlord_name': _landlordName,
      'landlord_code': _landlordCode,
      'school_id': _schoolId,
      'school_name': _schoolName,
      'short_name': _schoolShortName,
      'updated_at': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEdit) {
        // Inside _save() — WRONG
        _depositValue.addListener(() => setState(() {}));
        // ✅ LOG HOSTEL UPDATE
        await ActivityLogger.log(
          action: 'Updated Hostel',
          details: 'Hostel: ${_name.text.trim()}, Town: ${_town.text.trim()}',
        );
      } else {
        data['created_at'] = FieldValue.serverTimestamp();
        await db.collection('hostels').add(data);
        // ✅ LOG HOSTEL CREATE
        await ActivityLogger.log(
          action: 'Created Hostel',
          details: 'Hostel: ${_name.text.trim()}, Landlord: $_landlordName',
        );
      }
      if (!mounted) return;
      final parentCtx = widget.parentContext;
      final message = _isEdit
          ? 'Hostel Updated Successfully!'
          : 'Hostel Added Successfully!';
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
    final dw = _dialogWidth(context, maxPx: 560);
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
            dialogHeader(_isEdit ? 'Edit Hostel' : 'Add Hostel'),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_isPhone(context) ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_validationError != null)
                      _ValidationBanner(_validationError!),
                    _section('Basic Information'),
                    AdminFormField(label: 'Hostel Name *', controller: _name),
                    const SizedBox(height: 12),
                    AdminFormField(
                        label: 'Hostel Code',
                        controller: _code,
                        readOnly: true),
                    const SizedBox(height: 12),
                    AdminFormField(label: 'Town *', controller: _town),
                    const SizedBox(height: 12),
                    AdminFormField(label: 'Address', controller: _address),
                    const SizedBox(height: 12),
                    AdminFormField(
                        label: 'Phone',
                        controller: _phone,
                        keyboard: TextInputType.phone),
                    const SizedBox(height: 12),
                    AdminFormField(
                        label: 'Description', controller: _desc, maxLines: 3),
                    const SizedBox(height: 16),
                    _section('Associations'),
                    FirestoreDropdown(
                      label: 'Landlord *',
                      collection: 'landlords',
                      displayField: 'full_name',
                      selectedId: _landlordId,
                      onChanged: (id, doc) => setState(() {
                        _landlordId = id;
                        final m = doc?.data() as Map?;
                        _landlordName = m?['full_name'] as String?;
                        _landlordCode = m?['landlord_code'] as String?;
                      }),
                    ),
                    const SizedBox(height: 12),
                    FirestoreDropdown(
                      label: 'School *',
                      collection: 'schools',
                      displayField: 'full_name',
                      selectedId: _schoolId,
                      onChanged: (id, doc) => setState(() {
                        _schoolId = id;
                        final m = doc?.data() as Map?;
                        _schoolName = m?['full_name'] as String?;
                        _schoolShortName = m?['short_name'] as String?;
                      }),
                    ),
                    const SizedBox(height: 16),
                    _section('Pricing & Availability'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Duration Type',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kTextLight)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _durationOptions.contains(_durationType)
                                ? _durationType
                                : 'per year',
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
                            items: _durationOptions
                                .map((o) =>
                                    DropdownMenuItem(value: o, child: Text(o)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _durationType = v ?? 'per year'),
                          ),
                        ],
                      ),
                    ),
                    AdminFormField(
                        label: 'Price Range (e.g. ₵800 - ₵1200)',
                        controller: _priceRange),
                    const SizedBox(height: 12),
                    AdminFormField(
                        label: 'Rooms Available',
                        controller: _roomsAvail,
                        keyboard: TextInputType.number),
                    const SizedBox(height: 16),
                    _section('Deposit Policy'),
                    Row(children: [
                      _DepositChip(
                        label: 'None',
                        icon: Icons.block_rounded,
                        selected: _depositType == 'none',
                        onTap: () => setState(() {
                          _depositType = 'none';
                          _depositValue.clear();
                        }),
                      ),
                      const SizedBox(width: 8),
                      _DepositChip(
                        label: 'Percentage',
                        icon: Icons.percent_rounded,
                        selected: _depositType == 'percent',
                        onTap: () => setState(() => _depositType = 'percent'),
                      ),
                      const SizedBox(width: 8),
                      _DepositChip(
                        label: 'Fixed (GHS)',
                        icon: Icons.attach_money_rounded,
                        selected: _depositType == 'fixed',
                        onTap: () => setState(() => _depositType = 'fixed'),
                      ),
                    ]),
                    if (_depositType != 'none') ...[
                      const SizedBox(height: 12),
                      AdminFormField(
                        label: _depositType == 'percent'
                            ? 'Deposit Percentage (%)'
                            : 'Deposit Amount (GHS per slot)',
                        controller: _depositValue,
                        keyboard: TextInputType.number,
                      ),
                      const SizedBox(height: 6),
                      _DepositPreviewNote(
                        type: _depositType,
                        rawValue: _depositValue.text,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _section('Payment Details'),
                    AdminFormField(
                        label: 'Mobile Money (MoMo)', controller: _momo),
                    const SizedBox(height: 12),
                    AdminFormField(label: 'Bank Payment', controller: _bank),
                    const SizedBox(height: 12),
                    AdminFormField(label: 'Cash Payment', controller: _cash),
                    const SizedBox(height: 12),
                    AdminFormField(label: 'Other Payment', controller: _other),
                    const SizedBox(height: 16),
                    _section('Media & Location'),
                    _ImagePickerField(
                      label: 'Main Image',
                      controller: _image,
                      folder: 'hostels/main',
                    ),
                    const SizedBox(height: 16),
                    _MultiImagePickerField(
                      label: 'Additional Images',
                      controller: _images,
                      folder: 'hostels/gallery',
                    ),
                    const SizedBox(height: 12),
                    AdminFormField(
                        label: 'Google Maps Link', controller: _googleMap),
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

  Widget _section(String label) => Padding(
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
    _name.removeListener(_genCode);
    _depositValue.dispose();
    for (final c in [
      _name,
      _code,
      _address,
      _town,
      _phone,
      _desc,
      _momo,
      _cash,
      _bank,
      _other,
      _image,
      _images,
      _googleMap,
      _priceRange,
      _roomsAvail,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOM DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _RoomDialog extends StatefulWidget {
  const _RoomDialog(
      {this.doc, required this.hostelDoc, required this.parentContext});
  final QueryDocumentSnapshot? doc;
  final QueryDocumentSnapshot hostelDoc;
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
    'Studio',
    'Suite',
    'Dormitory',
    'Chamber and Hall',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final d = widget.doc!.data() as Map<String, dynamic>;
      _roomNumber.text = d['room_number'] ?? '';
      _capacity.text = (d['capacity'] ?? 1).toString();
      _price.text = (d['price'] ?? 0).toString();
      _image.text = d['image'] ?? '';
      _images.text = d['images'] ?? '';
      _type = d['type'] ?? 'Single';
      _available = d['available'] == true || d['available'].toString() == '1';
    } else {
      _capacity.text = '1';
      _price.text = '0';
    }
  }

  Future<void> _save() async {
    if (_roomNumber.text.trim().isEmpty) {
      setState(() => _validationError = 'Room Number is required.');
      return;
    }

    setState(() {
      _saving = true;
      _validationError = null;
    });

    final hostelData = widget.hostelDoc.data() as Map<String, dynamic>;
    final hostelName = hostelData['hostel_name'] ?? '';

    final data = <String, dynamic>{
      'room_number': _roomNumber.text.trim(),
      'type': _type,
      'capacity': int.tryParse(_capacity.text.trim()) ?? 1,
      'price': double.tryParse(_price.text.trim()) ?? 0,
      'available': _available,
      'image': _image.text.trim(),
      'images': _images.text.trim(),
      'hostel_id': widget.hostelDoc.id,
      'hostel_name': hostelData['hostel_name'] ?? '',
      'hostel_code': hostelData['hostel_code'] ?? '',
      'booked': _isEdit ? ((widget.doc!.data() as Map)['booked'] ?? 0) : 0,
      'updated_at': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEdit) {
        await db.collection('rooms').doc(widget.doc!.id).update(data);
        // ✅ LOG ROOM UPDATE
        await ActivityLogger.log(
          action: 'Updated Room',
          details: 'Room ${_roomNumber.text.trim()} in $hostelName',
        );
      } else {
        data['created_at'] = FieldValue.serverTimestamp();
        await db.collection('rooms').add(data);
        // ✅ LOG ROOM CREATE
        await ActivityLogger.log(
          action: 'Created Room',
          details: 'Room ${_roomNumber.text.trim()} in $hostelName',
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
    final dw = _dialogWidth(context, maxPx: 480);
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
                    if (_validationError != null)
                      _ValidationBanner(_validationError!),
                    AdminFormField(
                        label: 'Room Number *', controller: _roomNumber),
                    const SizedBox(height: 12),
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
                        keyboard: TextInputType.number),
                    const SizedBox(height: 12),
                    AdminFormField(
                        label: 'Price (₵)',
                        controller: _price,
                        keyboard: TextInputType.number),
                    const SizedBox(height: 12),
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
                    ]),
                    const SizedBox(height: 16),
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
// ─────────────────────────────────────────────────────────────────────────────
// DEPOSIT CHIP  (admin)
// ─────────────────────────────────────────────────────────────────────────────

class _DepositChip extends StatelessWidget {
  const _DepositChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? kGreen : kSurfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: selected ? kGreen : kBorder, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16, color: selected ? Colors.white : kTextLight),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : kTextLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DEPOSIT PREVIEW NOTE
// ─────────────────────────────────────────────────────────────────────────────

class _DepositPreviewNote extends StatelessWidget {
  const _DepositPreviewNote({required this.type, required this.rawValue});
  final String type;
  final String rawValue;

  @override
  Widget build(BuildContext context) {
    final val = double.tryParse(rawValue.trim()) ?? 0.0;
    if (val <= 0) return const SizedBox.shrink();

    final String preview;
    if (type == 'percent') {
      final dep = 1000.0 * val / 100;
      preview =
          'e.g. ${val.toStringAsFixed(0)}% of GHS 1000 room = GHS ${dep.toStringAsFixed(2)} deposit';
    } else {
      preview = 'Student pays GHS ${val.toStringAsFixed(2)} deposit per slot';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kGreen.withOpacity(0.20)),
      ),
      child: Row(children: [
        Icon(Icons.calculate_outlined, size: 13, color: kGreen),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            preview,
            style: TextStyle(
                fontSize: 11, color: kGreen, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
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

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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
