import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'command/mlkit_receipt_scanner.dart';
import 'command/receipt_scanner.dart';
import 'config.dart';
import 'screens/sign_in_gate.dart';
import 'services/home_widget_bridge.dart';
import 'spaces/spaces_shell.dart';
import 'services/storage.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';
import 'state/brain_state.dart';
import 'sync/api_client.dart';
import 'sync/sync_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Real on-device receipt OCR for the running app. Tests and non-mobile builds
  // leave the mock in place, so nothing else has to know about ML Kit.
  if (!kIsWeb) defaultReceiptScanner = MlKitReceiptScanner();

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

  final authState = AuthState(storage);

  // Sync is only wired when a backend is configured for this build; otherwise
  // the app stays fully local, exactly as before.
  ApiClient? api;
  SyncService? sync;
  if (Config.syncEnabled) {
    api = ApiClient(Config.apiBase);
    sync = SyncService(
      storage: storage,
      api: api,
      auth: authState,
      appState: appState,
      brainState: brainState,
    );
  }

  runApp(
    BudgetApp(
      appState: appState,
      brainState: brainState,
      authState: authState,
      api: api,
      sync: sync,
    ),
  );
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({
    super.key,
    required this.appState,
    required this.brainState,
    required this.authState,
    this.api,
    this.sync,
  });

  final AppState appState;
  final BrainState brainState;
  final AuthState authState;
  final ApiClient? api;
  final SyncService? sync;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<BrainState>.value(value: brainState),
        ChangeNotifierProvider<AuthState>.value(value: authState),
        if (api != null) Provider<ApiClient>.value(value: api!),
        if (sync != null)
          ChangeNotifierProvider<SyncService>.value(value: sync!),
      ],
      child: MaterialApp(
        title: 'Spaces',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const SignInGate(child: SpacesShell()),
      ),
    );
  }
}
