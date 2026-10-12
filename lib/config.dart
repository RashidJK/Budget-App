/// Build-time configuration, supplied with `--dart-define` at build:
///
///   flutter build web --release \
///     --dart-define=API_BASE=https://api.yourdomain.com \
///     --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
///
/// Both default to empty, in which case the app stays fully local (no sign-in,
/// no sync) — exactly the behaviour before the backend existed.
class Config {
  const Config._();

  static const String apiBase = String.fromEnvironment('API_BASE');
  static const String googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

  /// Whether a backend is wired up for this build.
  static bool get syncEnabled => apiBase.isNotEmpty;

  /// Whether Google sign-in is configured for this build.
  static bool get authEnabled => apiBase.isNotEmpty && googleClientId.isNotEmpty;
}
