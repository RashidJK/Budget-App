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

  // Green (Budget) → violet (Second Brain): the two apps Spaces unites.
  static const _violet = Color(0xFF6D5DF6);
  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppTheme.brandGreen, _violet],
  );

  static const _features = [
    (Icons.account_balance_wallet_rounded, 'Budget', 'Spending, budgets and balances at a glance.'),
    (Icons.bubble_chart_rounded, 'Second Brain', 'Capture notes, tasks, journal and links.'),
    (Icons.sync_rounded, 'Synced & private', 'Across every device. Your data stays yours.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.surface,
      body: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 860) {
            // Marketing pitch on the left, sign-in on the right.
            return Row(
              children: [
                Expanded(
                  flex: 6,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(gradient: _gradient),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(56),
                        child: _pitch(),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: _signIn(context),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          // Stacked: a gradient pitch header over the sign-in.
          return SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(gradient: _gradient),
                  padding: const EdgeInsets.fromLTRB(28, 64, 28, 36),
                  child: _pitch(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _signIn(context),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// White-on-gradient: logo, wordmark, tagline and the feature list.
  Widget _pitch() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            const Text(
              'Spaces',
              style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Your money and your mind,\nin one private, synced workspace.',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, height: 1.35),
        ),
        const SizedBox(height: 36),
        for (final (icon, title, subtitle) in _features)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13.5, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The sign-in column on a plain surface.
  Widget _signIn(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Get started',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Sign in with Google to sync your Spaces.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.muted, height: 1.4),
        ),
        const SizedBox(height: 26),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: CircularProgressIndicator(),
          )
        else
          googleSignInButton(onCredential: onCredential, clientId: Config.googleClientId),
        if (error != null) ...[
          const SizedBox(height: 14),
          Text(error!, textAlign: TextAlign.center, style: TextStyle(color: context.warn, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: context.muted),
            const SizedBox(width: 6),
            Text('Private by default — your data is yours.', style: TextStyle(color: context.muted, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
