import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/category_fields.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// Editor for a category's optional metadata — the "enrich later" half of
/// capture-first (spec §18, §19).
///
/// Opened after a capture ("Add fuel details?") or from the expense editor.
/// Everything here is optional; the expense is already saved, so closing
/// without filling anything in loses nothing.
class MetadataSheet extends StatefulWidget {
  const MetadataSheet({super.key, required this.expenseId});

  final String expenseId;

  static Future<void> show(BuildContext context, String expenseId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MetadataSheet(expenseId: expenseId),
    );
  }

  @override
  State<MetadataSheet> createState() => _MetadataSheetState();
}

class _MetadataSheetState extends State<MetadataSheet> {
  late final Map<String, TextEditingController> _controllers;
  late final List<CategoryField> _fields;
  late final ExpenseCategory _category;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final expense = state.expenseById(widget.expenseId);
    _category = state.categoryById(expense?.categoryId);
    _fields = CategoryFields.forCategory(expense?.categoryId);

    _controllers = {
      for (final field in _fields)
        field.key: TextEditingController(
          text: _stringValue(expense?.metadata[field.key]),
        ),
    };
  }

  String _stringValue(Object? value) {
    if (value == null) return '';
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return '$value';
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final expense = state.expenseById(widget.expenseId);
    if (expense == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final metadata = <String, dynamic>{...expense.metadata};
    for (final field in _fields) {
      final raw = _controllers[field.key]!.text.trim();
      if (raw.isEmpty) {
        metadata.remove(field.key);
      } else if (field.isNumeric) {
        metadata[field.key] = double.tryParse(raw) ?? raw;
      } else {
        metadata[field.key] = raw;
      }
    }

    await state.updateExpense(
      expense.copyWith(metadata: metadata, updatedAt: DateTime.now()),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _category.of(context);

    return Padding(
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
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: context.isDark ? 0.26 : 0.13,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_category.icon, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
                Text('${_category.name} details',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'All optional — fill in what you know.',
              style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
            ),
            const SizedBox(height: 18),
            for (final field in _fields) ...[
              _FieldInput(
                field: field,
                controller: _controllers[field.key]!,
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 6),
            FilledButton(onPressed: _save, child: const Text('Save details')),
          ],
        ),
      ),
    );
  }
}

/// A metadata section embeddable in the expense editor, editing directly into
/// [metadata]. Shown only for categories that have a schema.
class MetadataFields extends StatelessWidget {
  const MetadataFields({
    super.key,
    required this.categoryId,
    required this.controllers,
  });

  final String categoryId;

  /// One controller per field key; the caller owns their lifecycle.
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final fields = CategoryFields.forCategory(categoryId);
    if (fields.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in fields) ...[
          _FieldInput(
            field: field,
            controller: controllers.putIfAbsent(
              field.key,
              TextEditingController.new,
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({required this.field, required this.controller});

  final CategoryField field;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: field.isNumeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: field.isNumeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
              : null,
          textCapitalization: field.isNumeric
              ? TextCapitalization.none
              : TextCapitalization.words,
          decoration: InputDecoration(
            hintText: field.hint,
            isDense: true,
            suffixText: field.unit,
          ),
        ),
      ],
    );
  }
}
