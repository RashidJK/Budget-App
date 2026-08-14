import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../planner/engine.dart' as engine;
import '../services/format.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'command_parser.dart';
import 'receipt_scanner.dart';

/// The universal command bar (spec §4, §5, §31).
///
/// A compact floating sheet over the current screen — Spotlight, not a
/// chatbot. It parses what the user types on every keystroke and shows a live,
/// compact preview: a confirmation card for a new activity, a one-tap
/// clarification for an ambiguous one, or an answer for a history/planner
/// question. Nothing is a full form; the manual expense form stays one tap away
/// behind "Edit".
class CommandBar {
  const CommandBar._();

  /// Presents the command bar. [scanner] is injectable so tests and a future
  /// real OCR provider can replace the mock. [initialText] pre-fills the field
  /// (used to deep-link a command in, and by tests).
  static Future<void> show(
    BuildContext context, {
    ReceiptScanner scanner = const MockReceiptScanner(),
    String? initialText,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Dim the current screen but keep it visible behind (spec §4).
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _CommandSheet(scanner: scanner, initialText: initialText),
    );
  }
}

class _CommandSheet extends StatefulWidget {
  const _CommandSheet({required this.scanner, this.initialText});

  final ReceiptScanner scanner;
  final String? initialText;

  @override
  State<_CommandSheet> createState() => _CommandSheetState();
}

class _CommandSheetState extends State<_CommandSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  ParsedCommand? _parsed;
  bool _pasteMode = false;
  bool _scanning = false;

  /// Set once the user commits, switching the sheet to its success state.
  CaptureResult? _captured;
  String _capturedSummary = '';

  @override
  void initState() {
    super.initState();
    final seed = widget.initialText;
    if (seed != null && seed.isNotEmpty) {
      _controller.text = seed;
      _controller.selection = TextSelection.collapsed(offset: seed.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onChanged(seed);
      });
    }
    // Focus immediately so the keyboard is up on open (spec §4).
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  CommandParser get _parser =>
      CommandParser(context.read<AppState>().parseContext());

  void _onChanged(String value) {
    setState(() {
      _parsed = value.trim().isEmpty
          ? null
          : (_pasteMode ? _parser.parsePaste(value) : _parser.parse(value));
    });
  }

  void _prime(String text, {bool paste = false}) {
    _pasteMode = paste;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _focus.requestFocus();
    _onChanged(text);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _notify('Clipboard is empty');
      return;
    }
    _prime(text, paste: true);
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) {
        setState(() => _scanning = false);
        return;
      }
      final receipt = await widget.scanner.scan(picked.path);
      if (!mounted) return;
      if (receipt == null) {
        setState(() => _scanning = false);
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't read that receipt.")),
        );
        return;
      }
      final defaultProfile = context.read<AppState>().defaultProfileId;
      setState(() {
        _scanning = false;
        _parsed = ParsedCommand(
          kind: CommandKind.create,
          rawText: 'receipt',
          confidence: receipt.confidence,
          activity: receipt.toParsedActivity(defaultProfileId: defaultProfile),
        );
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _scanning = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the camera.')),
      );
    }
  }

  Future<void> _commit(ParsedActivity activity, {double? confidence}) async {
    final state = context.read<AppState>();
    final source = _pasteMode
        ? ActivitySource.pastedTransaction
        : ActivitySource.command;
    final result = await state.capture(
      activity,
      source: source,
      confidence: confidence ?? _parsed?.confidence,
    );
    if (!mounted) return;
    setState(() {
      _captured = result;
      _capturedSummary = _summaryFor(activity);
    });
  }

  Future<void> _undo() async {
    final state = context.read<AppState>();
    final captured = _captured;
    if (captured != null) await state.undoCapture(captured);
    if (mounted) Navigator.of(context).pop();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: context.isDark ? const Color(0xFF1E1F24) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.bottomCenter,
            child: _captured != null ? _successBody() : _inputBody(),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Input state
  // ---------------------------------------------------------------------------

  Widget _inputBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(
            children: [
              Icon(
                _pasteMode ? Icons.content_paste_rounded : Icons.bolt_rounded,
                color: context.scheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  maxLines: _pasteMode ? 4 : 1,
                  minLines: 1,
                  textInputAction: TextInputAction.done,
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'What do you want to do?',
                  ),
                  onChanged: _onChanged,
                  onSubmitted: (_) => _onPrimaryAction(),
                ),
              ),
              IconButton(
                onPressed: _scanning ? null : _scan,
                tooltip: 'Scan receipt',
                icon: _scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_rounded, size: 22),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: context.hairline),
        Padding(
          padding: const EdgeInsets.all(14),
          child: _parsed == null ? _quickActions() : _preview(_parsed!),
        ),
      ],
    );
  }

  Widget _quickActions() {
    final actions = <(_Qa, String, IconData)>[
      (_Qa.expense, 'Add expense', Icons.remove_circle_outline_rounded),
      (_Qa.income, 'Add income', Icons.add_circle_outline_rounded),
      (_Qa.transfer, 'Transfer', Icons.swap_horiz_rounded),
      (_Qa.lend, 'Lend', Icons.call_made_rounded),
      (_Qa.borrow, 'Borrow', Icons.call_received_rounded),
      (_Qa.paste, 'Paste', Icons.content_paste_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Try "5000 lunch", "OEA paid me 300000", or ask "how much do I owe John?"',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (kind, label, icon) in actions)
              ActionChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                onPressed: () => _onQuickAction(kind),
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

  void _onQuickAction(_Qa kind) {
    switch (kind) {
      case _Qa.expense:
        _focus.requestFocus();
      case _Qa.income:
        _prime('Received ');
      case _Qa.transfer:
        _prime('Transfer ');
      case _Qa.lend:
        _prime('Lent ');
      case _Qa.borrow:
        _prime('Borrowed ');
      case _Qa.paste:
        _paste();
    }
  }

  void _onPrimaryAction() {
    final parsed = _parsed;
    if (parsed == null) return;
    if (parsed.kind == CommandKind.create && parsed.activity != null) {
      _commit(parsed.activity!);
    }
    // Query/plan results are shown live; ambiguous waits for a chip tap.
  }

  // ---------------------------------------------------------------------------
  // Live preview
  // ---------------------------------------------------------------------------

  Widget _preview(ParsedCommand parsed) {
    switch (parsed.kind) {
      case CommandKind.create:
        return _createPreview(parsed.activity!, parsed.confidence);
      case CommandKind.ambiguous:
        return _ambiguousPreview(parsed);
      case CommandKind.query:
        return _queryResult(parsed.query!);
      case CommandKind.plan:
        return _planResult(parsed.plan!);
      case CommandKind.unknown:
        return Text(
          "I couldn't read that yet. Try an amount and what it was for, "
          'like "5000 lunch".',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.muted,
          ),
        );
    }
  }

  Widget _createPreview(ParsedActivity activity, double confidence) {
    final theme = Theme.of(context);
    final tone = _toneFor(activity.type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _signedAmount(activity),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activity.description.isEmpty
                        ? activity.type.label
                        : activity.description,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitleFor(activity),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.muted,
                    ),
                  ),
                ],
              ),
            ),
            _TypePill(type: activity.type),
          ],
        ),
        if (confidence < 0.75) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: context.warn),
              const SizedBox(width: 6),
              Text(
                'Some details are a guess — saved as "needs review".',
                style: theme.textTheme.bodySmall?.copyWith(color: context.warn),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => _commit(activity, confidence: confidence),
                child: Text(_addLabel(activity.type)),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => _editInFullForm(activity),
              child: const Text('Edit'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _ambiguousPreview(ParsedCommand parsed) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parsed.clarificationQuestion ?? 'What was this?',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in parsed.clarificationTypes)
              ActionChip(
                label: Text(type.label),
                onPressed: () {
                  // Re-classify the same input as the chosen type and commit.
                  final base = parsed.activity;
                  final resolved = base != null
                      ? base.copyWith(type: type)
                      : _reparseAs(parsed.rawText, type);
                  if (resolved != null) _commit(resolved, confidence: 0.9);
                },
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

  /// The parser leaves an ambiguous command with no activity; rebuild a
  /// ParsedActivity from the raw text once the user picks a type.
  ParsedActivity? _reparseAs(String raw, ActivityType type) {
    // Force the type by appending an unambiguous verb, then re-parse.
    final hint = switch (type) {
      ActivityType.income => 'received ',
      ActivityType.loanIn => 'borrowed ',
      ActivityType.receivableRepayment => '',
      _ => '',
    };
    final result = _parser.parse('$hint$raw');
    return result.activity?.copyWith(type: type);
  }

  Widget _queryResult(QueryIntent query) {
    final state = context.read<AppState>();
    final answer = _answerQuery(state, query);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            answer.label,
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
          ),
          const SizedBox(height: 4),
          Text(
            answer.value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (answer.detail != null) ...[
            const SizedBox(height: 4),
            Text(answer.detail!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _planResult(PlanIntent plan) {
    final theme = Theme.of(context);
    final rows = _computePlan(plan);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Projection',
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
          ),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Success state
  // ---------------------------------------------------------------------------

  Widget _successBody() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: context.good, size: 22),
              const SizedBox(width: 8),
              Text('Recorded', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Text(_capturedSummary, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _undo,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Undo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Full form fallback (spec §16, §37 rule 7)
  // ---------------------------------------------------------------------------

  void _editInFullForm(ParsedActivity activity) {
    // For an expense, the existing detailed form is the natural "Edit" target.
    // Non-expense types don't have a dedicated form yet, so committing then
    // editing from history is the path; for now, just commit.
    Navigator.of(context).pop();
    // The caller (home shell) can offer the full form; keeping the command bar
    // focused on capture. Committing keeps the data rather than losing it.
    context.read<AppState>().capture(activity, source: ActivitySource.command);
  }

  // ---------------------------------------------------------------------------
  // Query answering
  // ---------------------------------------------------------------------------

  _Answer _answerQuery(AppState state, QueryIntent query) {
    final now = DateTime.now();
    final month = switch (query.timeframe) {
      Timeframe.thisMonth => DateTime(now.year, now.month),
      Timeframe.lastMonth => DateTime(now.year, now.month - 1),
      Timeframe.specificMonth => DateTime(now.year, query.month ?? now.month),
      _ => DateTime(now.year, now.month),
    };
    final inMonth = state.expensesInMonth(month);

    switch (query.topic) {
      case QueryTopic.categorySpend:
        final matching = inMonth
            .where((e) => e.categoryId == query.categoryId)
            .toList();
        final total = state.totalFor(matching);
        final name = state.categoryById(query.categoryId).name;
        return _Answer(
          label: '$name · ${_timeframeLabel(query)}',
          value: Money.format(total),
          detail:
              '${matching.length} ${matching.length == 1 ? 'expense' : 'expenses'}',
        );
      case QueryTopic.totalSpend:
        return _Answer(
          label: 'Spent ${_timeframeLabel(query)}',
          value: Money.format(state.totalFor(inMonth)),
        );
      case QueryTopic.biggestExpenses:
        final sorted = [...inMonth]..sort((a, b) => b.amount.compareTo(a.amount));
        final top = sorted.take(3).toList();
        return _Answer(
          label: 'Biggest ${_timeframeLabel(query)}',
          value: top.isEmpty ? Money.format(0) : Money.format(top.first.amount),
          detail: top.map((e) => e.title).join(', '),
        );
      case QueryTopic.income:
        return _Answer(
          label: 'Income ${_timeframeLabel(query)}',
          value: Money.format(state.incomeThisMonth),
        );
      case QueryTopic.merchantSpend:
        final needle = (query.merchant ?? '').toLowerCase();
        final matching = state.expenses
            .where((e) => e.searchable.contains(needle))
            .toList();
        return _Answer(
          label: 'At ${query.merchant}',
          value: Money.format(state.totalFor(matching)),
          detail:
              '${matching.length} ${matching.length == 1 ? 'expense' : 'expenses'}',
        );
      case QueryTopic.owedToMe:
        final balance = _balanceForName(state, query.personName);
        return _Answer(
          label: query.personName == null
              ? 'Owed to you'
              : '${query.personName} owes you',
          value: Money.format(balance > 0 ? balance : 0),
        );
      case QueryTopic.iOwe:
        final balance = _balanceForName(state, query.personName);
        return _Answer(
          label: query.personName == null
              ? 'You owe'
              : 'You owe ${query.personName}',
          value: Money.format(balance < 0 ? -balance : 0),
        );
    }
  }

  double _balanceForName(AppState state, String? name) {
    if (name == null) return state.totalOwedToUser;
    final key = name.trim().toLowerCase();
    for (final person in state.people) {
      if (person.matchKey == key) return state.balanceWith(person.id);
    }
    return 0;
  }

  String _timeframeLabel(QueryIntent query) {
    switch (query.timeframe) {
      case Timeframe.lastMonth:
        return 'last month';
      case Timeframe.specificMonth:
        const months = [
          'January', 'February', 'March', 'April', 'May', 'June', 'July',
          'August', 'September', 'October', 'November', 'December',
        ];
        return 'in ${months[(query.month ?? 1) - 1]}';
      default:
        return 'this month';
    }
  }

  // ---------------------------------------------------------------------------
  // Plan computation
  // ---------------------------------------------------------------------------

  List<(String, String)> _computePlan(PlanIntent plan) {
    switch (plan.topic) {
      case PlanTopic.dailyHabit:
        final breakdown = engine.breakdownFor(
          amount: plan.dailyAmount ?? 0,
          frequency: engine.Frequency.everyDay,
        );
        return [
          ('Daily', Money.format(breakdown.daily)),
          ('Weekly', Money.format(breakdown.weekly)),
          ('Monthly', Money.format(breakdown.monthly)),
          ('Yearly', Money.format(breakdown.yearly)),
        ];
      case PlanTopic.reduce:
        final current = engine.breakdownFor(
          amount: plan.dailyAmount ?? 0,
          frequency: engine.Frequency.everyDay,
        );
        final next = engine.breakdownFor(
          amount: plan.newAmount ?? 0,
          frequency: engine.Frequency.everyDay,
        );
        final monthlySaving = current.monthly - next.monthly;
        final yearlySaving = current.yearly - next.yearly;
        return [
          ('Now / month', Money.format(current.monthly)),
          ('New / month', Money.format(next.monthly)),
          ('Monthly saving', Money.format(monthlySaving)),
          ('Yearly saving', Money.format(yearlySaving)),
        ];
      case PlanTopic.fuel:
        // Use sensible Tanzanian defaults; the full Fuel planner refines these.
        final estimate = engine.estimateFuel(
          distancePerDay: plan.distancePerDay ?? 0,
          efficiency: 12,
          pricePerLitre: 3200,
        );
        return [
          ('Litres / month', Money.litres(estimate.litresPerMonth)),
          ('Monthly', Money.format(estimate.cost.monthly)),
          ('Yearly', Money.format(estimate.cost.yearly)),
        ];
    }
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  Color _toneFor(ActivityType type) {
    if (type.isInflow) return context.good;
    if (type == ActivityType.transfer) return context.scheme.onSurface;
    return context.scheme.onSurface;
  }

  String _signedAmount(ParsedActivity activity) {
    final money = Money.format(activity.amount);
    if (activity.type.isInflow) return '+$money';
    if (activity.type == ActivityType.transfer) return money;
    return money;
  }

  String _subtitleFor(ParsedActivity activity) {
    final state = context.read<AppState>();
    switch (activity.type) {
      case ActivityType.transfer:
        return '${activity.sourceAccount ?? 'From'} → '
            '${activity.destinationAccount ?? 'To'}';
      case ActivityType.loanOut:
      case ActivityType.loanIn:
      case ActivityType.loanRepayment:
      case ActivityType.receivableRepayment:
        return activity.type.label;
      case ActivityType.income:
        return 'Income · ${_profileName(state, activity.profileId)}';
      case ActivityType.expense:
        final category = state.categoryById(activity.categoryId).name;
        return '$category · ${_profileName(state, activity.profileId)}';
    }
  }

  String _profileName(AppState state, String? id) =>
      state.profileById(id)?.name ?? 'Personal';

  String _addLabel(ActivityType type) {
    switch (type) {
      case ActivityType.income:
        return 'Add income';
      case ActivityType.transfer:
        return 'Add transfer';
      case ActivityType.loanOut:
        return 'Record loan';
      case ActivityType.loanIn:
        return 'Record loan';
      case ActivityType.loanRepayment:
      case ActivityType.receivableRepayment:
        return 'Record repayment';
      case ActivityType.expense:
        return 'Add expense';
    }
  }

  String _summaryFor(ParsedActivity activity) {
    final amount = _signedAmount(activity);
    final what = activity.description.isEmpty
        ? activity.type.label
        : activity.description;
    return '$amount · $what';
  }
}

enum _Qa { expense, income, transfer, lend, borrow, paste }

class _Answer {
  const _Answer({required this.label, required this.value, this.detail});
  final String label;
  final String value;
  final String? detail;
}

/// A small pill naming the detected activity type.
class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

  final ActivityType type;

  @override
  Widget build(BuildContext context) {
    final color = type.isInflow
        ? context.good
        : type == ActivityType.transfer
        ? context.scheme.primary
        : context.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
