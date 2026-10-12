import 'package:flutter/foundation.dart';

import '../services/storage.dart';

/// Holds the signed-in session (the server token + who it belongs to) and
/// persists it, so sign-in survives a restart. Empty = signed out / local-only.
class AuthState extends ChangeNotifier {
  AuthState(this._storage)
    : _token = _storage.readAuthToken(),
      _email = _storage.readAuthEmail(),
      _name = _storage.readAuthName();

  final Storage _storage;

  String? _token;
  String? _email;
  String? _name;

  String? get token => _token;
  String? get email => _email;
  String? get name => _name;
  bool get isSignedIn => _token != null && _token!.isNotEmpty;

  Future<void> setSession(String token, {String? email, String? name}) async {
    _token = token;
    _email = email;
    _name = name;
    await _storage.writeAuth(token: token, email: email, name: name);
    notifyListeners();
  }

  Future<void> signOut() async {
    _token = null;
    _email = null;
    _name = null;
    await _storage.writeAuth();
    await _storage.writeSyncCursor(0); // next sign-in pulls a fresh snapshot
    notifyListeners();
  }
}
