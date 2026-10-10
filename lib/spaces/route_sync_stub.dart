// Non-web fallback: there's no browser URL to sync, so these are all no-ops.

String? initialRoutePath() => null;

void pushRoutePath(String path, {bool replace = false}) {}

void listenRoutePop(void Function(String path) onPop) {}
