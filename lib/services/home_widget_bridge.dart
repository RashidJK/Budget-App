import 'dart:io' show Platform;

import 'package:home_widget/home_widget.dart';

import '../state/app_state.dart';
import 'format.dart';

/// Bridges the app's month-to-date figures to the iOS home-screen widget.
///
/// The Dart side only writes a few strings into a shared App Group container
/// and asks WidgetKit to reload; the SwiftUI widget (see
/// `ios/BudgetWidget/`) reads those strings and draws them. Keeping the numbers
/// pre-formatted here means the native side needs no currency logic.
class HomeWidgetBridge {
  /// Must match the App Group configured on both the Runner and the widget
  /// extension targets, and the `suiteName` the SwiftUI widget reads.
  static const appGroupId = 'group.com.kadingo.budget';

  /// Matches the `kind` / struct name of the SwiftUI widget.
  static const _iOSWidgetName = 'BudgetWidget';

  static bool get _supported => Platform.isIOS;

  /// Registers the App Group so reads and writes hit the shared container.
  static Future<void> init() async {
    if (!_supported) return;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
    } catch (_) {
      // A missing extension or entitlement shouldn't crash the app.
    }
  }

  /// Pushes the current figures now and on every subsequent change.
  static void attach(AppState state) {
    unawaitedPush(state);
    state.addListener(() => unawaitedPush(state));
  }

  /// Fire-and-forget push; failures are swallowed so the UI never blocks on the
  /// widget.
  static void unawaitedPush(AppState state) {
    if (!_supported) return;
    push(state).catchError((_) {});
  }

  static Future<void> push(AppState state) async {
    if (!_supported) return;
    final spent = state.spentThisMonth;
    final income = state.incomeThisMonth;
    final net = income - spent;

    await HomeWidget.saveWidgetData<String>('month', _monthLabel());
    await HomeWidget.saveWidgetData<String>('spent', Money.format(spent));
    await HomeWidget.saveWidgetData<String>('income', Money.format(income));
    await HomeWidget.saveWidgetData<String>('net', Money.format(net));
    // A signed net lets the widget colour it without re-parsing.
    await HomeWidget.saveWidgetData<double>('netValue', net);
    await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
  }

  static String _monthLabel() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    return months[now.month - 1];
  }
}
