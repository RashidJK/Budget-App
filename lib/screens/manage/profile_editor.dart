import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/palette.dart';
import '../../models/profile.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/pickers.dart';

/// Create or edit a profile.
class ProfileEditorSheet extends StatefulWidget {
  const ProfileEditorSheet({super.key, this.existing});

  final Profile? existing;

  static Future<void> show(BuildContext context, {Profile? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProfileEditorSheet(existing: existing),
    );
  }

  @override
  State<ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<ProfileEditorSheet> {
  late final TextEditingController _name;
  late String _iconName;
  late int? _colorSlot;
  late bool _isBusiness;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _name = TextEditingController(text: existing?.name ?? '');
    _iconName = existing?.iconName ?? 'briefcase';
    _isBusiness = existing?.isBusiness ?? false;
    _colorSlot =
        existing?.colorSlot ??
        Palette.firstFree(
          context.read<AppState>().profiles.map((p) => p.colorSlot),
        );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final existing = widget.existing;
    if (existing == null) {
      await state.addProfile(
        name: name,
        iconName: _iconName,
        colorSlot: _colorSlot,
        isBusiness: _isBusiness,
      );
    } else {
      await state.updateProfile(
        existing.copyWith(
          name: name,
          iconName: _iconName,
          colorSlot: _colorSlot,
          isBusiness: _isBusiness,
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Palette.color(_colorSlot, theme.brightness);

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
            Text(
              widget.existing == null ? 'New profile' : 'Edit profile',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Coffee Shop'),
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
                onChanged: (slot) => setState(() => _colorSlot = slot),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              value: _isBusiness,
              onChanged: (value) => setState(() => _isBusiness = value),
              contentPadding: EdgeInsets.zero,
              title: const Text('This is a business'),
              subtitle: Text(
                'Business profiles are framed as operating costs rather than '
                'personal spending.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.muted,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: Text(
                widget.existing == null ? 'Add profile' : 'Save changes',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
