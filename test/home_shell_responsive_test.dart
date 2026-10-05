import 'package:budget/screens/home_shell.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:budget/widgets/morph_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _hostShell() async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  return ChangeNotifierProvider<AppState>(
    create: (_) => AppState(storage),
    child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('wide layouts use a persistent labelled sidebar', (tester) async {
    _setViewport(tester, const Size(1200, 800));
    await tester.pumpWidget(await _hostShell());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.byType(MorphNavBar), findsNothing);
    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('Add or capture'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-nav-home')), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('desktop-nav-home'))),
      isSemantics(isSelected: true),
    );

    await tester.tap(find.byKey(const ValueKey('desktop-nav-planner')));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(
      tester.getSemantics(find.byKey(const ValueKey('desktop-nav-planner'))),
      isSemantics(isSelected: true),
    );
  });

  testWidgets('narrow layouts keep the touch navigation bar', (tester) async {
    _setViewport(tester, const Size(600, 800));
    await tester.pumpWidget(await _hostShell());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.byType(MorphNavBar), findsOneWidget);
    expect(find.text('Budget'), findsNothing);
  });
}
