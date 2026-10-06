import 'package:budget/services/storage.dart';
import 'package:budget/spaces/spaces_shell.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/state/brain_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _hostSpaces() async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>(create: (_) => AppState(storage)),
      ChangeNotifierProvider<BrainState>(create: (_) => BrainState(storage)),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const SpacesShell()),
  );
}

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

double _spacesOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(of: find.text('Spaces'), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

void main() {
  testWidgets('desktop sidebar returns to Spaces without pinching', (
    tester,
  ) async {
    _useViewport(tester, const Size(1200, 800));
    await tester.pumpWidget(await _hostSpaces());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('spaces-back-button')), findsOneWidget);
    expect(_spacesOpacity(tester), 0);

    await tester.tap(find.byKey(const ValueKey('spaces-back-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(_spacesOpacity(tester), 1);
  });

  testWidgets('mobile Functions menu returns to Spaces', (tester) async {
    _useViewport(tester, const Size(600, 800));
    await tester.pumpWidget(await _hostSpaces());
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('More'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.bySemanticsLabel('Go to Spaces'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Go to Spaces'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(_spacesOpacity(tester), 1);
  });
}
