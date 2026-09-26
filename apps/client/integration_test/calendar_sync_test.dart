import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:self_tracker_client/api/api_client.dart';
import 'package:self_tracker_client/auth/session_store.dart';
import 'package:self_tracker_client/calendar/events.dart';
import 'package:self_tracker_client/main.dart' as app;

Future<void> waitForText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text(text).evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $text');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('calendar plan is shared between Android and macOS', (
    tester,
  ) async {
    const phase = String.fromEnvironment('SYNC_PHASE');
    const title = String.fromEnvironment('SYNC_TITLE');
    const username = String.fromEnvironment('SMOKE_USERNAME');
    const password = String.fromEnvironment('SMOKE_PASSWORD');
    const url = String.fromEnvironment('API_BASE_URL');
    expect(['create', 'edit', 'verify'], contains(phase));
    expect(title, isNotEmpty);
    expect(url, isNotEmpty);

    await SecureSessionStore().clear();
    app.main();
    await waitForText(tester, 'Войти');
    await tester.enterText(find.byType(TextField).at(0), username);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.tap(find.text('Войти'));
    await waitForText(tester, 'Мой день');

    if (phase == 'create') {
      await tester.tap(find.text('Новый план').first);
      await waitForText(tester, 'Создать план');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        title,
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Создать план'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Создать план'));
      await waitForText(tester, title);
    } else if (phase == 'edit') {
      await waitForText(tester, title);
      await tester.tap(find.text(title));
      await waitForText(tester, 'Удалить план');
      await tester.tap(find.text('Изменить план'));
      await waitForText(tester, 'Сохранить');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Начало'),
        '08:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Конец'),
        '09:00',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await waitForText(tester, '08:00–09:00');
    } else {
      await waitForText(tester, title);
      expect(find.text('08:00–09:00'), findsOneWidget);
    }

    final api = ApiClient(baseUri: Uri.parse(url));
    addTearDown(api.close);
    final session = await api.login(username, password);
    final plans = await ApiEventRepository(
      api,
      () => session.token,
    ).list(dayKey(DateTime.now()));
    expect(plans.where((event) => event.title == title), hasLength(1));
  });
}
