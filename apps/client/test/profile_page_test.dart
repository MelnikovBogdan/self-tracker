import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_tracker_client/api/api_client.dart';
import 'package:self_tracker_client/auth/session_controller.dart';
import 'package:self_tracker_client/auth/session_store.dart';
import 'package:self_tracker_client/ui/profile_page.dart';

class MemoryStore implements SessionStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> read() async => 'token';
  @override
  Future<void> write(String token) async {}
}

void main() {
  testWidgets(
    'a stale edit displays the current server value and can reload it',
    (tester) async {
      final api = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:3000'),
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({'displayName': 'Original', 'revision': 1}),
              200,
            );
          }
          expect(jsonDecode(request.body), {
            'displayName': 'Draft',
            'revision': 1,
          });
          return http.Response(
            jsonEncode({
              'error': 'Profile was changed on another device',
              'profile': {'displayName': 'Current', 'revision': 2},
            }),
            409,
          );
        }),
      );
      final session = SessionController(api, MemoryStore())
        ..token = 'token'
        ..state = SessionState.signedIn;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfilePage(session: session)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Draft');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Профиль изменён'), findsOneWidget);
      expect(
        find.textContaining('На другом устройстве сохранено: Current'),
        findsOneWidget,
      );
      expect(find.text('Синхронизировано'), findsNothing);

      await tester.tap(find.text('Загрузить актуальное значение'));
      await tester.pump();
      expect(find.text('Current'), findsOneWidget);
      session.dispose();
      api.close();
    },
  );

  testWidgets('network failure never displays a successful sync state', (
    tester,
  ) async {
    final api = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:3000'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'displayName': 'Original', 'revision': 1}),
            200,
          );
        }
        throw http.ClientException('offline');
      }),
    );
    final session = SessionController(api, MemoryStore())
      ..token = 'token'
      ..state = SessionState.signedIn;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfilePage(session: session)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Нет связи с сервером.'), findsOneWidget);
    expect(find.text('Изменение не синхронизировано'), findsOneWidget);
    session.dispose();
    api.close();
  });
}
