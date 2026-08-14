import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the app's collections as JSON in shared preferences.
///
/// The data set is small — hundreds of expenses, a handful of categories,
/// profiles and saved scenarios — so a whole-collection rewrite on every
/// change is cheaper than the complexity of a database, and it keeps the app
/// dependency-light. Receipt images are the exception: those are files.
class Storage {
  Storage(this._prefs);

  static const _expensesKey = 'budget.expenses.v1';
  static const _scenariosKey = 'budget.scenarios.v1';
  static const _categoriesKey = 'budget.categories.v1';
  static const _profilesKey = 'budget.profiles.v1';
  static const _activeProfileKey = 'budget.activeProfile.v1';
  static const _activitiesKey = 'budget.activities.v1';
  static const _peopleKey = 'budget.people.v1';
  static const _merchantCategoryKey = 'budget.merchantCategory.v1';

  static Future<Storage> open() async =>
      Storage(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  List<Map<String, dynamic>> readExpenses() => _readList(_expensesKey);

  Future<void> writeExpenses(List<Map<String, dynamic>> expenses) =>
      _writeList(_expensesKey, expenses);

  /// Non-expense financial activities (income, transfers, loans, repayments).
  List<Map<String, dynamic>> readActivities() => _readList(_activitiesKey);

  Future<void> writeActivities(List<Map<String, dynamic>> activities) =>
      _writeList(_activitiesKey, activities);

  /// People involved in loans.
  List<Map<String, dynamic>> readPeople() => _readList(_peopleKey);

  Future<void> writePeople(List<Map<String, dynamic>> people) =>
      _writeList(_peopleKey, people);

  List<Map<String, dynamic>> readScenarios() => _readList(_scenariosKey);

  Future<void> writeScenarios(List<Map<String, dynamic>> scenarios) =>
      _writeList(_scenariosKey, scenarios);

  List<Map<String, dynamic>> readCategories() => _readList(_categoriesKey);

  Future<void> writeCategories(List<Map<String, dynamic>> categories) =>
      _writeList(_categoriesKey, categories);

  List<Map<String, dynamic>> readProfiles() => _readList(_profilesKey);

  Future<void> writeProfiles(List<Map<String, dynamic>> profiles) =>
      _writeList(_profilesKey, profiles);

  /// Null means "All profiles".
  String? readActiveProfile() => _prefs.getString(_activeProfileKey);

  Future<void> writeActiveProfile(String? id) async {
    if (id == null) {
      await _prefs.remove(_activeProfileKey);
    } else {
      await _prefs.setString(_activeProfileKey, id);
    }
  }

  /// Learned merchant → category associations (spec §5, §37 rule 2).
  Map<String, String> readMerchantCategories() {
    final raw = _prefs.getString(_merchantCategoryKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } on FormatException {
      return {};
    }
  }

  Future<void> writeMerchantCategories(Map<String, String> map) =>
      _prefs.setString(_merchantCategoryKey, jsonEncode(map));

  /// True when nothing has ever been written — the signal to seed defaults.
  bool get isFirstLaunch => !_prefs.containsKey(_categoriesKey);

  /// Decodes a stored list, discarding anything unreadable.
  ///
  /// Corrupt or partially-written JSON returns an empty list rather than
  /// throwing: losing saved data is bad, but a launch crash the user cannot
  /// recover from without reinstalling is worse.
  List<Map<String, dynamic>> _readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> items) =>
      _prefs.setString(key, jsonEncode(items));
}

/// Receipt images on disk.
///
/// The picker hands back a path in a temporary cache the OS is free to purge,
/// so every attachment is copied into the app's documents directory before it
/// is recorded on an expense.
class AttachmentStore {
  const AttachmentStore._();

  static const String _folder = 'receipts';

  /// Copies [sourcePath] into permanent storage and returns the new path.
  static Future<String> keep(String sourcePath) async {
    final directory = await _directory();
    final extension = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.jpg';
    final name = 'receipt_${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination = File('${directory.path}/$name');

    await File(sourcePath).copy(destination.path);
    return destination.path;
  }

  /// Deletes an attachment, ignoring a file that is already gone.
  static Future<void> discard(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // A missing or unreadable receipt must not block deleting the expense.
    }
  }

  static Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/$_folder');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
