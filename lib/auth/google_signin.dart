// The "Sign in with Google" button. On the web it renders Google Identity
// Services and hands back the ID token; everywhere else it's a no-op (sign-in
// is web-only for now — mobile stays local-first).
export 'google_signin_stub.dart'
    if (dart.library.html) 'google_signin_web.dart';
