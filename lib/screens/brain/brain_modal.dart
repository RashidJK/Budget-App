import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/brain_item.dart';
import '../../state/brain_state.dart';
import '../../theme.dart';
import 'brain_command_bar.dart' show brainKindColor, brainKindIcon;
import 'brain_detail_sheet.dart' show showBrainDetail;

/// Opens an item full-screen, expanding in from its card. A reading view: date,
/// title, meta chips and actions up top, the content below.
Future<void> showBrainModal(BuildContext context, BrainItem item) {
  final brain = context.read<BrainState>();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondary) =>
          ChangeNotifierProvider<BrainState>.value(
            value: brain,
            child: _BrainModal(id: item.id),
          ),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class _BrainModal extends StatelessWidget {
  const _BrainModal({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final brain = context.watch<BrainState>();
    final item = brain.byId(id);
    if (item == null) {
      // The item was deleted while open — dismiss.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final color = brainKindColor(item.kind);
    final isLink =
        item.kind == BrainKind.link && (item.url?.isNotEmpty ?? false);
    final title = _title(item, isLink);
    final words = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final body = _body(context, item, isLink, color);

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF14131C) : Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _action(
                    context,
                    item.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    item.pinned ? color : context.muted,
                    () => brain.togglePinned(item.id),
                  ),
                  _action(context, Icons.edit_outlined, context.muted, () {
                    showBrainDetail(context, item);
                  }),
                  _action(context, Icons.ios_share_rounded, context.muted, () {
                    final text = isLink ? (item.url ?? item.text) : item.text;
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Copied')));
                  }),
                  _action(
                    context,
                    Icons.delete_outline_rounded,
                    context.warn,
                    () {
                      brain.remove(item.id);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
                children: [
                  Text(
                    _fullDate(item.createdAt),
                    style: TextStyle(fontSize: 13, color: context.muted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.kind == BrainKind.task)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 12),
                          child: _Checkbox(item: item, color: color),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: context.scheme.onSurface,
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: context.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        icon: brainKindIcon(item.kind),
                        label: item.kind.label,
                        color: color,
                      ),
                      _MetaChip(
                        label: '$words ${words == 1 ? 'word' : 'words'}',
                        color: context.muted,
                      ),
                      _MetaChip(
                        label: _time(item.createdAt),
                        color: context.muted,
                      ),
                      if (item.kind == BrainKind.task && item.dueDate != null)
                        _MetaChip(
                          icon: Icons.event_rounded,
                          label: 'Due ${_shortDate(item.dueDate!)}',
                          color: color,
                        ),
                      for (final t in item.tags)
                        _MetaChip(label: '#$t', color: color),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Divider(color: context.hairline, height: 1),
                    const SizedBox(height: 20),
                    ...body,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(BrainItem item, bool isLink) {
    if (isLink) {
      if (item.previewTitle != null && item.previewTitle!.isNotEmpty) {
        return item.previewTitle!;
      }
      final d = _domainOf(item.url!);
      if (item.text.isEmpty || item.text == item.url) return d ?? item.url!;
    }
    return item.text.isEmpty ? item.kind.label : item.text;
  }

  List<Widget> _body(
    BuildContext context,
    BrainItem item,
    bool isLink,
    Color color,
  ) {
    if (isLink) {
      final domain = _domainOf(item.url!) ?? item.url!;
      return [
        if (item.previewImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              item.previewImage!,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
        if (item.previewImage != null) const SizedBox(height: 16),
        // A label the user added, if it isn't just the raw URL.
        if (item.text.isNotEmpty && item.text != item.url) ...[
          Text(
            item.text,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: context.scheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: item.url!));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Link copied')));
          },
          style: FilledButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: Text(domain),
        ),
      ];
    }
    // Notes, tasks and journals show their text as the title, so there's no
    // separate body to repeat.
    return const [];
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return IconButton(
      icon: Icon(icon, size: 22),
      color: color,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.item, required this.color});

  final BrainItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.read<BrainState>().toggleDone(item.id);
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: item.done ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
        ),
        child: item.done
            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({this.icon, required this.label, required this.color});

  final IconData? icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF232232)
            : const Color(0xFFF3F2FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: icon != null ? color : context.muted,
            ),
          ),
        ],
      ),
    );
  }
}

String? _domainOf(String url) {
  var u = url.trim();
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u))
    u = 'https://$u';
  try {
    final host = Uri.parse(u).host;
    return host.isEmpty ? null : host.replaceFirst(RegExp(r'^www\.'), '');
  } catch (_) {
    return null;
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _fullDate(DateTime d) => '${_months[d.month - 1]} ${d.day} ${d.year}';

String _shortDate(DateTime d) =>
    '${_months[d.month - 1].substring(0, 3)} ${d.day}';

String _time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
