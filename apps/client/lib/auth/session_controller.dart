import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'session_store.dart';

enum SessionState { loading, signedOut, signedIn }

class SessionController extends ChangeNotifier {
  SessionController(this.api, this.store);

  final ApiClient api;
  final SessionStore store;
  SessionState state = SessionState.loading;
  String? token;
  String? connectionNotice;

  Future<void> restore() async {
    try {
      token = await store.read();
      if (token == null) {
        state = SessionState.signedOut;
      } else {
        try {
          await api.validateSession(token!);
          state = SessionState.signedIn;
        } on UnauthorizedException {
          await store.clear();
          token = null;
          state = SessionState.signedOut;
        } on ApiException catch (error) {
          connectionNotice = error.message;
          state = SessionState.signedIn;
        }
      }
    } catch (_) {
      token = null;
      state = SessionState.signedOut;
      connectionNotice = 'Не удалось прочитать сохранённую сессию.';
    }
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final result = await api.login(username, password);
    await store.write(result.token);
    token = result.token;
    state = SessionState.signedIn;
    connectionNotice = null;
    notifyListeners();
  }

  Future<void> logout() async {
    if (token == null) return;
    await api.logout(token!);
    await store.clear();
    token = null;
    state = SessionState.signedOut;
    connectionNotice = null;
    notifyListeners();
  }

  Future<void> sessionExpired() async {
    await store.clear();
    token = null;
    state = SessionState.signedOut;
    connectionNotice = null;
    notifyListeners();
  }
}
