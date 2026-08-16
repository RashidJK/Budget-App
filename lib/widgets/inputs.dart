import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../planner/engine.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Allows digits and at most one decimal point.
///
/// Applied at the formatter level rather than validated on submit, because
/// planner fields recalculate live — there is no submit step to validate at,
/// and a half-typed "5..2" must never reach the engine.
final _decimalOnly = FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'));

/// A labelled numeric field with a unit affix.
///
/// Reports every keystroke through [onChanged] so results recalculate live.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.prefix,
    this.suffix,
    this.hint,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<double> onChanged;

  /// Leading unit, e.g. `TSh`.
  final String? prefix;

  /// Trailing unit, e.g. `km/L`.
  final String? suffix;

  final String? hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_decimalOnly],
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: hint ?? '0',
            prefixIcon: prefix == null
                ? null
                : _Affix(text: prefix!, leading: true),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
            suffixIcon: suffix == null
                ? null
                : _Affix(text: suffix!, leading: false),
            suffixIconConstraints: const BoxConstraints(minWidth: 0),
          ),
          onChanged: (raw) => onChanged(double.tryParse(raw) ?? 0),
        ),
      ],
    );
  }
}

class _Affix extends StatelessWidget {
  const _Affix({required this.text, required this.leading});

  final String text;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: leading ? 16 : 12,
        right: leading ? 4 : 16,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: context.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Plain text field with the same label treatment as [NumberField].
class LabelledField extends StatelessWidget {
  const LabelledField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

/// Frequency picker, including the custom days-per-month field that only
/// appears when it is relevant.
class FrequencyPicker extends StatelessWidget {
  const FrequencyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.customDays,
    required this.onCustomDaysChanged,
  });

  final Frequency value;
  final ValueChanged<Frequency> onChanged;
  final double customDays;
  final ValueChanged<double> onCustomDaysChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frequency',
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final frequency in Frequency.values)
              ChoiceChip(
                label: Text(frequency.label),
                selected: frequency == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(frequency),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: context.hairline),
                ),
              ),
          ],
        ),
        // Only rendered for the custom option — an always-visible field would
        // imply it affects the other three, which it does not.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: value == Frequency.customPerMonth
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _CustomDaysSlider(
                    days: customDays,
                    onChanged: onCustomDaysChanged,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _CustomDaysSlider extends StatelessWidget {
  const _CustomDaysSlider({required this.days, required this.onChanged});

  final double days;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rounded = days.clamp(1.0, 31.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Days per month',
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${rounded.round()}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: rounded,
          min: 1,
          max: 31,
          divisions: 30,
          label: '${rounded.round()} days',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Horizontally scrolling category picker.
///
/// Reads the category list from state rather than a constant, since categories
/// are user data. [onManage] adds a trailing button for creating a new one, so
/// a missing category can be fixed without abandoning the form.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Category',
    this.onManage,
  });

  final String selectedId;
  final ValueChanged<String> onChanged;
  final String label;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = context.watch<AppState>().categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: categories.length + (onManage == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == categories.length) {
                return _AddChip(onTap: onManage!);
              }

              final category = categories[index];
              final selected = category.id == selectedId;
              final color = category.of(context);

              return GestureDetector(
                onTap: () => onChanged(category.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: context.isDark ? 0.28 : 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? color : context.hairline,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(category.icon, size: 18, color: color),
                      const SizedBox(width: 8),
                      Text(
                        category.name,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: context.scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Trailing "new category" affordance on [CategoryPicker].
class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 18, color: context.muted),
            const SizedBox(width: 6),
            Text(
              'New',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: context.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented picker for which profile an expense belongs to.
///
/// Hidden entirely when only one profile exists — a chooser with a single
/// option is noise on a form the user fills in several times a day.
class ProfilePicker extends StatelessWidget {
  const ProfilePicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Profile',
  });

  final String selectedId;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = context.watch<AppState>().profiles;
    if (profiles.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final profile in profiles)
              ChoiceChip(
                label: Text(profile.name),
                avatar: Icon(
                  profile.icon,
                  size: 16,
                  color: profile.of(context),
                ),
                selected: profile.id == selectedId,
                showCheckmark: false,
                onSelected: (_) => onChanged(profile.id),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: context.hairline),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A titled block of inputs or results.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(title!, style: theme.textTheme.titleMedium),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Empty-state placeholder used by the lists.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: context.scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: context.muted),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Read-only row pairing a label with a value, used in result summaries.
class ValueRow extends StatelessWidget {
  const ValueRow({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? accent;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (accent != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: bold ? context.scheme.onSurface : context.muted,
                fontWeight: bold ? FontWeight.w600 : null,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats a frequency into the phrasing used in insight sentences.
String frequencyPhrase(Frequency frequency, double customDays) {
  return switch (frequency) {
    Frequency.everyDay => 'every day',
    Frequency.weekdaysOnly => 'every weekday',
    Frequency.weekendsOnly => 'every weekend',
    Frequency.customPerMonth =>
      '${customDays.round()} ${customDays.round() == 1 ? 'day' : 'days'} a month',
  };
}
