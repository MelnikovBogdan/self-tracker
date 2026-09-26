import 'dart:collection';

const eventColors = <String, int>{
  'terracotta': 0xFFAB6655,
  'sage': 0xFF4F8767,
  'slate': 0xFF547FA0,
  'ochre': 0xFFB18B42,
  'neutral': 0xFF8E9189,
};

const eventColorNames = <String, String>{
  'terracotta': 'Терракотовый',
  'sage': 'Зелёный',
  'slate': 'Синий',
  'ochre': 'Охра',
  'neutral': 'Нейтральный',
};

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String? validateEvent(EventDraft draft) {
  final parsedDate = DateTime.tryParse(draft.date);
  if (parsedDate == null ||
      dayKey(parsedDate) != draft.date ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(draft.date)) {
    return 'Укажите дату.';
  }
  final time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
  if (!time.hasMatch(draft.startTime) || !time.hasMatch(draft.endTime)) {
    return 'Укажите время в формате ЧЧ:ММ.';
  }
  if (draft.endTime.compareTo(draft.startTime) <= 0) {
    return 'Конец должен быть позже начала.';
  }
  if (draft.title.trim().isEmpty) return 'Укажите название.';
  if (draft.title.trim().length > 120) return 'Название слишком длинное.';
  if (draft.description.length > 2000) return 'Описание слишком длинное.';
  if (!eventColors.containsKey(draft.color)) return 'Выберите цвет.';
  return null;
}

class EventDraft {
  const EventDraft({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.title,
    this.description = '',
    this.color = 'neutral',
  });

  final String date;
  final String startTime;
  final String endTime;
  final String title;
  final String description;
  final String color;

  Map<String, dynamic> toJson({int? revision}) => {
    'date': date,
    'startTime': startTime,
    'endTime': endTime,
    'title': title.trim(),
    'description': description.trim(),
    'color': color,
    'revision': ?revision,
  };
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.revision,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.title,
    required this.description,
    required this.color,
  });

  final String id;
  final int revision;
  final String date;
  final String startTime;
  final String endTime;
  final String title;
  final String description;
  final String color;

  EventDraft get draft => EventDraft(
    date: date,
    startTime: startTime,
    endTime: endTime,
    title: title,
    description: description,
    color: color,
  );

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: json['id'] as String,
    revision: json['revision'] as int,
    date: json['date'] as String,
    startTime: json['startTime'] as String,
    endTime: json['endTime'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    color: json['color'] as String? ?? 'neutral',
  );
}

class EventConflict implements Exception {
  const EventConflict(this.current);
  final CalendarEvent? current;
}

abstract class EventRepository {
  Future<List<CalendarEvent>> list(String date);
  Future<Set<String>> busyDays(int year, int month);
  Future<CalendarEvent> create(EventDraft draft);
  Future<CalendarEvent> update(String id, EventDraft draft, int revision);
  Future<void> delete(String id, int revision);
}

class MemoryEventRepository implements EventRepository {
  MemoryEventRepository([Iterable<CalendarEvent> seed = const []]) {
    for (final event in seed) {
      _items[event.id] = event;
    }
  }

  final Map<String, CalendarEvent> _items = {};
  int _nextId = 1;

  @override
  Future<List<CalendarEvent>> list(String date) async {
    final events = _items.values.where((event) => event.date == date).toList()
      ..sort((a, b) {
        final time = a.startTime.compareTo(b.startTime);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    return UnmodifiableListView(events);
  }

  @override
  Future<Set<String>> busyDays(int year, int month) async => _items.values
      .where(
        (event) => event.date.startsWith(
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-',
        ),
      )
      .map((event) => event.date)
      .toSet();

  @override
  Future<CalendarEvent> create(EventDraft draft) async {
    final error = validateEvent(draft);
    if (error != null) throw ArgumentError(error);
    final event = _fromDraft('local-${_nextId++}', 1, draft);
    _items[event.id] = event;
    return event;
  }

  @override
  Future<CalendarEvent> update(
    String id,
    EventDraft draft,
    int revision,
  ) async {
    final error = validateEvent(draft);
    if (error != null) throw ArgumentError(error);
    final current = _items[id];
    if (current == null) throw StateError('План не найден.');
    if (current.revision != revision) throw EventConflict(current);
    final event = _fromDraft(id, revision + 1, draft);
    _items[id] = event;
    return event;
  }

  @override
  Future<void> delete(String id, int revision) async {
    final current = _items[id];
    if (current == null) throw StateError('План не найден.');
    if (current.revision != revision) throw EventConflict(current);
    _items.remove(id);
  }

  CalendarEvent _fromDraft(String id, int revision, EventDraft draft) =>
      CalendarEvent(
        id: id,
        revision: revision,
        date: draft.date,
        startTime: draft.startTime,
        endTime: draft.endTime,
        title: draft.title.trim(),
        description: draft.description.trim(),
        color: draft.color,
      );
}
