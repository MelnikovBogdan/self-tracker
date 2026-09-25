import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:self_tracker_client/activities/activity_module.dart';
import 'package:self_tracker_client/api/api_client.dart';
import 'package:self_tracker_client/auth/session_controller.dart';
import 'package:self_tracker_client/auth/session_store.dart';
import 'package:self_tracker_client/ui/home_shell.dart';

class TestActivity implements ActivityModule {
  const TestActivity(this.id, this.title);
  @override
  final String id;
  @override
  final String title;
  @override
  IconData get icon => Icons.book_outlined;
  @override
  WidgetBuilder get home =>
      (_) => const Center(child: Text('Activity screen'));
  @override
  WidgetBuilder? get settings => null;
}

class MemoryStore implements SessionStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String token) async {}
}

void main() {
  test('registry accepts separate modules and rejects repeated IDs', () {
    final registry = ActivityRegistry([
      const TestActivity('reading', 'Чтение'),
      const TestActivity('programming', 'Программирование'),
    ]);
    expect(registry.modules.map((module) => module.id), [
      'reading',
      'programming',
    ]);
    expect(
      () => ActivityRegistry([
        const TestActivity('reading', 'Чтение'),
        const TestActivity('reading', 'Ещё чтение'),
      ]),
      throwsArgumentError,
    );
  });

  testWidgets(
    'registered activity appears in navigation and opens its screen',
    (tester) async {
      final api = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:3000'),
        httpClient: MockClient((_) async => throw UnimplementedError()),
      );
      final session = SessionController(api, MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          home: HomeShell(
            session: session,
            registry: ActivityRegistry([
              const TestActivity('reading', 'Чтение'),
            ]),
          ),
        ),
      );
      expect(find.text('Чтение'), findsOneWidget);
      await tester.tap(find.text('Чтение'));
      await tester.pump();
      expect(find.text('Activity screen'), findsOneWidget);
      session.dispose();
      api.close();
    },
  );

  testWidgets('empty registry keeps the home screen usable', (tester) async {
    final api = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:3000'),
      httpClient: MockClient((_) async => throw UnimplementedError()),
    );
    final session = SessionController(api, MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(session: session, registry: ActivityRegistry([])),
      ),
    );
    expect(find.text('Активности появятся здесь'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
    session.dispose();
    api.close();
  });
}
