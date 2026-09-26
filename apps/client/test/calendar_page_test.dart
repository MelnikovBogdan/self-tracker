import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_tracker_client/calendar/calendar_page.dart';
import 'package:self_tracker_client/calendar/events.dart';

class FailOnceRepository extends MemoryEventRepository {
  bool fail = true;
  @override
  Future<CalendarEvent> create(EventDraft draft) {
    if (fail) {
      fail = false;
      throw StateError('Связь прервана');
    }
    return super.create(draft);
  }
}

class StaleRepository extends MemoryEventRepository {
  StaleRepository(this.stale, CalendarEvent current) : super([current]);
  final CalendarEvent stale;
  bool showStale = true;
  @override
  Future<List<CalendarEvent>> list(String date) async =>
      showStale ? [stale] : super.list(date);
  @override
  Future<CalendarEvent> update(
    String id,
    EventDraft draft,
    int revision,
  ) async {
    final result = await super.update(id, draft, revision);
    showStale = false;
    return result;
  }
}

void main() {
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('phone: empty day can create, preview and delete a plan', (
    tester,
  ) async {
    await size(tester, const Size(390, 844));
    final repository = MemoryEventRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            initialDate: DateTime(2026, 9, 26),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Этот день свободен'), findsOneWidget);
    await tester.tap(find.text('Создать план'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Утренняя прогулка',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать план').last);
    await tester.pumpAndSettle();
    expect(find.text('Утренняя прогулка'), findsOneWidget);
    await tester.tap(find.text('Утренняя прогулка'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить план'), findsOneWidget);
    await tester.tap(find.text('Удалить план'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить план?'), findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Этот день свободен'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide: selected plan opens preview with visible delete action', (
    tester,
  ) async {
    await size(tester, const Size(1280, 820));
    final repository = MemoryEventRepository();
    await repository.create(
      const EventDraft(
        date: '2026-09-26',
        startTime: '09:00',
        endTime: '10:00',
        title: 'Чтение',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            initialDate: DateTime(2026, 9, 26),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чтение'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить план'), findsOneWidget);
    expect(find.text('Изменить план'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save keeps the entered title for retry', (tester) async {
    await size(tester, const Size(390, 844));
    final repository = FailOnceRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            initialDate: DateTime(2026, 9, 26),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать план'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Важное дело',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать план').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось сохранить'), findsOneWidget);
    expect(find.text('Важное дело'), findsOneWidget);
    await tester.tap(find.text('Проверить календарь'));
    await tester.pumpAndSettle();
    expect(find.textContaining('План не найден'), findsOneWidget);
    expect(find.text('Важное дело'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Создать план').last);
    await tester.pumpAndSettle();
    expect(find.text('Важное дело'), findsOneWidget);
    expect(await repository.list('2026-09-26'), hasLength(1));
  });

  testWidgets('stale edit preserves draft and requires explicit overwrite', (
    tester,
  ) async {
    await size(tester, const Size(1280, 820));
    const stale = CalendarEvent(
      id: 'event-1',
      revision: 1,
      date: '2026-09-26',
      startTime: '09:00',
      endTime: '10:00',
      title: 'Чтение',
      description: '',
      color: 'neutral',
    );
    const current = CalendarEvent(
      id: 'event-1',
      revision: 2,
      date: '2026-09-26',
      startTime: '10:00',
      endTime: '11:00',
      title: 'Чтение с другого устройства',
      description: '',
      color: 'neutral',
    );
    final repository = StaleRepository(stale, current);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            repository: repository,
            initialDate: DateTime(2026, 9, 26),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чтение'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить план'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Мои правки',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('План изменён на другом устройстве'), findsOneWidget);
    expect(find.text('Мои правки'), findsOneWidget);
    await tester.tap(find.text('Посмотреть варианты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить мои изменения'));
    await tester.pumpAndSettle();
    expect(find.text('Заменить актуальный план?'), findsOneWidget);
    await tester.tap(find.text('Заменить'));
    await tester.pumpAndSettle();
    expect((await repository.list('2026-09-26')).single.title, 'Мои правки');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading current conflict version also updates the revision for save',
    (tester) async {
      await size(tester, const Size(1280, 820));
      const stale = CalendarEvent(
        id: 'event-2',
        revision: 1,
        date: '2026-09-26',
        startTime: '09:00',
        endTime: '10:00',
        title: 'Старый план',
        description: '',
        color: 'neutral',
      );
      const current = CalendarEvent(
        id: 'event-2',
        revision: 2,
        date: '2026-09-26',
        startTime: '10:00',
        endTime: '11:00',
        title: 'Актуальный план',
        description: '',
        color: 'neutral',
      );
      final repository = StaleRepository(stale, current);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarPage(
              repository: repository,
              initialDate: DateTime(2026, 9, 26),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Старый план'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Изменить план'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Посмотреть варианты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Загрузить актуальное'));
      await tester.pumpAndSettle();
      expect(find.text('Актуальный план'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Правка после загрузки',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(
        (await repository.list('2026-09-26')).single.title,
        'Правка после загрузки',
      );
    },
  );

  testWidgets(
    'long day remains scrollable on a small phone and a wide window',
    (tester) async {
      final repository = MemoryEventRepository();
      for (var index = 0; index < 8; index++) {
        await repository.create(
          EventDraft(
            date: '2026-09-26',
            startTime: '${(8 + index).toString().padLeft(2, '0')}:00',
            endTime: '${(9 + index).toString().padLeft(2, '0')}:00',
            title: 'План $index',
          ),
        );
      }
      for (final dimensions in [const Size(375, 667), const Size(1280, 820)]) {
        await size(tester, dimensions);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CalendarPage(
                key: ValueKey(dimensions.width),
                repository: repository,
                initialDate: DateTime(2026, 9, 26),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('План 7'),
          200,
          scrollable: dimensions.width >= 840
              ? find.byType(Scrollable).last
              : find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('План 7'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
