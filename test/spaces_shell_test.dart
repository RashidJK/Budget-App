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
  testWidgets('trackpad pinch zooms the Spaces launcher in and out', (tester) async {
    await tester.pumpWidget(await _hostSpaces());
    await tester.pumpAndSettle();

    // The launcher heading sits inside an Opacity that tracks the zoom: 1 when
    // Spaces is open, 0 when a focused app fills the screen.
    double spacesOpacity() => tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text('Spaces'), matching: find.byType(Opacity))
              .first,
        )
        .opacity;

    // Pinch out (scale < 1) opens the launcher.
    await tester.sendEventToBinding(
      const PointerScaleEvent(position: Offset(20, 20), scale: 0.8),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(spacesOpacity(), 1);

    // A neutral scale of exactly 1 must not move the zoom.
    await tester.sendEventToBinding(
      const PointerScaleEvent(position: Offset(20, 20), scale: 1),
    );
    await tester.pump();
    expect(spacesOpacity(), 1);

    // Spread (scale > 1) dives back into the focused app.
    await tester.sendEventToBinding(
      const PointerScaleEvent(position: Offset(20, 20), scale: 1.2),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(spacesOpacity(), 0);
  });
}
