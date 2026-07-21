import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/profile.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'category_editor.dart';
import 'profile_editor.dart';

/// Manage categories and profiles.
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key, this.initialTab = 0});

  /// 0 for Categories, 1 for Profiles.
  final int initialTab;

  static Future<void> open(BuildContext context, {int initialTab = 0}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManageScreen(initialTab: initialTab),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Categories'),
              Tab(text: 'Profiles'),
            ],
          ),
        ),
        body: const TabBarView(children: [_CategoryTab(), _ProfileTab()]),
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab();

  /// Deleting a category has to send its expenses somewhere; this asks where.
  Future<void> _confirmDelete(
    BuildContext context,
    ExpenseCategory category,
  ) async {
    final state = context.read<AppState>();
    final affected = state.expenseCountForCategory(category.id);
    final others = state.categories
        .where((item) => item.id != category.id)
        .toList();

    if (others.isEmpty) return;

    var reassignTo = others.first.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Delete "${category.name}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                affected == 0
                    ? 'No expenses use this category.'
                    : '$affected ${affected == 1 ? 'expense uses' : 'expenses use'} '
                          'this category. They will be moved, not deleted.',
              ),
              if (affected > 0) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: reassignTo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Move them to',
                    isDense: true,
                  ),
                  items: [
                    for (final other in others)
                      DropdownMenuItem(
                        value: other.id,
                        child: Text(other.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => reassignTo = value);
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed ?? false) {
      await state.deleteCategory(category.id, reassignTo: reassignTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final categories = state.categories;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => CategoryEditorSheet.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final count = state.expenseCountForCategory(category.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ManageRow(
              icon: category.icon,
              color: category.of(context),
              title: category.name,
              subtitle: count == 0
                  ? 'No expenses'
                  : '$count ${count == 1 ? 'expense' : 'expenses'}',
              onTap: () =>
                  CategoryEditorSheet.show(context, existing: category),
              onDelete: categories.length <= 1
                  ? null
                  : () => _confirmDelete(context, category),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  Future<void> _confirmDelete(BuildContext context, Profile profile) async {
    final state = context.read<AppState>();
    final affected = state.expenseCountForProfile(profile.id);
    final others = state.profiles
        .where((item) => item.id != profile.id)
        .toList();

    if (others.isEmpty) return;

    var reassignTo = others.first.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Delete "${profile.name}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                affected == 0
                    ? 'No expenses belong to this profile.'
                    : '$affected ${affected == 1 ? 'expense belongs' : 'expenses belong'} '
                          'to this profile. They will be moved, not deleted.',
              ),
              if (affected > 0) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: reassignTo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Move them to',
                    isDense: true,
                  ),
                  items: [
                    for (final other in others)
                      DropdownMenuItem(
                        value: other.id,
                        child: Text(other.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => reassignTo = value);
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed ?? false) {
      await state.deleteProfile(profile.id, reassignTo: reassignTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profiles = state.profiles;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ProfileEditorSheet.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New profile'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: profiles.length,
        itemBuilder: (context, index) {
          final profile = profiles[index];
          final count = state.expenseCountForProfile(profile.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ManageRow(
              icon: profile.icon,
              color: profile.of(context),
              title: profile.name,
              subtitle: [
                if (profile.isBusiness) 'Business',
                count == 0
                    ? 'No expenses'
                    : '$count ${count == 1 ? 'expense' : 'expenses'}',
              ].join(' · '),
              onTap: () => ProfileEditorSheet.show(context, existing: profile),
              onDelete: profiles.length <= 1
                  ? null
                  : () => _confirmDelete(context, profile),
            ),
          );
        },
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Null disables deletion — the last category or profile must survive.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: context.isDark ? 0.26 : 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: onDelete == null
                    ? 'The last one cannot be deleted'
                    : 'Delete',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: onDelete == null ? context.hairline : context.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
