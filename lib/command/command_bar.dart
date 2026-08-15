import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../models/category_fields.dart';
import '../planner/engine.dart' as engine;
import '../screens/tracker/metadata_sheet.dart';
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

  /// Presents the command bar. [scanner] is injectable so tests can replace the
  /// OCR; when omitted it uses [defaultReceiptScanner] (ML Kit in production,
  /// the mock in tests). [initialText] pre-fills the field.
  static Future<void> show(
    BuildContext context, {
    ReceiptScanner? scanner,
    String? initialText,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Dim the current screen but keep it visible behind (spec §4).
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _CommandSheet(
        scanner: scanner ?? defaultReceiptScanner,
        initialText: initialText,
      ),
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

  /// True once "Loan" is tapped, revealing Lend / Borrow in its place.
  bool _loanExpanded = false;

  /// Rotating example placeholder that teaches what the field understands
  /// (spec §37 rule 1: minimum typing — but the user still needs to know what
  /// they *can* type). Cycles only while the field is empty.
  static const _hints = [
    "Try 'I spent 5,000 on lunch'",
    "Try 'OEA paid me 300,000'",
    "Try 'I lent John 50,000'",
    "Try 'Transfer 100k to M-Pesa'",
    "Ask 'How much do I owe John?'",
  ];
  int _hintIndex = 0;
  Timer? _hintTimer;

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

    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_controller.text.isEmpty && _parsed == null && _captured == null) {
        setState(() => _hintIndex = (_hintIndex + 1) % _hints.length);
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
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
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        // No enclosing surface — each piece is its own floating glass island,
        // Siri-style, with the dimmed screen showing through the gaps.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _captured != null ? _successIslands() : _inputIslands(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Input state — floating islands
  // ---------------------------------------------------------------------------

  List<Widget> _inputIslands() {
    return [
      // The context area above the bar: quick actions when empty, a live
      // preview once something is typed.
      if (_parsed == null)
        _quickActionIslands()
      else
        _Glass(
          padding: const EdgeInsets.all(16),
          child: _preview(_parsed!),
        ),
      const SizedBox(height: 10),
      // The input bar island + the scan island beside it.
      Row(
        children: [
          Expanded(
            child: _Glass(
              radius: 26,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _pasteMode
                        ? Icons.content_paste_rounded
                        : Icons.bolt_rounded,
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
                      // Transparent so the glass shows through — override the
                      // global filled/bordered input theme. The hint rotates
                      // through examples to teach what the field understands.
                      decoration: InputDecoration(
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        hintText: _pasteMode
                            ? 'Paste a transaction message'
                            : _hints[_hintIndex],
                      ),
                      onChanged: _onChanged,
                      onSubmitted: (_) => _onPrimaryAction(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _GlassButton(
            onTap: _scanning ? null : _scan,
            child: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_rounded, size: 22),
          ),
        ],
      ),
    ];
  }

  /// A short, self-explaining set of glass chips. Expense isn't here — the
  /// rotating hint teaches that you just type an amount — and Lend/Borrow hide
  /// behind one "Loan" chip that expands in place, so the common view stays to
  /// four compact chips without losing any capability (spec §4).
  Widget _quickActionIslands() {
    final chips = _loanExpanded
        ? <Widget>[
            _chip(_Qa.lend, 'Lend', Icons.call_made_rounded),
            _chip(_Qa.borrow, 'Borrow', Icons.call_received_rounded),
            _backChip(),
          ]
        : <Widget>[
            _chip(_Qa.income, 'Income', Icons.south_west_rounded),
            _chip(_Qa.transfer, 'Transfer', Icons.swap_horiz_rounded),
            _loanChip(),
            _chip(_Qa.paste, 'Paste', Icons.content_paste_rounded),
          ];

    // A vertical stack of content-width chips, left-aligned.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          chips[i],
        ],
      ],
    );
  }

  Widget _chip(_Qa kind, String label, IconData icon, {VoidCallback? onTap}) {
    return _Glass(
      radius: 18,
      padding: EdgeInsets.zero,
      onTap: onTap ?? () => _onQuickAction(kind),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: context.scheme.primary),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loanChip() => _chip(
    _Qa.lend,
    'Loan',
    Icons.swap_vert_rounded,
    onTap: () => setState(() => _loanExpanded = true),
  );

  Widget _backChip() => _Glass(
    radius: 18,
    padding: EdgeInsets.zero,
    onTap: () => setState(() => _loanExpanded = false),
    child: const Padding(
      padding: EdgeInsets.all(9),
      child: Icon(Icons.close_rounded, size: 16),
    ),
  );

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

    // Plain content — the glass island is the surface.
    return Column(
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
    );
  }

  Widget _planResult(PlanIntent plan) {
    final theme = Theme.of(context);
    final rows = _computePlan(plan);

    return Column(
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
    );
  }

  // ---------------------------------------------------------------------------
  // Success state
  // ---------------------------------------------------------------------------

  List<Widget> _successIslands() {
    final theme = Theme.of(context);
    return [
      _Glass(
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
            // Capture-first, enrich-later (spec §19): if the captured expense's
            // category has extra fields (litres, odometer…), offer to add them
            // — but the record is already saved, so this is purely optional.
            if (_enrichPrompt() case final prompt?) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _openEnrich,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(prompt),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      // The two footer actions are their own islands.
      Row(
        children: [
          Expanded(
            child: _Glass(
              radius: 22,
              padding: EdgeInsets.zero,
              onTap: _undo,
              child: _islandLabel(Icons.undo_rounded, 'Undo'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Glass(
              radius: 22,
              padding: EdgeInsets.zero,
              tint: context.scheme.primary,
              onTap: () => Navigator.of(context).pop(),
              child: _islandLabel(
                Icons.check_rounded,
                'Done',
                color: context.scheme.primary,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _islandLabel(IconData icon, String label, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// The enrich-later prompt for the captured expense, or null when there's
  /// nothing extra to add.
  String? _enrichPrompt() {
    final captured = _captured;
    if (captured == null || !captured.isExpense) return null;
    final expense = context.read<AppState>().expenseById(captured.id);
    if (expense == null || !CategoryFields.has(expense.categoryId)) return null;
    final name = context.read<AppState>().categoryById(expense.categoryId).name;
    return CategoryFields.promptFor(name);
  }

  Future<void> _openEnrich() async {
    final captured = _captured;
    if (captured == null) return;
    await MetadataSheet.show(context, captured.id);
    if (mounted) Navigator.of(context).pop();
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
        // Fuel answers report litres and refuel count from the metadata that
        // was enriched onto each expense (spec §21: "265.4 L, 8 refuels").
        String detail =
            '${matching.length} ${matching.length == 1 ? 'expense' : 'expenses'}';
        if (query.categoryId == 'fuel') {
          final litres = matching.fold<double>(
            0,
            (sum, e) => sum + ((e.metadata['litres'] as num?)?.toDouble() ?? 0),
          );
          if (litres > 0) {
            detail = '${matching.length} refuels · ${Money.litres(litres)}';
          }
        }
        return _Answer(
          label: '$name · ${_timeframeLabel(query)}',
          value: Money.format(total),
          detail: detail,
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

/// A frosted-glass "island": a rounded, translucent, blurred surface that lets
/// the dimmed screen behind show through, iOS-style. Each piece of the command
/// bar is one of these, floating with gaps between them.
class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Optional accent wash (e.g. the primary colour on a confirm button).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    // A translucent fill over the blur; a hair of tint if requested.
    final base = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.55);
    final fill = tint == null
        ? base
        : Color.alphaBlend(tint!.withValues(alpha: dark ? 0.22 : 0.16), base);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Material(
          color: fill,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                // A bright hairline gives the glass its edge highlight.
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? 0.14 : 0.6),
                  width: 1,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular glass island for a single icon action (the scan button).
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      radius: 26,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Center(child: child),
      ),
    );
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
