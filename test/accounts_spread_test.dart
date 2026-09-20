import 'package:budget/screens/tracker/accounts_spread.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wallet spread — pinching the deck fans every account out as a big card.
Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

void main() {
  testWidgets('the spread lists each account as its own card', (tester) async {
    final state = await _freshState();
    final account = state.accounts.single;
    await state.updateAccount(account.copyWith(openingBalance: 500000));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAccountsSpread(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Header plus a card bearing the account's own name, writ large.
    expect(find.text('Accounts'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == account.name && w.style?.fontSize == 44,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });
}
