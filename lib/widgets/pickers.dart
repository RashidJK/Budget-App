import 'package:flutter/material.dart';

import '../models/icons.dart';
import '../models/palette.dart';
import '../theme.dart';

/// Grid of the icons a category or profile can wear.
class IconPicker extends StatelessWidget {
  const IconPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.accent,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        // Two rows, not four: at four the tiles fell to ~23px, half the ~48px
        // minimum tap target. Two rows in the same height give ~54px tiles.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: IconChoice.all.length,
        itemBuilder: (context, index) {
          final choice = IconChoice.all[index];
          final isSelected = choice.name == selected;

          return GestureDetector(
            onTap: () => onChanged(choice.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: context.isDark ? 0.28 : 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? accent : context.hairline,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Icon(
                choice.icon,
                size: 20,
                color: isSelected ? accent : context.muted,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Palette slot picker.
///
/// Slots already used by another category are still selectable — sharing a hue
/// is sometimes what the user wants — but they are marked, because two
/// same-coloured categories in one chart cannot be told apart.
class ColorSlotPicker extends StatelessWidget {
  const ColorSlotPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.used = const {},
  });

  final int? selected;
  final ValueChanged<int?> onChanged;
  final Set<int> used;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final slot in Palette.indices)
          _Swatch(
            color: Palette.color(slot, brightness),
            label: Palette.name(slot),
            isSelected: slot == selected,
            isTaken: used.contains(slot) && slot != selected,
            onTap: () => onChanged(slot),
          ),
        _Swatch(
          color: Palette.color(null, brightness),
          label: 'Neutral',
          isSelected: selected == null,
          isTaken: false,
          onTap: () => onChanged(null),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.isTaken,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool isSelected;
  final bool isTaken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isTaken ? '$label (already used)' : label,
      child: GestureDetector(
        onTap: onTap,
        // The swatch stays 40px, but the tap area is padded out to the ~48px
        // minimum so the target isn't pixel-precise.
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? context.scheme.onSurface
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: isTaken
                  ? Icon(
                      Icons.circle,
                      size: 7,
                      color: Colors.white.withValues(alpha: 0.85),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact label + control wrapper used across the editor sheets.
class FieldLabel extends StatelessWidget {
  const FieldLabel({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
