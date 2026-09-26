import 'package:flutter_test/flutter_test.dart';
import 'package:self_tracker_client/calendar/events.dart';

void main() {
  test('validates the required interval and title', () {
    const valid = EventDraft(
      date: '2026-09-26',
      startTime: '09:00',
      endTime: '10:00',
      title: 'Прогулка',
    );
    expect(validateEvent(valid), isNull);
    expect(
      validateEvent(
        const EventDraft(
          date: '2026-02-30',
          startTime: '09:00',
          endTime: '10:00',
          title: 'Дело',
        ),
      ),
      contains('дату'),
    );
    expect(
      validateEvent(
        const EventDraft(
          date: '2026-09-26',
          startTime: '10:00',
          endTime: '09:00',
          title: 'Дело',
        ),
      ),
      contains('позже'),
    );
    expect(
      validateEvent(
        const EventDraft(
          date: '2026-09-26',
          startTime: '09:00',
          endTime: '10:00',
          title: '  ',
        ),
      ),
      contains('название'),
    );
  });

  test(
    'repository orders events, moves dates and detects stale edits',
    () async {
      final repository = MemoryEventRepository();
      const later = EventDraft(
        date: '2026-09-26',
        startTime: '18:00',
        endTime: '19:00',
        title: 'Чтение',
      );
      const earlier = EventDraft(
        date: '2026-09-26',
        startTime: '09:00',
        endTime: '10:00',
        title: 'Прогулка',
      );
      final a = await repository.create(later);
      await repository.create(earlier);
      expect((await repository.list('2026-09-26')).map((e) => e.title), [
        'Прогулка',
        'Чтение',
      ]);
      final moved = await repository.update(
        a.id,
        const EventDraft(
          date: '2026-09-27',
          startTime: '08:00',
          endTime: '09:00',
          title: 'Чтение',
        ),
        a.revision,
      );
      expect(await repository.list('2026-09-26'), hasLength(1));
      expect(await repository.list('2026-09-27'), hasLength(1));
      await expectLater(
        repository.update(a.id, later, a.revision),
        throwsA(isA<EventConflict>()),
      );
      await repository.delete(a.id, moved.revision);
      expect(await repository.list('2026-09-27'), isEmpty);
    },
  );
}
