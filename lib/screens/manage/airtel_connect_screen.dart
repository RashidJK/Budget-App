import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../integrations/transaction_source.dart';
import '../../integrations/transaction_sync.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// Connect an Airtel Money feed and pull transactions into the ledger.
///
/// Today this runs against [MockAirtelSource] so the whole flow — fetch, dedup,
/// map, record — works end-to-end. Wiring the real account is a matter of
/// swapping the source for one that calls your backend proxy.
class AirtelConnectScreen extends StatefulWidget {
  const AirtelConnectScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AirtelConnectScreen()),
    );
  }

  @override
  State<AirtelConnectScreen> createState() => _AirtelConnectScreenState();
}

class _AirtelConnectScreenState extends State<AirtelConnectScreen> {
  static const _source = MockAirtelSource();

  bool _syncing = false;
  DateTime? _lastSynced;
  SyncResult? _lastResult;

  @override
  void initState() {
    super.initState();
    TransactionSync.lastSynced().then((value) {
      if (mounted) setState(() => _lastSynced = value);
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await TransactionSync(
        state: state,
        source: _source,
      ).run(since: _lastSynced);
      final now = DateTime.now();
      await TransactionSync.markSynced(now);
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _lastSynced = now;
        _lastResult = result;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.isEmpty
                ? 'Up to date — nothing new'
                : 'Imported ${result.imported} '
                      '${result.imported == 1 ? 'transaction' : 'transactions'}'
                      '${result.skipped > 0 ? ' · ${result.skipped} already there' : ''}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncing = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Sync failed — please try again')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Airtel Money')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Connection status.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: context.cardDecoration(),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE12A2A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFFE12A2A),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _source.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _lastSynced == null
                            ? 'Never synced'
                            : 'Last synced ${_formatWhen(_lastSynced!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.check_circle_rounded, color: context.good),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(_syncing ? 'Syncing…' : 'Sync now'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),

          // What the last run recorded.
          if (_lastResult != null && !_lastResult!.isEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Just imported',
              style: theme.textTheme.labelLarge?.copyWith(color: context.muted),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: context.cardDecoration(),
              child: Column(
                children: [
                  for (var i = 0; i < _lastResult!.titles.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: context.hairline, indent: 16),
                    ListTile(
                      leading: const Icon(Icons.south_west_rounded, size: 20),
                      title: Text(_lastResult!.titles[i]),
                      dense: true,
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          // Honest note about what this is and what real wiring needs.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.scheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: context.scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Demo source',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'This runs sample data through the real Airtel '
                  'Transactions-Summary parser, so the flow works end to end. '
                  'Going live needs a small backend that holds the Airtel API '
                  'credentials and returns /merchant/v1/transactions — the app '
                  'then syncs from it exactly like this.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatWhen(DateTime dt) {
    final l = dt.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month} · $hh:$mm';
  }
}
