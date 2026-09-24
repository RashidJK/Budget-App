import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'command/mlkit_receipt_scanner.dart';
import 'command/receipt_scanner.dart';
import 'services/home_widget_bridge.dart';
import 'spaces/spaces_shell.dart';
import 'services/storage.dart';
import 'state/app_state.dart';
import 'state/brain_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Real on-device receipt OCR for the running app. Tests and non-mobile builds
  // leave the mock in place, so nothing else has to know about ML Kit.
  defaultReceiptScanner = MlKitReceiptScanner();

  // Register the App Group before anything writes to it.
  await HomeWidgetBridge.init();

  // Storage is opened before the first frame so the dashboard can render real
  // figures immediately rather than flashing an empty state on every launch.
  final storage = await Storage.open();

  final appState = AppState(storage);
  // Keep the iOS home-screen widget in step with the latest figures.
  HomeWidgetBridge.attach(appState);

  // The second brain's captures live in their own store, alongside the budget.
  final brainState = BrainState(storage);

  runApp(BudgetApp(appState: appState, brainState: brainState));
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({
    super.key,
    required this.appState,
    required this.brainState,
  });

  final AppState appState;
  final BrainState brainState;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<BrainState>.value(value: brainState),
      ],
      child: MaterialApp(
        title: 'Budget',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const SpacesShell(),
      ),
    );
  }
}
