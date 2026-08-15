import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'command/mlkit_receipt_scanner.dart';
import 'command/receipt_scanner.dart';
import 'screens/home_shell.dart';
import 'services/storage.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Real on-device receipt OCR for the running app. Tests and non-mobile builds
  // leave the mock in place, so nothing else has to know about ML Kit.
  defaultReceiptScanner = MlKitReceiptScanner();

  // Storage is opened before the first frame so the dashboard can render real
  // figures immediately rather than flashing an empty state on every launch.
  final storage = await Storage.open();

  runApp(BudgetApp(storage: storage));
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key, required this.storage});

  final Storage storage;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(storage),
      child: MaterialApp(
        title: 'Budget',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}
