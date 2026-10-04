import 'package:budget/services/storage.dart';
import 'package:budget/spaces/spaces_shell.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/state/brain_state.dart';
import 'package:flutter/gestures.dart';
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
    child: const MaterialApp(home: SpacesShell()),
  );
}

void main() {
  testWidgets('browser pinch zoom-out opens Spaces', (tester) async {
    await tester.pumpWidget(await _hostSpaces());
    await tester.pumpAndSettle();

    await tester.sendEventToBinding(
      const PointerScaleEvent(position: Offset(20, 20), scale: 0.8),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final spacesOpacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Spaces'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(spacesOpacity.opacity, 1);
  });
}
