/// Deterministic natural-language parser for the command bar (spec §5, §29,
/// §30).
///
/// The whole design principle is **rules first, AI never-required**. Every
/// example in the spec's test matrix (§38) is resolvable from patterns —
/// amounts, currency, type keywords, people, accounts, categories — so this
/// parser handles them locally and instantly. There is no model call here and
/// the command bar must stay fast without one; an AI fallback, if ever added,
/// slots in only where these rules return [CommandKind.unknown].
///
/// The parser is **pure**: it reads a [ParseContext] snapshot and returns a
/// structured [ParsedCommand]. It never touches storage — persistence is the
/// caller's job (spec §29: "the parser should return structured data, not
/// directly mutate the database").
library;

import '../models/activity.dart';

/// What the user's text is trying to do.
enum CommandKind {
  /// Record a financial activity (expense, income, transfer, loan, repayment).
  create,

  /// Ask about recorded history ("how much did I spend on fuel?").
  query,

  /// Simulate the future ("if I spend 5000 a day, what's the month?").
  plan,

  /// A create whose *type* is genuinely unclear; needs one tap to resolve.
  ambiguous,

  /// Nothing actionable could be extracted.
  unknown,
}

/// Everything the parser needs to know about the user's existing data to
/// resolve context (spec §37 rule 2: don't ask what the app already knows).
class ParseContext {
  const ParseContext({
    this.people = const [],
    this.loanNetByPersonKey = const {},
    this.knownCategoryIds = const {},
    this.profileMatches = const {},
    this.accountMatches = const {},
    this.merchantCategories = const {},
    this.defaultProfileId = 'personal',
  });

  /// Existing people, matched by lowercased name.
  final List<({String id, String name})> people;

  /// Per person (lowercased name → net): positive = they owe the user,
  /// negative = the user owes them. Drives repayment disambiguation (§11).
  final Map<String, double> loanNetByPersonKey;

  /// Category ids the user actually has, so a guessed category is only used
  /// when it exists.
  final Set<String> knownCategoryIds;

  /// Lowercased profile name/alias → profile id, for "Flow-HQ paid …" (§24).
  final Map<String, String> profileMatches;

  /// Lowercased account name/alias → account id, so "paid … from M-Pesa" and
  /// "move X from CRDB to NMB" attribute to the real accounts.
  final Map<String, String> accountMatches;

  /// Learned lowercased merchant → category id, so a merchant seen before is
  /// categorised the same way next time (spec §5).
  final Map<String, String> merchantCategories;

  final String defaultProfileId;
}

/// The structured result. Exactly one of [activity], [query], [plan] is set,
/// per [kind].
class ParsedCommand {
  const ParsedCommand({
    required this.kind,
    required this.rawText,
    this.activity,
    this.query,
    this.plan,
    this.confidence = 0,
    this.clarificationTypes = const [],
    this.clarificationQuestion,
  });

  const ParsedCommand.unknown(this.rawText)
    : kind = CommandKind.unknown,
      activity = null,
      query = null,
      plan = null,
      confidence = 0,
      clarificationTypes = const [],
      clarificationQuestion = null;

  final CommandKind kind;
  final String rawText;
  final ParsedActivity? activity;
  final QueryIntent? query;
  final PlanIntent? plan;

  /// 0..1. High-confidence creates can save immediately (spec §31).
  final double confidence;

  /// When [kind] is [CommandKind.ambiguous], the candidate types to offer as
  /// one-tap chips.
  final List<ActivityType> clarificationTypes;
  final String? clarificationQuestion;
}

/// A parsed but not-yet-saved activity. Mirrors [Activity] but holds a person
/// *name* (unresolved to an id) and a category *guess*.
class ParsedActivity {
  const ParsedActivity({
    required this.type,
    required this.amount,
    required this.date,
    this.currency = 'TZS',
    this.description = '',
    this.categoryId,
    this.profileId,
    this.accountId,
    this.toAccountId,
    this.personName,
    this.sourceAccount,
    this.destinationAccount,
    this.paymentMethod,
    this.merchant,
  });

  final ActivityType type;
  final double amount;
  final DateTime date;
  final String currency;
  final String description;
  final String? categoryId;
  final String? profileId;

  /// Resolved account ids: the account the money moves out of / into, and — for
  /// a transfer — its destination.
  final String? accountId;
  final String? toAccountId;

  final String? personName;
  final String? sourceAccount;
  final String? destinationAccount;
  final PaymentMethod? paymentMethod;
  final String? merchant;

  bool get isExpense => type == ActivityType.expense;

  ParsedActivity copyWith({
    ActivityType? type,
    String? categoryId,
    String? profileId,
    PaymentMethod? paymentMethod,
  }) {
    return ParsedActivity(
      type: type ?? this.type,
      amount: amount,
      date: date,
      currency: currency,
      description: description,
      categoryId: categoryId ?? this.categoryId,
      profileId: profileId ?? this.profileId,
      accountId: accountId,
      toAccountId: toAccountId,
      personName: personName,
      sourceAccount: sourceAccount,
      destinationAccount: destinationAccount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      merchant: merchant,
    );
  }
}

/// What a history question is asking (spec §21).
enum QueryTopic {
  categorySpend,
  totalSpend,
  biggestExpenses,
  merchantSpend,
  owedToMe,
  iOwe,
  income,
}

enum Timeframe { thisMonth, lastMonth, specificMonth, today, yesterday, allTime }

class QueryIntent {
  const QueryIntent({
    required this.topic,
    this.categoryId,
    this.merchant,
    this.personName,
    this.profileId,
    this.timeframe = Timeframe.thisMonth,
    this.month,
  });

  final QueryTopic topic;
  final String? categoryId;
  final String? merchant;
  final String? personName;
  final String? profileId;
  final Timeframe timeframe;

  /// 1..12 when [timeframe] is [Timeframe.specificMonth].
  final int? month;
}

/// What a planning question wants to simulate (spec §22, §36).
enum PlanTopic { dailyHabit, reduce, fuel }

class PlanIntent {
  const PlanIntent({
    required this.topic,
    this.dailyAmount,
    this.newAmount,
    this.categoryId,
    this.distancePerDay,
  });

  final PlanTopic topic;
  final double? dailyAmount;
  final double? newAmount;
  final String? categoryId;
  final double? distancePerDay;
}

/// The parser entry points.
class CommandParser {
  const CommandParser(this.context);

  final ParseContext context;

  /// Parses a free-typed command from the command bar.
  ParsedCommand parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return ParsedCommand.unknown(raw);

    final lower = raw.toLowerCase();

    // Order matters: a plan question ("if I spend…") and a history question
    // ("how much did I spend…") both contain "spend", so those framings are
    // checked before the create path claims the text.
    if (_looksLikePlan(lower)) {
      final plan = _parsePlan(raw, lower);
      if (plan != null) {
        return ParsedCommand(
          kind: CommandKind.plan,
          rawText: raw,
          plan: plan,
          confidence: 0.9,
        );
      }
    }

    if (_looksLikeQuery(lower)) {
      // Query-shaped input must never fall through to the create path and
      // silently record a transaction ("show me expenses above 20000"). If the
      // specific intent is unclear, answer with a safe total-spend query rather
      // than writing data.
      final query = _parseQuery(raw, lower) ??
          const QueryIntent(topic: QueryTopic.totalSpend);
      return ParsedCommand(
        kind: CommandKind.query,
        rawText: raw,
        query: query,
        confidence: 0.85,
      );
    }

    return _parseCreate(raw, lower, source: _Origin.command);
  }

  /// Parses a pasted bank / mobile-money SMS (spec §12). Same extraction, but
  /// the phrasing is third-person ("You have paid …", "You have received …")
  /// and a merchant is usually present.
  ParsedCommand parsePaste(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return ParsedCommand.unknown(raw);
    return _parseCreate(raw, raw.toLowerCase(), source: _Origin.paste);
  }

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  ParsedCommand _parseCreate(String raw, String lower, {required _Origin source}) {
    final money = _extractAmount(lower);
    if (money == null) {
      // No amount → we can't record anything meaningful.
      return ParsedCommand.unknown(raw);
    }

    final date = _extractDate(lower);
    final person = _extractPerson(raw, lower);
    final accounts = _extractTransferAccounts(lower);
    final paymentMethod = _extractPaymentMethod(lower);
    final profileId = _extractProfile(lower);

    var classification = _classifyType(
      lower,
      hasPerson: person != null,
      accounts: accounts,
    );

    // Context override (spec §11): paying money *to* a person the user already
    // owes is a loan repayment, not a fresh expense. Only applied when the
    // command would otherwise be a plain expense to a known-owed person.
    if (!classification.ambiguous &&
        classification.type == ActivityType.expense &&
        person != null &&
        _matches(lower, r'\bto\s') ) {
      final net = context.loanNetByPersonKey[person.toLowerCase()];
      if (net != null && net < 0) {
        classification = const _Classification(
          ActivityType.loanRepayment,
          confidence: 0.8,
        );
      }
    }

    // Genuinely ambiguous inflow like "I got 100000 from John" — try to
    // resolve from loan context before asking (spec §11).
    if (classification.ambiguous) {
      final resolved = _resolveAmbiguous(person, accounts);
      if (resolved != null) {
        return _buildCreate(
          raw: raw,
          lower: lower,
          type: resolved,
          money: money,
          date: date,
          person: person,
          accounts: accounts,
          paymentMethod: paymentMethod,
          profileId: profileId,
          confidence: 0.7,
        );
      }
      return ParsedCommand(
        kind: CommandKind.ambiguous,
        rawText: raw,
        confidence: 0.4,
        clarificationQuestion: 'What was this?',
        clarificationTypes: classification.candidates,
      );
    }

    return _buildCreate(
      raw: raw,
      lower: lower,
      type: classification.type,
      money: money,
      date: date,
      person: person,
      accounts: accounts,
      paymentMethod: paymentMethod,
      profileId: profileId,
      confidence: classification.confidence,
    );
  }

  ParsedCommand _buildCreate({
    required String raw,
    required String lower,
    required ActivityType type,
    required _Money money,
    required DateTime date,
    required String? person,
    required _Accounts accounts,
    required PaymentMethod? paymentMethod,
    required String? profileId,
    required double confidence,
  }) {
    final description = _extractDescription(raw, lower, type, person, money);
    final merchant = _extractMerchant(raw, lower);
    final categoryId = type == ActivityType.expense || type == ActivityType.income
        ? _guessCategory(lower, merchant)
        : null;

    // Attribute to real accounts. A transfer moves source → destination;
    // money in lands in the destination account, money out leaves the source.
    final (sourceId, destId) = _resolveAccountIds(lower);
    final String? accountId;
    final String? toAccountId;
    if (type == ActivityType.transfer) {
      accountId = sourceId;
      toAccountId = destId;
    } else if (type.isInflow) {
      accountId = destId ?? sourceId;
      toAccountId = null;
    } else {
      accountId = sourceId ?? destId;
      toAccountId = null;
    }

    return ParsedCommand(
      kind: CommandKind.create,
      rawText: raw,
      confidence: confidence,
      activity: ParsedActivity(
        type: type,
        amount: money.amount,
        currency: money.currency,
        date: date,
        description: description,
        categoryId: categoryId,
        profileId: profileId ?? context.defaultProfileId,
        accountId: accountId,
        toAccountId: toAccountId,
        personName: person,
        sourceAccount: accounts.from,
        destinationAccount: accounts.to,
        paymentMethod: paymentMethod,
        merchant: merchant,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Type classification
  // ---------------------------------------------------------------------------

  _Classification _classifyType(
    String lower, {
    required bool hasPerson,
    required _Accounts accounts,
  }) {
    // Transfer: two of the user's own accounts, or explicit movement between
    // one's own holdings. A withdrawal (bank → cash) and a deposit (cash →
    // bank) are transfers too, not spending or earning (spec §6, §34).
    if (accounts.isComplete ||
        _matches(lower, r'\bmove\b') ||
        _containsAny(lower, [
          'transfer',
          'transferred',
          'moved',
          'withdrew',
          'withdraw',
          'withdrawn',
          'deposited',
          'deposit',
        ])) {
      return const _Classification(ActivityType.transfer, confidence: 0.9);
    }

    // "<person> owes me" states a receivable the user holds → recorded as a
    // loan out (spec §21 pairs with the "owes me" query).
    if (_matches(lower, r'\bowes?\s+me\b')) {
      return const _Classification(ActivityType.loanOut, confidence: 0.85);
    }

    // Loan repayments read as "someone paid someone back". Direction hinges
    // on who is the subject, so these are checked before plain lend/borrow.
    if (_matches(lower, r'\bpaid\b.*\bback\b') ||
        _containsAny(lower, ['repaid', 'paid back', 'pay back'])) {
      // "<person> paid me back" → they are repaying the user.
      if (_matches(lower, r'\bpaid\s+me\b') ||
          _matches(lower, r'\bpaid\s+me\s+back\b')) {
        return const _Classification(
          ActivityType.receivableRepayment,
          confidence: 0.9,
        );
      }
      // "I paid <person> back" → the user is repaying.
      return const _Classification(
        ActivityType.loanRepayment,
        confidence: 0.9,
      );
    }

    // Borrowing.
    if (_containsAny(lower, ['borrowed', 'i borrowed']) ||
        _matches(lower, r'\bloaned\s+me\b') ||
        _matches(lower, r'\blent\s+me\b') ||
        _matches(lower, r'\bborrow\b')) {
      return const _Classification(ActivityType.loanIn, confidence: 0.9);
    }

    // Lending.
    if (_matches(lower, r'\blent\b') ||
        _matches(lower, r'\bloaned\b') ||
        _matches(lower, r'\bas a loan\b') ||
        (_matches(lower, r'\bgave\b') && _matches(lower, r'\bloan\b'))) {
      return const _Classification(ActivityType.loanOut, confidence: 0.88);
    }

    // Income. 'refund' is deliberately absent — "refunded the customer" is
    // money going *out* — so a refund only reads as income via "received".
    if (_containsAny(lower, [
          'received', 'salary', 'earned', 'bonus', 'commission', 'dividend',
          'pension', 'allowance', 'stipend', 'grant', 'sold', 'selling',
        ]) ||
        _matches(lower, r'\bpaid\s+me\b') ||
        _matches(lower, r'\bgot\s+paid\b') ||
        _matches(lower, r'\bi made\b')) {
      // "paid me" without "back" is income; the back-case was handled above.
      return const _Classification(ActivityType.income, confidence: 0.82);
    }

    // "I got X from <person>" is the classic ambiguity; "I got X from
    // freelance work" (no person, but a source) is money received → income.
    if (_matches(lower, r'\bgot\b')) {
      if (hasPerson) {
        return const _Classification.ambiguous([
          ActivityType.income,
          ActivityType.loanIn,
          ActivityType.receivableRepayment,
        ]);
      }
      if (_matches(lower, r'\bfrom\b')) {
        return const _Classification(ActivityType.income, confidence: 0.7);
      }
    }

    // Explicit expense verbs.
    if (_containsAny(lower, [
      'spent',
      'paid',
      'bought',
      'buy',
      'purchased',
      'cost',
    ])) {
      return const _Classification(ActivityType.expense, confidence: 0.85);
    }

    // Bare "5000 lunch" — an amount and a noun, no verb: default to expense,
    // the overwhelmingly common case (spec §16, §38).
    return const _Classification(ActivityType.expense, confidence: 0.75);
  }

  /// For an ambiguous "I got X from someone": prefer a repayment/loan reading
  /// when a matching balance exists (spec §11), otherwise leave it ambiguous.
  ActivityType? _resolveAmbiguous(String? person, _Accounts accounts) {
    if (person == null) return null;
    final net = context.loanNetByPersonKey[person.toLowerCase()];
    if (net == null || net == 0) return null;
    // They owe the user (net > 0): receiving from them repays that receivable.
    if (net > 0) return ActivityType.receivableRepayment;
    // The user owes them (net < 0): receiving from them is a fresh loan in.
    return ActivityType.loanIn;
  }

  // ---------------------------------------------------------------------------
  // Amount & currency
  // ---------------------------------------------------------------------------

  _Money? _extractAmount(String lower) {
    // Matches: "5000", "35,000", "5k", "1.5m", "tsh 5,000", "tzs35000",
    final candidates = <_AmountCandidate>[];
    for (final match in _amountRegex.allMatches(lower)) {
      final raw = match.namedGroup('num')!;
      final grouped = raw.contains(',') || raw.contains(' ');
      final currency = match.namedGroup('cur')?.toLowerCase();
      final suffix = match.namedGroup('suf')?.toLowerCase();

      var value = double.tryParse(raw.replaceAll(RegExp(r'[,\s]'), ''));
      if (value == null || value <= 0) continue;
      if (suffix == 'k') value *= 1000;
      if (suffix == 'm') value *= 1000000;

      final windowStart = match.start - 15 < 0 ? 0 : match.start - 15;
      final preceding = lower.substring(windowStart, match.start);
      // A trailing "balance is TZS 120,000", or a reference/phone run after
      // "TID"/"ref", must never be mistaken for the transaction amount.
      if (preceding.contains('balance') || preceding.contains('bal.')) continue;
      if (RegExp(r'(tid|ref|txn|trans id|receipt no)\b').hasMatch(preceding)) {
        continue;
      }

      final digitLen = raw.replaceAll(RegExp(r'\D'), '').length;
      final flagged = grouped || currency != null || suffix != null;
      // An unflagged 12+ digit run is a phone number or reference, not money.
      final plausible = flagged || digitLen <= 7;
      final isYear =
          !flagged && digitLen == 4 && value >= 1900 && value <= 2099;

      candidates.add(
        _AmountCandidate(
          value: value,
          currency: currency == 'usd' ? 'USD' : 'TZS',
          flagged: flagged,
          plausible: plausible,
          isYear: isYear,
        ),
      );
    }

    if (candidates.isEmpty) return null;

    // A currency-tagged / comma-or-space-grouped / k-m amount is almost always
    // the real transaction value, so it wins over a bare quantity ("2 sodas
    // 6000") or a year ("rent for 2024 150000").
    final flagged = candidates.where((c) => c.flagged && c.plausible).toList();
    if (flagged.isNotEmpty) return _pickLargest(flagged);

    var pool = candidates.where((c) => c.plausible && !c.isYear).toList();
    if (pool.isEmpty) pool = candidates.where((c) => c.plausible).toList();
    if (pool.isEmpty) pool = candidates;
    return _pickLargest(pool);
  }

  /// The number pattern, shared shape documented at the call site. A negative
  /// lookahead after the optional k/m suffix stops it eating the first letter
  /// of a following word ("5000 milk" must not read as 5000·m = 5 billion).
  static final RegExp _amountRegex = RegExp(
    r'(?<cur>tsh|tzs|tshs|usd)?\s*'
    r'(?<num>\d{1,3}(?:[,\s]\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)'
    r'\s*(?<suf>k|m|/=|/-)?(?![a-z])',
    caseSensitive: false,
  );

  _Money _pickLargest(List<_AmountCandidate> pool) {
    var best = pool.first;
    for (final c in pool) {
      if (c.value > best.value) best = c;
    }
    return _Money(best.value, best.currency);
  }

  // ---------------------------------------------------------------------------
  // Dates
  // ---------------------------------------------------------------------------

  DateTime _extractDate(String lower) {
    final now = _now();
    if (_matches(lower, r'\byesterday\b')) {
      return now.subtract(const Duration(days: 1));
    }
    // "today" and anything unspecified default to now.
    return now;
  }

  // ---------------------------------------------------------------------------
  // People
  // ---------------------------------------------------------------------------

  static const _stopWords = {
    'i', 'me', 'my', 'you', 'to', 'from', 'for', 'on', 'the', 'a', 'an',
    'cash', 'bank', 'mpesa', 'card', 'loan', 'back', 'paid', 'pay', 'lent',
    'borrowed', 'received', 'got', 'gave', 'give', 'money', 'and', 'as',
    'salary', 'today', 'yesterday', 'tsh', 'tzs',
  };

  String? _extractPerson(String raw, String lower) {
    // Prefer a known person mentioned anywhere in the text.
    for (final person in context.people) {
      final key = person.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (RegExp(r'\b' + RegExp.escape(key) + r'\b').hasMatch(lower)) {
        return person.name;
      }
    }

    // Otherwise pull the word next to a relationship cue. The cue is what makes
    // it a person, so a lowercased name ("i lent john 5000") is accepted — the
    // cue "lent" is enough — and a following Capitalised word is folded in so a
    // two-part name survives ("Mary Jane").
    final tokens = RegExp(r"[A-Za-z][A-Za-z'\-]*").allMatches(raw).toList();
    for (var i = 0; i < tokens.length; i++) {
      final word = tokens[i].group(0)!;
      if (word.length < 2) continue;
      if (_stopWords.contains(word.toLowerCase())) continue;

      final before = i > 0 ? tokens[i - 1].group(0)!.toLowerCase() : '';
      final after =
          i + 1 < tokens.length ? tokens[i + 1].group(0)!.toLowerCase() : '';

      final cuedBefore = {
        'to', 'from', 'lent', 'loaned', 'borrowed', 'gave', 'give', 'owe',
        'owes',
      }.contains(before);
      // "paid John back", "John owe me", "John paid me" — the name sits next to
      // a relationship word.
      final cuedAfter = {
        'paid', 'owes', 'owe', 'loaned', 'lent', 'back',
      }.contains(after);
      if (!cuedBefore && !cuedAfter) continue;

      // A person's name is never a category word — "Rent paid 5000" has no
      // person, it's an ordinary expense whose subject happens to precede
      // "paid".
      if (_categoryWords.contains(word.toLowerCase())) continue;

      var name = _titleCase(word);
      // A second Capitalised token right after (and not a stop word) is part of
      // the name: "Mary Jane".
      if (i + 1 < tokens.length) {
        final next = tokens[i + 1].group(0)!;
        final nextIsName = next.length > 1 &&
            next[0].toUpperCase() == next[0] &&
            !_stopWords.contains(next.toLowerCase());
        if (cuedBefore && nextIsName) name = '$name ${_titleCase(next)}';
      }
      return name;
    }
    return null;
  }

  String _titleCase(String word) =>
      word[0].toUpperCase() + word.substring(1).toLowerCase();

  // ---------------------------------------------------------------------------
  // Transfer accounts
  // ---------------------------------------------------------------------------

  static const _accountAliases = {
    'bank': 'Bank',
    'mpesa': 'M-Pesa',
    'm-pesa': 'M-Pesa',
    'tigo pesa': 'Tigo Pesa',
    'tigopesa': 'Tigo Pesa',
    'airtel money': 'Airtel Money',
    'halopesa': 'HaloPesa',
    'savings': 'Savings',
    'cash': 'Cash',
    'wallet': 'Wallet',
  };

  _Accounts _extractTransferAccounts(String lower) {
    String? from;
    String? to;

    final fromMatch = RegExp(r'from\s+(?:my\s+)?([a-z\-]+(?:\s+[a-z]+)?)')
        .firstMatch(lower);
    if (fromMatch != null) from = _matchAccount(fromMatch.group(1)!);

    final toMatch = RegExp(r'to\s+(?:my\s+)?([a-z\-]+(?:\s+[a-z]+)?)')
        .firstMatch(lower);
    if (toMatch != null) to = _matchAccount(toMatch.group(1)!);

    return _Accounts(from, to);
  }

  String? _matchAccount(String phrase) {
    final trimmed = phrase.trim();
    for (final entry in _accountAliases.entries) {
      if (trimmed.startsWith(entry.key)) return entry.value;
    }
    // "savings account", "my account" → treat the leading word as the account.
    if (trimmed.contains('account')) {
      final word = trimmed.split(' ').first;
      if (word != 'account') {
        return word[0].toUpperCase() + word.substring(1);
      }
    }
    return null;
  }

  /// Resolves the "from/with/using" (source) and "to/into" (destination)
  /// account phrases to real account ids, against the user's actual accounts.
  (String?, String?) _resolveAccountIds(String lower) {
    final source = _matchAccountId(
      RegExp(
        r'\b(?:from|with|using|via|out of|paid with)\s+(?:my\s+)?'
        r'([a-z][a-z\-]*(?:\s+[a-z]+){0,2})',
      ).firstMatch(lower)?.group(1),
    );
    final dest = _matchAccountId(
      RegExp(
        r'\b(?:to|into)\s+(?:my\s+)?([a-z][a-z\-]*(?:\s+[a-z]+){0,2})',
      ).firstMatch(lower)?.group(1),
    );
    return (source, dest);
  }

  /// Matches a spoken account phrase against the user's accounts, longest
  /// prefix first ("nmb bank" before "nmb"), tolerating spaces/hyphens. Only
  /// fires on a real account name, so "from John" never mis-attributes.
  String? _matchAccountId(String? phrase) {
    if (phrase == null) return null;
    final words = phrase.trim().toLowerCase().split(RegExp(r'\s+'));
    for (var take = words.length; take >= 1; take--) {
      final cand = words.take(take).join(' ');
      final id =
          context.accountMatches[cand] ??
          context.accountMatches[cand.replaceAll(RegExp(r'[\s\-]'), '')];
      if (id != null) return id;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Payment method
  // ---------------------------------------------------------------------------

  PaymentMethod? _extractPaymentMethod(String lower) {
    if (_containsAny(lower, ['cash'])) return PaymentMethod.cash;
    if (_containsAny(lower, [
      'mpesa',
      'm-pesa',
      'mobile money',
      'tigo pesa',
      'airtel money',
      'halopesa',
    ])) {
      return PaymentMethod.mobileMoney;
    }
    if (_containsAny(lower, ['card', 'visa', 'mastercard'])) {
      return PaymentMethod.card;
    }
    if (_containsAny(lower, ['bank transfer', 'by bank', 'bank'])) {
      return PaymentMethod.bank;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  String? _extractProfile(String lower) {
    for (final entry in context.profileMatches.entries) {
      if (entry.key.isEmpty) continue;
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Category
  // ---------------------------------------------------------------------------

  /// Keyword → seed category id. Only used when that id is one the user has.
  static const _categoryKeywords = <String, List<String>>{
    'fuel': [
      'fuel', 'petrol', 'diesel', 'gas station', 'totalenergies', 'total',
      'oryx', 'puma energy', 'refuel', 'refuels', 'gasoline',
    ],
    'eating_out': [
      'lunch', 'dinner', 'breakfast', 'food', 'restaurant', 'eat', 'eating',
      'meal', 'chai', 'coffee', 'snack', 'mandazi', 'cafe', 'pizza', 'burger',
    ],
    'groceries': [
      'groceries', 'grocery', 'shoppers', 'supermarket', 'market', 'shoprite',
      'shop', 'vegetables', 'milk', 'bread',
    ],
    'transport': [
      'transport', 'daladala', 'bus', 'taxi', 'bajaji', 'uber', 'bolt', 'fare',
      'ride', 'boda', 'piki',
    ],
    'bills': [
      'electricity', 'luku', 'umeme', 'water', 'internet', 'wifi', 'bundle',
      'bundles', 'airtime', 'tigo', 'vodacom', 'halotel', 'bill', 'utility',
    ],
    'housing': ['rent', 'mortgage', 'landlord', 'house rent'],
    'subscriptions': [
      'netflix', 'spotify', 'subscription', 'chatgpt', 'openai', 'hosting',
      'domain', 'youtube', 'prime', 'icloud',
    ],
    'family': [
      'pharmacy', 'hospital', 'medicine', 'health', 'clinic', 'school',
      'fees', 'doctor', 'family',
    ],
  };

  /// Every category keyword, flattened — used to reject a "person" that is
  /// really a category word ("Rent", "Fuel").
  static final Set<String> _categoryWords =
      _categoryKeywords.values.expand((words) => words).toSet();

  String? _guessCategory(String lower, String? merchant) {
    // Learned merchant associations win — if this merchant was categorised
    // before, reuse that (spec §5). Match the exact merchant, or any learned
    // merchant name appearing in the text.
    if (context.merchantCategories.isNotEmpty) {
      if (merchant != null) {
        final learned = context.merchantCategories[merchant.toLowerCase()];
        if (learned != null && context.knownCategoryIds.contains(learned)) {
          return learned;
        }
      }
      for (final entry in context.merchantCategories.entries) {
        if (entry.key.length >= 3 &&
            lower.contains(entry.key) &&
            context.knownCategoryIds.contains(entry.value)) {
          return entry.value;
        }
      }
    }

    for (final entry in _categoryKeywords.entries) {
      if (!context.knownCategoryIds.contains(entry.key)) continue;
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Merchant & description
  // ---------------------------------------------------------------------------

  String? _extractMerchant(String raw, String lower) {
    // SMS-style "to MERCHANT NAME" / "at MERCHANT". A merchant is a run of
    // Capitalised words after the cue — "TOTALENERGIES MIKOCHENI" — and a
    // period or lowercase word ends the run, so "… MIKOCHENI. Your balance …"
    // stops cleanly at the merchant. "to"/"at" take priority over "paid" so a
    // currency token right after "paid" ("paid TZS 35,000") never wins.
    final pattern = RegExp(
      r'\b(?:to|at)\s+([A-Z][A-Za-z0-9&.\-]+(?:\s+[A-Z][A-Za-z0-9&.\-]+)*)',
    );

    for (final match in pattern.allMatches(raw)) {
      final candidate = match.group(1)!.trim();
      final lowerCandidate = candidate.toLowerCase();
      // Reject currency tokens and the user's own accounts.
      if (RegExp(r'^(tzs|tsh|tshs)\b').hasMatch(lowerCandidate)) continue;
      if (_accountAliases.containsKey(lowerCandidate)) continue;
      if (candidate.length < 3) continue;
      return candidate;
    }
    return null;
  }

  String _extractDescription(
    String raw,
    String lower,
    ActivityType type,
    String? person,
    _Money money,
  ) {
    // Loans read best as the relationship, handled by the UI; still capture a
    // sensible description for history.
    if (type.isLoanRelated && person != null) {
      switch (type) {
        case ActivityType.loanOut:
          return 'Lent to $person';
        case ActivityType.loanIn:
          return 'Loan from $person';
        case ActivityType.loanRepayment:
          return 'Repaid $person';
        case ActivityType.receivableRepayment:
          return '$person repaid you';
        default:
          break;
      }
    }

    // Strip amount tokens, currency, and leading verbs to leave the subject
    // ("I spent 5000 on lunch" → "lunch").
    var text = raw;
    text = text.replaceAll(
      RegExp(
        r'(?:tsh|tzs|tshs)?\s*\d[\d,\.]*\s*(?:k|m|/=|/-)?(?![a-z])',
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAll(
      RegExp(
        r'\b(i|you|we|spent|paid|bought|buy|purchased|received|got|for|on|'
        r'cash|with|by|salary|income|to|from|the|a|an|today|yesterday|'
        r'transferred|transfer|moved|lent|borrowed|loan)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (text.isEmpty) {
      // Fall back to type label or merchant.
      return type.label;
    }
    // Capitalise first letter.
    return text[0].toUpperCase() + text.substring(1);
  }

  // ---------------------------------------------------------------------------
  // Query parsing
  // ---------------------------------------------------------------------------

  bool _looksLikeQuery(String lower) {
    return _startsWithAny(lower, [
          'how much', 'how many', 'what did', 'what is', "what's", 'what do',
          'what will', 'show', 'list', 'when did',
        ]) ||
        _matches(lower, r'\bhow much (do|does|did)\b') ||
        _matches(lower, r'\b(do|does|did) i owe\b');
    // Note: a bare "owes me" is NOT a query trigger — "John owes me 5000" is a
    // statement that records a receivable. The question form always leads with
    // "how much …", caught above.
  }

  QueryIntent? _parseQuery(String raw, String lower) {
    final timeframe = _extractTimeframe(lower);

    // Owed / owing.
    if (_matches(lower, r'\bdo i owe\b') || _matches(lower, r'\bi owe\b')) {
      return QueryIntent(
        topic: QueryTopic.iOwe,
        personName: _extractPerson(raw, lower),
      );
    }
    if (_matches(lower, r'\bowes? me\b') || _matches(lower, r'\bowe me\b')) {
      return QueryIntent(
        topic: QueryTopic.owedToMe,
        personName: _extractPerson(raw, lower),
      );
    }

    // Biggest expenses.
    if (_containsAny(lower, ['biggest', 'largest', 'top expenses', 'most'])) {
      return QueryIntent(topic: QueryTopic.biggestExpenses, timeframe: timeframe.$1, month: timeframe.$2);
    }

    // Income.
    if (_containsAny(lower, ['income', 'earn', 'earned', 'made'])) {
      return QueryIntent(topic: QueryTopic.income, timeframe: timeframe.$1, month: timeframe.$2);
    }

    // Merchant ("expenses at TotalEnergies"). The name must be Capitalised, so
    // "at the market" falls through to the category check (market = groceries)
    // instead of being read as a merchant called "the market".
    final atMatch = RegExp(r'\bat\s+([A-Z][A-Za-z0-9&.\- ]{2,40})')
        .firstMatch(raw);
    if (atMatch != null) {
      return QueryIntent(
        topic: QueryTopic.merchantSpend,
        merchant: atMatch.group(1)!.trim(),
        timeframe: timeframe.$1,
        month: timeframe.$2,
      );
    }

    // Category spend ("spend on fuel").
    final categoryId = _guessCategory(lower, null);
    if (categoryId != null) {
      return QueryIntent(
        topic: QueryTopic.categorySpend,
        categoryId: categoryId,
        timeframe: timeframe.$1,
        month: timeframe.$2,
      );
    }

    // Fall back to total spending.
    if (_containsAny(lower, [
      'spend', 'spent', 'spending', 'cost', 'expense', 'expenses',
    ])) {
      return QueryIntent(
        topic: QueryTopic.totalSpend,
        timeframe: timeframe.$1,
        month: timeframe.$2,
      );
    }

    return null;
  }

  (Timeframe, int?) _extractTimeframe(String lower) {
    if (_matches(lower, r'\bthis month\b')) return (Timeframe.thisMonth, null);
    if (_matches(lower, r'\blast month\b')) return (Timeframe.lastMonth, null);
    if (_matches(lower, r'\btoday\b')) return (Timeframe.today, null);
    if (_matches(lower, r'\byesterday\b')) return (Timeframe.yesterday, null);

    const months = [
      'january', 'february', 'march', 'april', 'may', 'june', 'july',
      'august', 'september', 'october', 'november', 'december',
    ];
    for (var i = 0; i < months.length; i++) {
      if (_matches(lower, r'\b' + months[i] + r'\b')) {
        return (Timeframe.specificMonth, i + 1);
      }
    }
    return (Timeframe.thisMonth, null);
  }

  // ---------------------------------------------------------------------------
  // Plan parsing
  // ---------------------------------------------------------------------------

  bool _looksLikePlan(String lower) {
    return _startsWithAny(lower, ['if', 'what if']) ||
        _matches(lower, r'\bwhat if\b') ||
        (_matches(lower, r'\bif i\b') && _containsAny(lower, ['spend', 'drive', 'reduce'])) ||
        _matches(lower, r'\bwill (i |it )?cost\b');
  }

  PlanIntent? _parsePlan(String raw, String lower) {
    final categoryId = _guessCategory(lower, null);

    // Fuel driving simulation.
    if (_containsAny(lower, ['drive', 'driving', 'km', 'kilomet'])) {
      final distance = _firstNumberBefore(lower, ['km', 'kilomet']);
      return PlanIntent(
        topic: PlanTopic.fuel,
        distancePerDay: distance,
        categoryId: 'fuel',
      );
    }

    // Reduce / what-if comparison.
    if (_containsAny(lower, ['reduce', 'cut', 'instead of', 'to ']) &&
        _containsAny(lower, ['reduce', 'what if', 'cut'])) {
      final amounts = _allAmounts(lower);
      return PlanIntent(
        topic: PlanTopic.reduce,
        dailyAmount: amounts.isNotEmpty ? amounts.first : null,
        newAmount: amounts.length > 1 ? amounts.last : null,
        categoryId: categoryId,
      );
    }

    // Plain daily-habit projection.
    final money = _extractAmount(lower);
    if (money != null) {
      return PlanIntent(
        topic: PlanTopic.dailyHabit,
        dailyAmount: money.amount,
        categoryId: categoryId,
      );
    }
    return null;
  }

  double? _firstNumberBefore(String lower, List<String> units) {
    for (final unit in units) {
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*' + unit).firstMatch(lower);
      if (match != null) return double.tryParse(match.group(1)!);
    }
    return null;
  }

  List<double> _allAmounts(String lower) {
    // The `(?![a-z])` guard mirrors _amountRegex: without it a trailing word
    // donates its leading k/m as a multiplier ("3000 monthly" → 3,000,000,000).
    final regex = RegExp(
      r'(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(k|m)?(?![a-z])',
      caseSensitive: false,
    );
    final result = <double>[];
    for (final match in regex.allMatches(lower)) {
      var value = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (value == null) continue;
      final suffix = match.group(2)?.toLowerCase();
      if (suffix == 'k') value *= 1000;
      if (suffix == 'm') value *= 1000000;
      // Ignore small integers that are likely percentages or "20%".
      if (value >= 100) result.add(value);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  bool _containsAny(String text, List<String> needles) =>
      needles.any(text.contains);

  bool _startsWithAny(String text, List<String> prefixes) =>
      prefixes.any(text.startsWith);

  bool _matches(String text, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(text);

  /// Overridable clock seam so tests get deterministic dates.
  DateTime _now() => clock?.call() ?? DateTime.now();

  /// Test seam; null in production.
  static DateTime Function()? clock;
}

enum _Origin { command, paste }

class _Money {
  const _Money(this.amount, this.currency);
  final double amount;
  final String currency;
}

class _AmountCandidate {
  const _AmountCandidate({
    required this.value,
    required this.currency,
    required this.flagged,
    required this.plausible,
    required this.isYear,
  });

  final double value;
  final String currency;

  /// Currency-tagged, thousands-grouped, or k/m-suffixed — a strong signal
  /// this is the real amount rather than an incidental number.
  final bool flagged;

  /// Not an implausibly long unflagged run (phone number / reference).
  final bool plausible;

  /// A bare four-digit year, deprioritised when a real amount is also present.
  final bool isYear;
}

class _Accounts {
  const _Accounts(this.from, this.to);
  final String? from;
  final String? to;
  bool get isComplete => from != null && to != null;
}

class _Classification {
  const _Classification(this.type, {this.confidence = 0.8})
    : ambiguous = false,
      candidates = const [];

  const _Classification.ambiguous(this.candidates)
    : type = ActivityType.expense,
      confidence = 0.4,
      ambiguous = true;

  final ActivityType type;
  final double confidence;
  final bool ambiguous;
  final List<ActivityType> candidates;
}
