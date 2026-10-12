import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/google_signin.dart';
import '../config.dart';
import '../state/auth_state.dart';
import '../sync/api_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';

/// Wraps the app. When Google sign-in is configured (web product build) and the
/// user isn't signed in, it shows a sign-in screen; otherwise it shows the app
/// and keeps a background sync ticking. On mobile/desktop or a local-only build
/// it's transparent — the app runs exactly as before.
class SignInGate extends StatefulWidget {
  const SignInGate({super.key, required this.child});

  final Widget child;

  @override
  State<SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends State<SignInGate> {
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSyncIfSignedIn());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startSyncIfSignedIn() {
    if (!Config.syncEnabled || !mounted) return;
    if (!context.read<AuthState>().isSignedIn) return;
    final sync = context.read<SyncService>();
    sync.syncNow();
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => sync.syncNow());
  }

  Future<void> _onCredential(String idToken) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await context.read<ApiClient>().authGoogle(idToken);
    if (!mounted) return;
    final token = res?['token']?.toString();
    if (token == null || token.isEmpty) {
      setState(() {
        _busy = false;
        _error = "Couldn't sign in. Please try again.";
      });
      return;
    }
    await context.read<AuthState>().setSession(
      token,
      email: res?['email']?.toString(),
      name: res?['name']?.toString(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _startSyncIfSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    // Only gate on web where Google sign-in is wired.
    if (!Config.authEnabled || !kIsWeb) return widget.child;
    final signedIn = context.watch<AuthState>().isSignedIn;
    if (signedIn) return widget.child;
    return _SignInScreen(
      busy: _busy,
      error: _error,
      onCredential: _onCredential,
    );
  }
}

class _SignInScreen extends StatelessWidget {
  const _SignInScreen({
    required this.busy,
    required this.error,
    required this.onCredential,
  });

  final bool busy;
  final String? error;
  final void Function(String idToken) onCredential;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                Text(
                  'Spaces',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your budget and second brain,\nsynced across your devices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.muted, height: 1.4),
                ),
                const SizedBox(height: 28),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: CircularProgressIndicator(),
                  )
                else
                  googleSignInButton(
                    onCredential: onCredential,
                    clientId: Config.googleClientId,
                  ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(error!, style: TextStyle(color: context.warn, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
