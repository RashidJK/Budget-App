import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/category_fields.dart';
import '../../models/expense.dart';
import '../../services/format.dart';
import '../../services/storage.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/inputs.dart';
import '../manage/category_editor.dart';
import 'metadata_sheet.dart';

/// Bottom sheet for recording or editing an expense.
///
/// A sheet rather than a full page: logging a spend is a ten-second task, and
/// keeping the dashboard visible behind it makes that obvious.
class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({super.key, this.existing});

  final Expense? existing;

  static Future<void> show(BuildContext context, {Expense? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddExpenseSheet(existing: existing),
    );
  }

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  late String _categoryId;
  late String _profileId;
  late DateTime _date;
  late List<String> _attachments;

  /// One controller per category-metadata field, created lazily as categories
  /// with schemas are shown.
  final Map<String, TextEditingController> _metadata = {};

  double _parsedAmount = 0;
  bool _showNote = false;

  /// Receipts copied to permanent storage during this edit. If the user backs
  /// out, these are orphans and get cleaned up on dispose.
  final List<String> _addedThisSession = [];
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final state = context.read<AppState>();

    _title = TextEditingController(text: existing?.title ?? '');
    _amount = TextEditingController(
      text: existing == null ? '' : Money.number(existing.amount),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _categoryId =
        existing?.categoryId ??
        (state.categories.isEmpty ? 'other' : state.categories.first.id);
    _profileId = existing?.profileId ?? state.defaultProfileId;
    _date = existing?.date ?? DateTime.now();
    _parsedAmount = existing?.amount ?? 0;
    _attachments = List.of(existing?.attachments ?? const []);
    _showNote = (existing?.note ?? '').isNotEmpty;

    // Pre-fill any category metadata the expense already carries.
    (existing?.metadata ?? const {}).forEach((key, value) {
      _metadata[key] = TextEditingController(
        text: value == null ? '' : _metaString(value),
      );
    });
  }

  String _metaString(Object value) {
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return '$value';
  }

  @override
  void dispose() {
    // Abandoning the sheet must not leave receipt files behind.
    if (!_saved) {
      for (final path in _addedThisSession) {
        AttachmentStore.discard(path);
      }
    }
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    for (final controller in _metadata.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Collects the metadata fields for the current category into a map.
  Map<String, dynamic> _collectMetadata() {
    final result = <String, dynamic>{};
    for (final field in CategoryFields.forCategory(_categoryId)) {
      final controller = _metadata[field.key];
      final raw = controller?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      result[field.key] =
          field.isNumeric ? (double.tryParse(raw) ?? raw) : raw;
    }
    return result;
  }

  bool get _canSave => _parsedAmount > 0 && _title.text.trim().isNotEmpty;

  Future<void> _save() async {
    final state = context.read<AppState>();
    final existing = widget.existing;
    _saved = true;

    final metadata = _collectMetadata();
    if (existing == null) {
      await state.addExpense(
        title: _title.text.trim(),
        amount: _parsedAmount,
        categoryId: _categoryId,
        profileId: _profileId,
        date: _date,
        note: _note.text.trim(),
        attachments: _attachments,
        metadata: metadata,
      );
    } else {
      await state.updateExpense(
        existing.copyWith(
          title: _title.text.trim(),
          amount: _parsedAmount,
          categoryId: _categoryId,
          profileId: _profileId,
          date: _date,
          note: _note.text.trim(),
          attachments: _attachments,
          metadata: metadata,
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _addReceipt(ImageSource source) async {
    final picker = ImagePicker();
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Receipts are read, not reprinted — full resolution would bloat storage
      // for no gain in legibility.
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;

      final stored = await AttachmentStore.keep(picked.path);
      _addedThisSession.add(stored);
      if (mounted) setState(() => _attachments = [..._attachments, stored]);
    } on Exception {
      // A denied permission or a cancelled camera shouldn't lose the form.
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not attach that image.')),
      );
    }
  }

  void _removeReceipt(String path) {
    setState(() {
      _attachments = _attachments.where((item) => item != path).toList();
    });
    // Only delete the file if it was added in this session; an existing
    // receipt stays on disk until the expense itself is saved without it.
    if (_addedThisSession.remove(path)) {
      AttachmentStore.discard(path);
    }
  }

  Future<void> _chooseSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) await _addReceipt(source);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Padding(
      // Lifts the sheet clear of the keyboard so the save button stays
      // reachable while typing.
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Edit expense' : 'New expense',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            NumberField(
              controller: _amount,
              label: 'Amount',
              prefix: Money.symbol,
              autofocus: !isEditing,
              onChanged: (value) => setState(() => _parsedAmount = value),
            ),
            const SizedBox(height: 16),
            LabelledField(
              controller: _title,
              label: 'What was it for?',
              hint: 'Lunch at the office',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            CategoryPicker(
              selectedId: _categoryId,
              onChanged: (id) => setState(() => _categoryId = id),
              onManage: () => CategoryEditorSheet.show(context),
            ),
            const SizedBox(height: 16),
            ProfilePicker(
              selectedId: _profileId,
              onChanged: (id) => setState(() => _profileId = id),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.hairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: context.muted,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Dates.relative(_date),
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      Dates.full(_date),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Receipts(
              paths: _attachments,
              onAdd: _chooseSource,
              onRemove: _removeReceipt,
            ),
            const SizedBox(height: 8),
            // The note field stays collapsed until asked for: most expenses
            // don't need one, and an always-present box makes the form look
            // longer than it is.
            if (_showNote)
              LabelledField(
                controller: _note,
                label: 'Note',
                hint: 'Anything worth remembering',
              )
            else
              TextButton.icon(
                onPressed: () => setState(() => _showNote = true),
                icon: const Icon(Icons.notes_rounded, size: 18),
                label: const Text('Add a note'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            // Category-specific details (litres, odometer, …) — optional, and
            // only shown for categories that have a schema (spec §18).
            if (CategoryFields.has(_categoryId)) ...[
              const SizedBox(height: 20),
              Text(
                '${context.read<AppState>().categoryById(_categoryId).name} details',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: context.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              MetadataFields(categoryId: _categoryId, controllers: _metadata),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: Text(isEditing ? 'Save changes' : 'Add expense'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Receipt thumbnails with an add tile.
class _Receipts extends StatelessWidget {
  const _Receipts({
    required this.paths,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> paths;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Receipts',
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: paths.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == paths.length) {
                return _AddReceiptTile(onTap: onAdd);
              }
              return _ReceiptThumb(
                path: paths[index],
                onRemove: () => onRemove(paths[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddReceiptTile extends StatelessWidget {
  const _AddReceiptTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.hairline),
        ),
        child: Icon(Icons.add_a_photo_outlined, size: 22, color: context.muted),
      ),
    );
  }
}

class _ReceiptThumb extends StatelessWidget {
  const _ReceiptThumb({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _preview(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(path),
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              // A receipt whose file went missing shouldn't break the form.
              errorBuilder: (context, _, _) => Container(
                width: 76,
                height: 76,
                color: context.hairline,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: context.muted,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.hairline),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: context.scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(File(path)),
            ),
          ),
        ),
      ),
    );
  }
}
