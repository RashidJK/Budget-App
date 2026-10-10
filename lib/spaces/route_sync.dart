// Keeps the browser URL in step with the active Space. A no-op off the web.
export 'route_sync_stub.dart' if (dart.library.html) 'route_sync_web.dart';
