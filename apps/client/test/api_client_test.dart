import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_tracker_client/api/api_client.dart';
import 'package:self_tracker_client/calendar/events.dart';

void main() {
  test('profile update sends revision and parses a conflict', () async {
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:3000'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'error': 'Profile was changed on another device',
            'profile': {'displayName': 'Current', 'revision': 3},
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      client.updateProfile('session-token', 'Draft', 2),
      throwsA(
        isA<ConflictException>().having(
          (error) => error.current.displayName,
          'current name',
          'Current',
        ),
      ),
    );
    expect(requests.single.url.path, '/v1/profile');
    expect(requests.single.method, 'PUT');
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(requests.single.headers['content-type'], 'application/json');
    expect(jsonDecode(requests.single.body), {
      'displayName': 'Draft',
      'revision': 2,
    });
    client.close();
  });

  test('logout sends no JSON content type when it has no body', () async {
    final client = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:3000'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/logout');
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer session-token');
        expect(request.headers.containsKey('content-type'), isFalse);
        expect(request.body, isEmpty);
        return http.Response('', 204);
      }),
    );

    await client.logout('session-token');
    client.close();
  });

  test('successful login and profile read match the API contract', () async {
    final client = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:3000'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'token': 'test-token',
              'expiresAt': '2030-01-01T00:00:00.000Z',
            }),
            200,
          );
        }
        expect(request.headers['authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({'displayName': 'Owner', 'revision': 1}),
          200,
        );
      }),
    );

    final login = await client.login('owner', 'password');
    expect(login.token, 'test-token');
    final profile = await client.getProfile(login.token);
    expect(profile.displayName, 'Owner');
    expect(profile.revision, 1);
    client.close();
  });

  test('calendar repository uses the event contract and current revision on conflict', () async {
    final requests = <http.Request>[];
    final current = {
      'id': 'ca6f0d55-4ca6-4ad0-aee4-d46722817e28',
      'date': '2026-09-26',
      'startTime': '09:00',
      'endTime': '10:00',
      'title': 'Чтение',
      'description': '',
      'color': 'neutral',
      'revision': 2,
    };
    final client = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:3000'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' && request.url.path == '/v1/events') {
          return http.Response(
            jsonEncode({
              'events': [current],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'dates': ['2026-09-26'],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'error': 'conflict', 'event': current}),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final repository = ApiEventRepository(client, () => 'session-token');
    expect((await repository.list('2026-09-26')).single.revision, 2);
    expect(await repository.busyDays(2026, 9), {'2026-09-26'});
    await expectLater(
      repository.update(
        current['id'] as String,
        const EventDraft(
          date: '2026-09-26',
          startTime: '11:00',
          endTime: '12:00',
          title: 'Мои правки',
        ),
        1,
      ),
      throwsA(
        isA<EventConflict>().having(
          (error) => error.current?.revision,
          'revision',
          2,
        ),
      ),
    );
    expect(jsonDecode(requests.last.body)['revision'], 1);
    expect(
      requests.every(
        (request) => request.headers['authorization'] == 'Bearer session-token',
      ),
      isTrue,
    );
    client.close();
  });
}
