import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_tracker_client/api/api_client.dart';
import 'package:self_tracker_client/auth/session_controller.dart';
import 'package:self_tracker_client/auth/session_store.dart';

class TestStore implements SessionStore {
  TestStore(this.token);
  String? token;

  @override
  Future<void> clear() async => token = null;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async => token = value;
}

void main() {
  test('restores a valid device session and clears an expired one', () async {
    var valid = true;
    final api = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:3000'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/session');
        return valid
            ? http.Response(jsonEncode({'username': 'owner'}), 200)
            : http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      }),
    );
    final store = TestStore('saved-token');
    final controller = SessionController(api, store);

    await controller.restore();
    expect(controller.state, SessionState.signedIn);
    expect(controller.token, 'saved-token');

    valid = false;
    await controller.restore();
    expect(controller.state, SessionState.signedOut);
    expect(store.token, isNull);
    controller.dispose();
    api.close();
  });

  test(
    'server outage retains a stored session without claiming it is valid',
    () async {
      final api = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:3000'),
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
      );
      final controller = SessionController(api, TestStore('saved-token'));
      await controller.restore();
      expect(controller.state, SessionState.signedIn);
      expect(controller.connectionNotice, isNotNull);
      controller.dispose();
      api.close();
    },
  );
}
