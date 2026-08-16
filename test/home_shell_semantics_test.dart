import 'package:budget/screens/home_shell.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bottom nav and the raised capture button are icon-only, so their
/// accessibility depends entirely on explicit semantics — covered here.
Future<Widget> _hostShell() async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  return ChangeNotifierProvider<AppState>(
    create: (_) => AppState(storage),
    child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
  );
}

void main() {
  testWidgets('the capture button is a labelled button for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(await _hostShell());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.bySemanticsLabel('Add or capture'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the active tab announces its selected state', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(await _hostShell());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // Home is the default tab; its nav item must expose isSelected, and the
    // others must not.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Home')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Analytics')),
      isSemantics(isSelected: false),
    );

    handle.dispose();
  });
}
