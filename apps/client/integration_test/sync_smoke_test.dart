import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:self_tracker_client/api/api_client.dart';
import 'package:self_tracker_client/auth/session_store.dart';
import 'package:self_tracker_client/main.dart' as app;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  final labels = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .take(20)
      .toList();
  throw TestFailure('Timed out waiting for $finder; visible text: $labels');
}

Future<void> openProfile(WidgetTester tester) async {
  await tester.tap(find.text('Профиль').first);
  await waitFor(tester, find.text('Синхронизировано'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, profile sync, restart, and independent logout', (
    tester,
  ) async {
    const username = String.fromEnvironment('SMOKE_USERNAME');
    const password = String.fromEnvironment('SMOKE_PASSWORD');
    const apiUrl = String.fromEnvironment('API_BASE_URL');
    const expectedInitialName = String.fromEnvironment('SMOKE_EXPECTED_NAME');
    const secondName = String.fromEnvironment(
      'SMOKE_SECOND_NAME',
      defaultValue: 'Updated from second session',
    );
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    expect(apiUrl, isNotEmpty);

    final secondClient = ApiClient(baseUri: Uri.parse(apiUrl));
    addTearDown(secondClient.close);
    await SecureSessionStore().clear();

    app.main();
    await waitFor(tester, find.text('Войти'));
    await tester.enterText(find.byType(TextField).at(0), username);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.tap(find.text('Войти'));
    await waitFor(tester, find.text('Мой день'));

    await openProfile(tester);
    if (expectedInitialName.isNotEmpty) {
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        expectedInitialName,
      );
    }
    final firstName = 'Smoke ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byType(TextField), firstName);
    await tester.tap(find.text('Сохранить'));
    await waitFor(tester, find.text('Синхронизировано'));

    final secondSession = await secondClient.login(username, password);
    final fromSecondSession = await secondClient.getProfile(
      secondSession.token,
    );
    expect(fromSecondSession.displayName, firstName);

    await secondClient.updateProfile(
      secondSession.token,
      secondName,
      fromSecondSession.revision,
    );
    await tester.tap(find.text('Обновить'));
    await waitFor(tester, find.text('Синхронизировано'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      secondName,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    app.main();
    await waitFor(tester, find.text('Мой день'));
    await openProfile(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      secondName,
    );

    final logoutFinder = find.ancestor(
      of: find.byIcon(Icons.logout),
      matching: find.byType(IconButton),
    );
    final logoutButton = tester.widget<IconButton>(logoutFinder);
    expect(logoutButton.onPressed, isNotNull);
    await tester.tap(logoutFinder);
    await waitFor(tester, find.text('Войти'));
    expect(
      (await secondClient.getProfile(secondSession.token)).displayName,
      secondName,
    );
    await secondClient.logout(secondSession.token);
  });
}
