import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/badge_icon.dart';
import '../../widgets/inputs.dart';
import '../../widgets/section_header.dart';
import 'account_detail_screen.dart';

/// Where the money lives — create and manage cash / bank / mobile-money
/// accounts and their balances.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
  );

  /// Opens the create/edit sheet directly — used by the account detail screen's
  /// "More" tab so editing lives in exactly one place.
  static Future<void> edit(BuildContext context, Account account) =>
      _AccountSheet.show(context, existing: account);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final balances = state.accountBalances;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Accounts'),
      ),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: context.cardDecoration(),
              child: Row(
                children: [
                  Text(
                    'Total balance',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    Money.format(state.totalBalance),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Your accounts'),
            const SizedBox(height: 14),
            for (final ab in balances)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AccountRow(balance: ab),
              ),
            const SizedBox(height: 4),
            FilledButton.tonalIcon(
              onPressed: () => _AccountSheet.show(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.balance});

  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = balance.account;
    final color = account.of(context);

    return InkWell(
      onTap: () => AccountDetailScreen.open(context, account.id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: context.cardDecoration(),
        child: Row(
          children: [
            BadgeIcon(icon: account.icon, accent: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    account.type.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.muted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              Money.format(balance.balance),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create or edit one account.
class _AccountSheet extends StatefulWidget {
  const _AccountSheet({this.existing});

  final Account? existing;

  static Future<void> show(BuildContext context, {Account? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccountSheet(existing: existing),
    );
  }

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late AccountType _type;
  double _openingBalance = 0;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _type = existing?.type ?? AccountType.cash;
    _openingBalance = existing?.openingBalance ?? 0;
    _balance = TextEditingController(
      text: existing == null ? '' : Money.number(existing.openingBalance),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  Future<void> _save() async {
    final state = context.read<AppState>();
    final existing = widget.existing;
    if (existing == null) {
      await state.addAccount(
        name: _name.text.trim(),
        type: _type,
        openingBalance: _openingBalance,
      );
    } else {
      await state.updateAccount(
        existing.copyWith(
          name: _name.text.trim(),
          type: _type,
          openingBalance: _openingBalance,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    await state.deleteAccount(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    // The last account can't be deleted — every record needs somewhere to land.
    final canDelete =
        isEditing && context.read<AppState>().accounts.length > 1;

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
              isEditing ? 'Edit account' : 'New account',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            LabelledField(
              controller: _name,
              label: 'Name',
              hint: 'M-Pesa, NMB, Cash…',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              'Type',
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
                for (final type in AccountType.values)
                  _TypeChip(
                    type: type,
                    selected: type == _type,
                    onTap: () => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            NumberField(
              controller: _balance,
              label: isEditing ? 'Starting balance' : 'Current balance',
              prefix: Money.symbol,
              onChanged: (value) => setState(() => _openingBalance = value),
            ),
            const SizedBox(height: 6),
            Text(
              'The money in this account before tracking. Its live balance '
              'updates as you spend, receive and transfer.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: Text(isEditing ? 'Save changes' : 'Add account'),
            ),
            if (canDelete) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline_rounded, color: context.warn),
                label: Text(
                  'Delete account',
                  style: TextStyle(color: context.warn),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final AccountType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.scheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: context.isDark ? 0.28 : 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : context.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, size: 16, color: selected ? color : context.muted),
            const SizedBox(width: 7),
            Text(
              type.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
