import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/icons.dart';
import '../../models/palette.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/inputs.dart';
import '../../widgets/pickers.dart';

/// Create or edit a single category.
class CategoryEditorSheet extends StatefulWidget {
  const CategoryEditorSheet({super.key, this.existing});

  final ExpenseCategory? existing;

  static Future<void> show(BuildContext context, {ExpenseCategory? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CategoryEditorSheet(existing: existing),
    );
  }

  @override
  State<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<CategoryEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _budget;
  late String _iconName;
  late int? _colorSlot;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _name = TextEditingController(text: existing?.name ?? '');
    _budget = TextEditingController(
      text: existing?.hasBudget ?? false
          ? Money.number(existing!.monthlyBudget!)
          : '',
    );
    _iconName = existing?.iconName ?? IconChoice.all.first.name;
    _colorSlot = existing?.colorSlot;

    if (existing == null) {
      // A new category takes the next free hue, so the common case needs no
      // colour decision at all.
      final state = context.read<AppState>();
      _colorSlot = Palette.firstFree(state.usedColorSlots);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final name = _name.text.trim();
    if (name.isEmpty) return;

    // A blank or zero budget means "no budget", not a limit of zero.
    final parsedBudget = double.tryParse(_budget.text) ?? 0;
    final budget = parsedBudget > 0 ? parsedBudget : null;

    final existing = widget.existing;
    if (existing == null) {
      await state.addCategory(
        name: name,
        iconName: _iconName,
        colorSlot: _colorSlot,
        monthlyBudget: budget,
      );
    } else {
      await state.updateCategory(
        existing.copyWith(
          name: name,
          iconName: _iconName,
          colorSlot: _colorSlot,
          clearColorSlot: _colorSlot == null,
          monthlyBudget: budget,
          clearBudget: budget == null,
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final accent = Palette.color(_colorSlot, theme.brightness);

    // The slot this category already owns isn't "taken" from its own point of
    // view, so it isn't marked in the picker.
    final used = state.usedColorSlots
      ..removeWhere((slot) => slot == widget.existing?.colorSlot);

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
                  child: Icon(
                    IconChoice.resolve(_iconName),
                    size: 20,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.existing == null ? 'New category' : 'Edit category',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Business Advertising',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            FieldLabel(
              label: 'Icon',
              child: IconPicker(
                selected: _iconName,
                accent: accent,
                onChanged: (name) => setState(() => _iconName = name),
              ),
            ),
            const SizedBox(height: 20),
            FieldLabel(
              label: 'Colour',
              child: ColorSlotPicker(
                selected: _colorSlot,
                used: used,
                onChanged: (slot) => setState(() => _colorSlot = slot),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _colorSlot == null
                  ? 'Neutral categories still appear in charts, labelled by '
                        'name. Only eight distinct colours read reliably, so '
                        'extra categories share the neutral tone.'
                  : 'This colour stays with the category, so charts never '
                        'repaint when spending changes.',
              style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
            ),
            const SizedBox(height: 20),
            NumberField(
              controller: _budget,
              label: 'Monthly budget (optional)',
              prefix: Money.symbol,
              hint: 'No limit',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Text(
              'Set a limit and this category shows up as a goal on the home '
              'screen, with a bar that fills as you spend.',
              style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: Text(
                widget.existing == null ? 'Add category' : 'Save changes',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
