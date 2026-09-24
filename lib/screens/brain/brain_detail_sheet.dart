import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/brain_item.dart';
import '../../state/brain_state.dart';
import '../../theme.dart';
import 'brain_command_bar.dart' show brainKindColor, brainKindIcon;

/// Opens the detail / edit sheet for one captured item.
Future<void> showBrainDetail(BuildContext context, BrainItem item) {
  final brain = context.read<BrainState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<BrainState>.value(
      value: brain,
      child: _DetailSheet(item: item),
    ),
  );
}

/// Groom a single item: edit its text, switch kind, set or clear a due date,
/// open/copy a link, pin, or delete. Anything the capture bar can't do.
class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.item});

  final BrainItem item;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.item.text);
  late final TextEditingController _url =
      TextEditingController(text: widget.item.url ?? '');

  late BrainKind _kind = widget.item.kind;
  late DateTime? _due = widget.item.dueDate;
  late bool _pinned = widget.item.pinned;

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    // copyWith can't clear a field (its `??` keeps the old value), so build a
    // fresh item directly — the only way to null out a due date or URL.
    final updated = BrainItem(
      id: widget.item.id,
      kind: _kind,
      text: _text.text.trim(),
      createdAt: widget.item.createdAt,
      updatedAt: DateTime.now(),
      done: widget.item.done,
      dueDate: _kind == BrainKind.task ? _due : null,
      url: _kind == BrainKind.link
          ? (_url.text.trim().isEmpty ? null : _url.text.trim())
          : null,
      pinned: _pinned,
      tags: widget.item.tags,
    );
    await context.read<BrainState>().update(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await context.read<BrainState>().remove(widget.item.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final color = brainKindColor(_kind);
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1B1A24) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: context.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final k in BrainKind.values) ...[
                  _KindPill(
                    kind: k,
                    active: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  ),
                  if (k != BrainKind.values.last) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Edit…',
                filled: true,
                fillColor: dark ? const Color(0xFF232232) : const Color(0xFFF3F2FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_kind == BrainKind.link) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'https://…',
                  prefixIcon: const Icon(Icons.link_rounded, size: 18),
                  filled: true,
                  fillColor: dark ? const Color(0xFF232232) : const Color(0xFFF3F2FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _url.text.trim()));
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy link'),
                  style: TextButton.styleFrom(foregroundColor: color),
                ),
              ),
            ],
            if (_kind == BrainKind.task) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.event_rounded, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(
                    _due == null ? 'No due date' : _fullDate(_due!),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (_due != null)
                    IconButton(
                      onPressed: () => setState(() => _due = null),
                      icon: Icon(Icons.close_rounded, size: 18, color: context.muted),
                    ),
                  TextButton(
                    onPressed: _pickDue,
                    style: TextButton.styleFrom(foregroundColor: color),
                    child: Text(_due == null ? 'Set date' : 'Change'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _ActionChip(
                  icon: _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  label: _pinned ? 'Pinned' : 'Pin',
                  color: _pinned ? color : context.muted,
                  onTap: () => setState(() => _pinned = !_pinned),
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: context.warn,
                  onTap: _delete,
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.kind, required this.active, required this.onTap});

  final BrainKind kind;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = brainKindColor(kind);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.6) : context.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(brainKindIcon(kind), size: 14, color: active ? color : context.muted),
            const SizedBox(width: 5),
            Text(
              kind.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? color : context.scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fullDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
