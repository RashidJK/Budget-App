import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:uuid/uuid.dart';

import '../command/command_parser.dart';
import '../models/account.dart';
import '../models/phosphor.dart';
import '../models/activity.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../models/palette.dart';
import '../models/person.dart';
import '../models/profile.dart';
import '../models/scenario.dart';
import '../services/storage.dart';
import '../sync/merge.dart';

const _uuid = Uuid();

/// Owns every persisted collection and notifies the UI when they change.
class AppState extends ChangeNotifier {
  AppState(this._storage) {
    _load();
  }

  final Storage _storage;

  List<Expense> _expenses = [];
  List<Scenario> _scenarios = [];
  List<ExpenseCategory> _categories = [];
  List<Profile> _profiles = [];
  List<Account> _accounts = [];
  List<Activity> _activities = [];
  List<Person> _people = [];

  /// Learned merchant → category id, so a merchant seen before auto-categorises.
  Map<String, String> _merchantCategories = {};

  /// The profile the dashboard and lists are scoped to. Null means all.
  String? _activeProfileId;

  List<Expense> get expenses => List.unmodifiable(_expenses);
  List<Scenario> get scenarios => List.unmodifiable(_scenarios);
  List<ExpenseCategory> get categories => List.unmodifiable(_categories);
  List<Profile> get profiles => List.unmodifiable(_profiles);

  /// Live (non-deleted) non-expense activities, newest first.
  List<Activity> get activities => List.unmodifiable(
    _activities.where((a) => !a.isDeleted).toList()
      ..sort((a, b) => b.date.compareTo(a.date)),
  );

  List<Person> get people => List.unmodifiable(
    _people.where((p) => !p.isDeleted).toList(),
  );

  String? get activeProfileId => _activeProfileId;

  Profile? get activeProfile => profileById(_activeProfileId);

  void _load() {
    // A first launch has no categories or profiles; without a starter set the
    // user would face an expense form with an empty category picker.
    if (_storage.isFirstLaunch) {
      _categories = List.of(ExpenseCategory.seed);
      _profiles = List.of(Profile.seed);
      unawaited(_persistCategories(notify: false));
      unawaited(_persistProfiles(notify: false));
    } else {
      _categories = _storage
          .readCategories()
          .map(ExpenseCategory.fromJson)
          .toList();
      _profiles = _storage.readProfiles().map(Profile.fromJson).toList();

      // Deleting the last of either would leave the app unusable.
      if (_categories.isEmpty) _categories = List.of(ExpenseCategory.seed);
      if (_profiles.isEmpty) _profiles = List.of(Profile.seed);
    }

    _expenses = _storage.readExpenses().map(Expense.fromJson).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    _scenarios = _storage.readScenarios().map(Scenario.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    _activities = _storage.readActivities().map(Activity.fromJson).toList();
    _people = _storage.readPeople().map(Person.fromJson).toList();
    _merchantCategories = _storage.readMerchantCategories();

    // Accounts arrived after the first versions, so seed a default "Cash"
    // account whenever none exist (fresh install or an upgrade). Records with
    // no accountId resolve to it, so historical data still balances.
    _accounts = _storage.readAccounts().map(Account.fromJson).toList();
    if (_accounts.where((a) => !a.isDeleted).isEmpty) {
      _accounts = List.of(Account.seed);
      unawaited(_persistAccounts(notify: false));
    }

    _activeProfileId = _storage.readActiveProfile();
  }

  // -------------------------------------------------------------------------
  // Lookups
  // -------------------------------------------------------------------------

  /// Resolves a category id, falling back to a neutral placeholder so an
  /// expense whose category was deleted still renders.
  ExpenseCategory categoryById(String? id) {
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return ExpenseCategory.unknown;
  }

  Profile? profileById(String? id) {
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Expense? expenseById(String? id) {
    if (id == null) return null;
    for (final expense in _expenses) {
      if (expense.id == id) return expense;
    }
    return null;
  }

  /// The profile new expenses default to.
  String get defaultProfileId =>
      _activeProfileId ??
      (_profiles.isEmpty ? Profile.personalId : _profiles.first.id);

  // -------------------------------------------------------------------------
  // Profiles
  // -------------------------------------------------------------------------

  Future<void> setActiveProfile(String? id) async {
    _activeProfileId = id;
    notifyListeners();
    await _storage.writeActiveProfile(id);
  }

  Future<void> addProfile({
    required String name,
    required String iconName,
    int? colorSlot,
    bool isBusiness = false,
  }) async {
    _profiles = [
      ..._profiles,
      Profile(
        id: _uuid.v4(),
        name: name,
        iconName: iconName,
        colorSlot:
            colorSlot ?? Palette.firstFree(_profiles.map((p) => p.colorSlot)),
        isBusiness: isBusiness,
      ),
    ];
    await _persistProfiles();
  }

  Future<void> updateProfile(Profile profile) async {
    final index = _profiles.indexWhere((item) => item.id == profile.id);
    if (index == -1) return;

    _profiles = [..._profiles]..[index] = profile;
    await _persistProfiles();
  }

  /// Deletes a profile and moves its expenses to [reassignTo].
  ///
  /// Expenses are never deleted as a side effect of removing a profile — that
  /// would destroy records the user didn't ask to lose.
  Future<void> deleteProfile(String id, {required String reassignTo}) async {
    if (_profiles.length <= 1) return;

    _profiles = _profiles.where((profile) => profile.id != id).toList();
    _expenses = _expenses
        .map(
          (expense) => expense.profileId == id
              ? expense.copyWith(profileId: reassignTo)
              : expense,
        )
        .toList();

    if (_activeProfileId == id) {
      _activeProfileId = null;
      await _storage.writeActiveProfile(null);
    }

    await _persistProfiles(notify: false);
    await _persistExpenses();
  }

  Future<void> _persistProfiles({bool notify = true}) async {
    if (notify) notifyListeners();
    await _storage.writeProfiles(
      _profiles.map((profile) => profile.toJson()).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Accounts & balances — where the money is, not just where it went.
  // -------------------------------------------------------------------------

  /// Live accounts, in creation order.
  List<Account> get accounts =>
      List.unmodifiable(_accounts.where((a) => !a.isDeleted));

  Account? accountById(String? id) {
    if (id == null) return null;
    for (final account in _accounts) {
      if (account.id == id && !account.isDeleted) return account;
    }
    return null;
  }

  /// The account new records land in and old records resolve to.
  String get defaultAccountId {
    final live = accounts;
    if (live.any((a) => a.id == Account.defaultId)) return Account.defaultId;
    return live.isEmpty ? Account.defaultId : live.first.id;
  }

  Future<void> addAccount({
    required String name,
    required AccountType type,
    double openingBalance = 0,
    int? colorSlot,
  }) async {
    _accounts = [
      ..._accounts,
      Account(
        id: _uuid.v4(),
        name: name,
        type: type,
        openingBalance: openingBalance,
        colorSlot: colorSlot ?? Palette.firstFree(_accountColorSlots),
        updatedAt: DateTime.now(),
      ),
    ];
    await _persistAccounts();
  }

  Future<void> updateAccount(Account account) async {
    final index = _accounts.indexWhere((item) => item.id == account.id);
    if (index == -1) return;
    _accounts = [..._accounts]..[index] = account;
    await _persistAccounts();
  }

  /// Deletes an account (tombstoned). Records that named it fall back to the
  /// default account for balance purposes, so nothing is orphaned.
  Future<void> deleteAccount(String id) async {
    if (accounts.length <= 1) return; // never leave zero accounts
    final index = _accounts.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _accounts = [..._accounts]..[index] = _accounts[index].tombstone();
    await _persistAccounts();
  }

  Iterable<int> get _accountColorSlots =>
      accounts.map((a) => a.colorSlot).whereType<int>();

  /// Current balance of one account: its opening balance plus every attributed
  /// movement. Global (not profile-scoped) — cash on hand is cash on hand.
  double accountBalance(String accountId) {
    final fallback = defaultAccountId;
    var balance = accountById(accountId)?.openingBalance ?? 0;

    for (final expense in _expenses) {
      if (expense.isDeleted) continue;
      if ((expense.accountId ?? fallback) == accountId) {
        balance -= expense.amount;
      }
    }
    for (final activity in _activities) {
      if (activity.isDeleted) continue;
      balance += activity.cashDeltaFor(accountId, fallback);
    }
    return balance;
  }

  /// Every account with its current balance, largest first.
  List<AccountBalance> get accountBalances {
    final result = [
      for (final account in accounts)
        AccountBalance(account: account, balance: accountBalance(account.id)),
    ];
    result.sort((a, b) => b.balance.compareTo(a.balance));
    return result;
  }

  /// Total money on hand across every account.
  double get totalBalance =>
      accounts.fold<double>(0, (sum, a) => sum + accountBalance(a.id));

  /// The account's own ledger — every expense and activity that touched it,
  /// signed from its point of view, newest first. This is what the account
  /// detail screen lists; balances above are just its running sum.
  List<AccountMovement> accountMovements(String accountId) {
    final fallback = defaultAccountId;
    final out = <AccountMovement>[];

    for (final expense in _expenses) {
      if (expense.isDeleted) continue;
      if ((expense.accountId ?? fallback) != accountId) continue;
      final category = categoryById(expense.categoryId);
      out.add(
        AccountMovement(
          date: expense.date,
          title: expense.title.isEmpty ? category.name : expense.title,
          subtitle: category.name,
          delta: -expense.amount,
          icon: category.icon,
        ),
      );
    }

    for (final activity in _activities) {
      if (activity.isDeleted) continue;
      final delta = activity.cashDeltaFor(accountId, fallback);
      if (delta == 0) continue;
      out.add(
        AccountMovement(
          date: activity.date,
          title: _movementTitle(activity, accountId, fallback),
          subtitle: activity.type.label,
          delta: delta,
          icon: _movementIcon(activity.type),
        ),
      );
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Money in vs out of [accountId] during [month].
  AccountFlow accountFlow(String accountId, DateTime month) {
    var inflow = 0.0;
    var outflow = 0.0;
    for (final movement in accountMovements(accountId)) {
      if (movement.date.year != month.year ||
          movement.date.month != month.month) {
        continue;
      }
      if (movement.delta >= 0) {
        inflow += movement.delta;
      } else {
        outflow += -movement.delta;
      }
    }
    return AccountFlow(inflow: inflow, outflow: outflow);
  }

  String _movementTitle(Activity activity, String accountId, String fallback) {
    switch (activity.type) {
      case ActivityType.transfer:
        final isSource = (activity.accountId ?? fallback) == accountId;
        final other = isSource
            ? (activity.toAccountId ?? fallback)
            : (activity.accountId ?? fallback);
        final name = accountById(other)?.name ?? 'account';
        return isSource ? 'Transfer to $name' : 'Transfer from $name';
      case ActivityType.income:
        return activity.description.isEmpty ? 'Income' : activity.description;
      case ActivityType.expense:
        return activity.description.isEmpty ? 'Expense' : activity.description;
      case ActivityType.loanOut:
      case ActivityType.loanIn:
      case ActivityType.loanRepayment:
      case ActivityType.receivableRepayment:
        final who = personById(activity.personId)?.name ?? 'someone';
        return switch (activity.type) {
          ActivityType.loanOut => 'Lent $who',
          ActivityType.loanIn => 'Borrowed from $who',
          ActivityType.loanRepayment => 'Repaid $who',
          ActivityType.receivableRepayment => '$who repaid you',
          _ => activity.type.label,
        };
    }
  }

  IconData _movementIcon(ActivityType type) => switch (type) {
    ActivityType.transfer => PhosphorR.arrowsLeftRight,
    ActivityType.income => PhosphorR.coins,
    ActivityType.expense => PhosphorR.receipt,
    ActivityType.loanOut ||
    ActivityType.loanIn ||
    ActivityType.loanRepayment ||
    ActivityType.receivableRepayment => PhosphorR.users,
  };

  Future<void> _persistAccounts({bool notify = true}) async {
    if (notify) notifyListeners();
    await _storage.writeAccounts(
      _accounts.map((account) => account.toJson()).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------------------

  /// Slots already spoken for, so the picker can show what is free.
  Set<int> get usedColorSlots => _categories
      .map((category) => category.colorSlot)
      .whereType<int>()
      .toSet();

  Future<void> addCategory({
    required String name,
    required String iconName,
    int? colorSlot,
    double? monthlyBudget,
  }) async {
    _categories = [
      ..._categories,
      ExpenseCategory(
        id: _uuid.v4(),
        name: name,
        iconName: iconName,
        // Past the palette's capacity this stays null and the category renders
        // neutral, rather than inventing an indistinguishable ninth hue.
        colorSlot: colorSlot ?? Palette.firstFree(usedColorSlots),
        monthlyBudget: monthlyBudget,
        updatedAt: DateTime.now(),
      ),
    ];
    await _persistCategories();
  }

  Future<void> updateCategory(ExpenseCategory category) async {
    final index = _categories.indexWhere((item) => item.id == category.id);
    if (index == -1) return;

    _categories = [..._categories]..[index] = category;
    await _persistCategories();
  }

  /// Deletes a category and moves its expenses to [reassignTo].
  Future<void> deleteCategory(String id, {required String reassignTo}) async {
    if (_categories.length <= 1) return;

    _categories = _categories.where((category) => category.id != id).toList();
    _expenses = _expenses
        .map(
          (expense) => expense.categoryId == id
              ? expense.copyWith(categoryId: reassignTo)
              : expense,
        )
        .toList();

    await _persistCategories(notify: false);
    await _persistExpenses();
  }

  /// How many expenses would be reassigned if [id] were deleted.
  int expenseCountForCategory(String id) =>
      _expenses.where((expense) => expense.categoryId == id).length;

  int expenseCountForProfile(String id) =>
      _expenses.where((expense) => expense.profileId == id).length;

  Future<void> _persistCategories({bool notify = true}) async {
    if (notify) notifyListeners();
    await _storage.writeCategories(
      _categories.map((category) => category.toJson()).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Expenses
  // -------------------------------------------------------------------------

  Future<void> addExpense({
    required String title,
    required double amount,
    required String categoryId,
    required DateTime date,
    String? profileId,
    String? accountId,
    String note = '',
    List<String> attachments = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    _expenses = [
      Expense(
        id: _uuid.v4(),
        title: title,
        amount: amount,
        categoryId: categoryId,
        profileId: profileId ?? defaultProfileId,
        accountId: accountId ?? defaultAccountId,
        date: date,
        updatedAt: DateTime.now(),
        note: note,
        attachments: attachments,
        metadata: metadata,
      ),
      ..._expenses,
    ]..sort((a, b) => b.date.compareTo(a.date));

    await _persistExpenses();
  }

  Future<void> updateExpense(Expense expense) async {
    final index = _expenses.indexWhere((item) => item.id == expense.id);
    if (index == -1) return;

    _expenses = [..._expenses]
      ..[index] = expense
      ..sort((a, b) => b.date.compareTo(a.date));

    await _persistExpenses();
  }

  Future<void> deleteExpense(
    String id, {
    bool discardAttachments = true,
  }) async {
    final matches = _expenses.where((item) => item.id == id);
    final expense = matches.isEmpty ? null : matches.first;

    _expenses = _expenses.where((item) => item.id != id).toList();
    await _persistExpenses();

    // Orphaned receipts would otherwise sit in the documents directory for
    // good. Skipped when the deletion is undoable, so Undo can restore them.
    if (discardAttachments && expense != null) {
      for (final path in expense.attachments) {
        unawaited(AttachmentStore.discard(path));
      }
    }
  }

  /// Re-inserts a deleted expense, preserving its original id and receipts.
  Future<void> restoreExpense(Expense expense) async {
    _expenses = [expense, ..._expenses]
      ..sort((a, b) => b.date.compareTo(a.date));
    await _persistExpenses();
  }

  Future<void> _persistExpenses() async {
    notifyListeners();
    await _storage.writeExpenses(
      _expenses.map((expense) => expense.toJson()).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Queries
  // -------------------------------------------------------------------------

  /// Expenses in the active profile. Everything on the dashboard reads from
  /// here, so switching profile rescopes the whole screen.
  List<Expense> get scopedExpenses {
    if (_activeProfileId == null) return _expenses;
    return _expenses
        .where((expense) => expense.profileId == _activeProfileId)
        .toList();
  }

  List<Expense> search(ExpenseFilter filter) =>
      _expenses.where(filter.matches).toList();

  List<Expense> expensesInMonth(DateTime month) {
    return scopedExpenses
        .where(
          (expense) =>
              expense.date.year == month.year &&
              expense.date.month == month.month,
        )
        .toList();
  }

  double totalFor(Iterable<Expense> expenses) =>
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount);

  double get spentThisMonth => totalFor(expensesInMonth(DateTime.now()));

  double get spentLastMonth {
    final now = DateTime.now();
    return totalFor(expensesInMonth(DateTime(now.year, now.month - 1)));
  }

  /// Totals by category for [month], largest first, excluding empty
  /// categories so the breakdown only lists things actually spent on.
  List<CategoryTotal> categoryTotals(DateTime month) {
    final totals = <String, double>{};
    for (final expense in expensesInMonth(month)) {
      totals[expense.categoryId] =
          (totals[expense.categoryId] ?? 0) + expense.amount;
    }

    return totals.entries
        .map(
          (entry) => CategoryTotal(
            category: categoryById(entry.key),
            total: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }


  /// Total spend per calendar month for the last [months] months, oldest
  /// first, empty months included so the trend chart keeps an even axis.
  List<MonthTotal> monthlyTotals({int months = 6}) {
    final now = DateTime.now();
    final result = <MonthTotal>[];

    for (var offset = months - 1; offset >= 0; offset--) {
      final month = DateTime(now.year, now.month - offset);
      result.add(
        MonthTotal(month: month, total: totalFor(expensesInMonth(month))),
      );
    }
    return result;
  }

  /// Budget progress for every category that has a limit, this month.
  ///
  /// Sorted by how close to (or past) the limit each is, so the categories
  /// that need attention sit at the top. Scoped to the active profile like
  /// everything else on the dashboard.
  List<BudgetProgress> budgetProgress([DateTime? month]) {
    final target = month ?? DateTime.now();
    final spentByCategory = <String, double>{};
    for (final expense in expensesInMonth(target)) {
      spentByCategory[expense.categoryId] =
          (spentByCategory[expense.categoryId] ?? 0) + expense.amount;
    }

    final result = _categories
        .where((category) => category.hasBudget)
        .map(
          (category) => BudgetProgress(
            category: category,
            spent: spentByCategory[category.id] ?? 0,
            budget: category.monthlyBudget!,
          ),
        )
        .toList()
      ..sort((a, b) => b.fraction.compareTo(a.fraction));

    return result;
  }

  bool get hasAnyBudget => _categories.any((category) => category.hasBudget);

  /// Days left in the current month, for "X days to go" on budget cards.
  int get daysLeftThisMonth {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return lastDay - now.day;
  }

  /// Highest single expense this month, for the analytics stat tiles.
  Expense? get biggestExpenseThisMonth {
    final expenses = expensesInMonth(DateTime.now());
    if (expenses.isEmpty) return null;
    return expenses.reduce((a, b) => a.amount >= b.amount ? a : b);
  }

  /// Mean spend per day so far this month.
  double get dailyAverageThisMonth {
    final now = DateTime.now();
    return spentThisMonth / now.day;
  }

  /// Spend recorded today — the tightest window on the snapshot row.
  double get spentToday => spentInLastDays(1);

  /// Projected month-end spend if the current daily pace holds. A forward read
  /// to sit beside the actuals; always ≥ [spentThisMonth] since the remaining
  /// days can only add to the total.
  double get projectedThisMonth {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return dailyAverageThisMonth * daysInMonth;
  }

  /// Number of expenses logged this month, for the "entries" snapshot.
  int get expenseCountThisMonth => expensesInMonth(DateTime.now()).length;

  /// Spend over the last [days] days including today, for the "this week"
  /// snapshot. A rolling window rather than a calendar week — "the last seven
  /// days" is what people mean by "this week's spending".
  double spentInLastDays(int days) {
    final today = DateTime.now();
    final cutoff = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: days - 1));

    return totalFor(
      scopedExpenses.where((expense) => !expense.date.isBefore(cutoff)),
    );
  }

  /// The largest category this month, or null when nothing is spent.
  CategoryTotal? get topCategoryThisMonth {
    final totals = categoryTotals(DateTime.now());
    return totals.isEmpty ? null : totals.first;
  }

  // -------------------------------------------------------------------------
  // Scenarios
  // -------------------------------------------------------------------------

  Scenario? scenarioById(String? id) {
    if (id == null) return null;
    for (final scenario in _scenarios) {
      if (scenario.id == id) return scenario;
    }
    return null;
  }

  Future<Scenario> saveScenario({
    required String name,
    required ScenarioKind kind,
    required Map<String, dynamic> data,
  }) async {
    final now = DateTime.now();
    final scenario = Scenario(
      id: _uuid.v4(),
      name: name,
      kind: kind,
      data: data,
      createdAt: now,
      updatedAt: now,
    );

    _scenarios = [scenario, ..._scenarios];
    await _persistScenarios();
    return scenario;
  }

  Future<void> updateScenario(
    String id, {
    String? name,
    Map<String, dynamic>? data,
  }) async {
    final index = _scenarios.indexWhere((scenario) => scenario.id == id);
    if (index == -1) return;

    _scenarios = [..._scenarios]
      ..[index] = _scenarios[index].copyWith(
        name: name,
        data: data,
        updatedAt: DateTime.now(),
      );
    _scenarios.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await _persistScenarios();
  }

  Future<Scenario?> duplicateScenario(String id) async {
    final source = scenarioById(id);
    if (source == null) return null;

    return saveScenario(
      name: _uniqueName('${source.name} (copy)'),
      kind: source.kind,
      data: Map<String, dynamic>.from(source.data),
    );
  }

  Future<void> deleteScenario(String id) async {
    _scenarios = _scenarios.where((scenario) => scenario.id != id).toList();
    await _persistScenarios();
  }

  /// Appends a counter until the name is free, so duplicating twice doesn't
  /// leave two identically-named scenarios the user can't tell apart.
  String _uniqueName(String preferred) {
    final taken = _scenarios.map((scenario) => scenario.name).toSet();
    if (!taken.contains(preferred)) return preferred;

    for (var suffix = 2; suffix < 100; suffix++) {
      final candidate = '$preferred $suffix';
      if (!taken.contains(candidate)) return candidate;
    }
    return preferred;
  }

  Future<void> _persistScenarios() async {
    notifyListeners();
    await _storage.writeScenarios(
      _scenarios.map((scenario) => scenario.toJson()).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Command parsing context
  // -------------------------------------------------------------------------

  /// A snapshot of everything the parser needs to resolve context — known
  /// people and their balances, categories, profile aliases (spec §37 rule 2).
  ParseContext parseContext() {
    final loanNet = <String, double>{};
    for (final person in people) {
      loanNet[person.matchKey] = balanceWith(person.id);
    }

    return ParseContext(
      people: people.map((p) => (id: p.id, name: p.name)).toList(),
      loanNetByPersonKey: loanNet,
      knownCategoryIds: _categories.map((c) => c.id).toSet(),
      profileMatches: {
        for (final profile in _profiles) profile.name.toLowerCase(): profile.id,
      },
      accountMatches: _accountMatches(),
      merchantCategories: Map.of(_merchantCategories),
      defaultProfileId: defaultProfileId,
    );
  }

  /// Spoken account names/aliases → id, so the parser can attribute "from
  /// M-Pesa". Each account is matched by its own name (spaces/hyphens squashed)
  /// and by the common spoken aliases for its type.
  Map<String, String> _accountMatches() {
    final map = <String, String>{};
    void add(String key, String id) {
      final k = key.toLowerCase();
      map.putIfAbsent(k, () => id);
      map.putIfAbsent(k.replaceAll(RegExp(r'[\s\-]'), ''), () => id);
    }

    for (final account in accounts) {
      add(account.name, account.id);
      switch (account.type) {
        case AccountType.cash:
          add('cash', account.id);
        case AccountType.mobileMoney:
          for (final a in ['mpesa', 'm-pesa', 'mobile money', 'mobile']) {
            add(a, account.id);
          }
        case AccountType.bank:
          add('bank', account.id);
        case AccountType.card:
          for (final a in ['card', 'credit card', 'visa']) {
            add(a, account.id);
          }
        case AccountType.other:
          break;
      }
    }
    return map;
  }

  /// Remembers that [merchant] was filed under [categoryId], so the next
  /// capture mentioning it is categorised automatically (spec §5).
  Future<void> learnMerchant(String merchant, String categoryId) async {
    final key = merchant.trim().toLowerCase();
    if (key.isEmpty || _merchantCategories[key] == categoryId) return;
    _merchantCategories = {..._merchantCategories, key: categoryId};
    await _storage.writeMerchantCategories(_merchantCategories);
  }

  // -------------------------------------------------------------------------
  // Capture (spec §29–§32): persist a parsed command as the right record
  // -------------------------------------------------------------------------

  /// Records a parsed activity, routing an expense into the existing expense
  /// pipeline (so it shows on the dashboard, budgets and analytics unchanged)
  /// and everything else into the activity ledger. Returns a handle the UI can
  /// use to Undo (spec §32).
  Future<CaptureResult> capture(
    ParsedActivity parsed, {
    ActivitySource source = ActivitySource.command,
    double? confidence,
  }) async {
    // A parsed field the app was unsure of leaves the record "needs review"
    // rather than blocking the save (spec §19, §20).
    final status = (confidence != null && confidence < 0.75)
        ? ActivityStatus.needsReview
        : ActivityStatus.recorded;

    if (parsed.type == ActivityType.expense) {
      final id = _uuid.v4();
      final expense = Expense(
        id: id,
        title: parsed.description.isNotEmpty
            ? parsed.description
            : (parsed.merchant ?? 'Expense'),
        amount: parsed.amount,
        categoryId: parsed.categoryId ?? 'other',
        profileId: parsed.profileId ?? defaultProfileId,
        accountId: parsed.accountId ?? defaultAccountId,
        date: parsed.date,
        updatedAt: DateTime.now(),
        note: parsed.merchant != null && parsed.description != parsed.merchant
            ? parsed.merchant!
            : '',
      );
      _expenses = [expense, ..._expenses]
        ..sort((a, b) => b.date.compareTo(a.date));
      await _persistExpenses();
      // Learn the merchant→category association for next time.
      if (parsed.merchant != null && parsed.categoryId != null) {
        await learnMerchant(parsed.merchant!, parsed.categoryId!);
      }
      return CaptureResult(isExpense: true, id: id);
    }

    String? personId;
    if (parsed.personName != null && parsed.personName!.trim().isNotEmpty) {
      personId = (await resolvePerson(parsed.personName!)).id;
    }

    final activity = Activity(
      id: _uuid.v4(),
      type: parsed.type,
      amount: parsed.amount,
      date: parsed.date,
      updatedAt: DateTime.now(),
      description: parsed.description,
      categoryId: parsed.categoryId,
      profileId: parsed.profileId ?? defaultProfileId,
      accountId: parsed.accountId ?? defaultAccountId,
      toAccountId: parsed.toAccountId,
      paymentMethod: parsed.paymentMethod,
      sourceAccount: parsed.sourceAccount,
      destinationAccount: parsed.destinationAccount,
      merchant: parsed.merchant,
      personId: personId,
      status: status,
      confidence: confidence,
      source: source,
    );
    await addActivity(activity);
    return CaptureResult(isExpense: false, id: activity.id);
  }

  /// Reverses a [capture], for the Undo action.
  Future<void> undoCapture(CaptureResult result) async {
    if (result.isExpense) {
      await deleteExpense(result.id, discardAttachments: false);
    } else {
      await deleteActivity(result.id);
    }
  }

  // -------------------------------------------------------------------------
  // Activities (income, transfers, loans, repayments)
  // -------------------------------------------------------------------------

  Future<Activity> addActivity(Activity activity) async {
    _activities = [activity, ..._activities];
    await _persistActivities();
    return activity;
  }

  Future<void> updateActivity(Activity activity) async {
    final index = _activities.indexWhere((item) => item.id == activity.id);
    if (index == -1) return;
    _activities = [..._activities]..[index] = activity;
    await _persistActivities();
  }

  /// Soft-deletes via a tombstone so the delete can replicate, but keeps Undo
  /// cheap — restoring is a second update, not a re-insert.
  Future<void> deleteActivity(String id) async {
    final index = _activities.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _activities = [..._activities]..[index] = _activities[index].tombstone();
    await _persistActivities();
  }

  Future<void> restoreActivity(String id) async {
    final index = _activities.indexWhere((item) => item.id == id);
    if (index == -1) return;
    // copyWith carries deletedAt through, so a copyWith(updatedAt:) would leave
    // the record tombstoned; revive() clears it so Undo actually restores.
    _activities = [..._activities]..[index] = _activities[index].revive();
    await _persistActivities();
  }

  Future<void> _persistActivities() async {
    notifyListeners();
    await _storage.writeActivities(
      _activities.map((activity) => activity.toJson()).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // People & loan balances
  // -------------------------------------------------------------------------

  Person? personById(String? id) {
    if (id == null) return null;
    for (final person in _people) {
      if (person.id == id && !person.isDeleted) return person;
    }
    return null;
  }

  /// Finds a person by name (case-insensitive), creating one if none matches,
  /// so a command like "I lent John 5000" always resolves to a stable id.
  Future<Person> resolvePerson(String name) async {
    final key = name.trim().toLowerCase();
    for (final person in _people) {
      if (!person.isDeleted && person.matchKey == key) return person;
    }

    final person = Person(
      id: _uuid.v4(),
      name: name.trim(),
      updatedAt: DateTime.now(),
    );
    _people = [..._people, person];
    await _persistPeople();
    return person;
  }

  /// The net standing with a person: positive = they owe the user, negative =
  /// the user owes them. Derived purely from loan activities so it can never
  /// drift from the ledger (spec §9, §10).
  double balanceWith(String personId) {
    return _activities
        .where((a) => !a.isDeleted && a.personId == personId)
        .fold<double>(0, (sum, a) => sum + a.receivableDelta);
  }

  /// Everyone with an unsettled balance, largest magnitude first.
  List<LoanBalance> get outstandingBalances {
    final result = <LoanBalance>[];
    for (final person in people) {
      final net = balanceWith(person.id);
      if (net.abs() >= 0.5) {
        result.add(LoanBalance(person: person, net: net));
      }
    }
    result.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    return result;
  }

  double get totalOwedToUser => outstandingBalances
      .where((b) => b.theyOweUser)
      .fold<double>(0, (sum, b) => sum + b.net);

  double get totalOwedByUser => outstandingBalances
      .where((b) => b.weOweThem)
      .fold<double>(0, (sum, b) => sum + b.magnitude);

  Future<void> _persistPeople() async {
    notifyListeners();
    await _storage.writePeople(
      _people.map((person) => person.toJson()).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Combined history & activity-type accounting (spec §33, §34)
  // -------------------------------------------------------------------------

  /// Income recorded in [month]. Transfers and loans are excluded by
  /// construction — they aren't income (spec §34).
  double incomeInMonth(DateTime month) {
    return activities
        .where(
          (a) =>
              a.type == ActivityType.income &&
              a.date.year == month.year &&
              a.date.month == month.month &&
              (_activeProfileId == null || a.profileId == _activeProfileId),
        )
        .fold<double>(0, (sum, a) => sum + a.amount);
  }

  /// Income recorded this month.
  double get incomeThisMonth => incomeInMonth(DateTime.now());

  /// Income recorded last month, for the hero card's month-on-month trend.
  double get incomeLastMonth {
    final now = DateTime.now();
    return incomeInMonth(DateTime(now.year, now.month - 1));
  }

  /// Activities in the active profile, for history. Expenses are handled
  /// separately by the existing expense list; this is the non-expense stream.
  List<Activity> get scopedActivities {
    if (_activeProfileId == null) return activities;
    return activities
        .where((a) => a.profileId == _activeProfileId)
        .toList();
  }
}

/// A handle to a just-captured record, so the command bar can Undo it.
class CaptureResult {
  const CaptureResult({required this.isExpense, required this.id});

  /// True when the capture created an [Expense]; false for an [Activity].
  final bool isExpense;
  final String id;
}

/// One row of the category breakdown.
class CategoryTotal {
  const CategoryTotal({required this.category, required this.total});

  final ExpenseCategory category;
  final double total;
}

/// One bar of the monthly trend chart.
class MonthTotal {
  const MonthTotal({required this.month, required this.total});

  final DateTime month;
  final double total;
}

/// A category's spend against its budget for a month — one goal card on the
/// home screen.
class BudgetProgress {
  const BudgetProgress({
    required this.category,
    required this.spent,
    required this.budget,
  });

  final ExpenseCategory category;
  final double spent;
  final double budget;

  /// Spend as a share of budget, uncapped so "over budget" is visible as a
  /// value above 1.
  double get fraction => budget <= 0 ? 0 : spent / budget;

  /// The bar never draws past full, even when [fraction] exceeds 1 — an
  /// over-budget card shows a full bar plus an explicit "over by" figure.
  double get barFraction => fraction.clamp(0.0, 1.0);

  double get remaining => budget - spent;
  bool get isOver => spent > budget;
}
