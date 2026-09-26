import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'events.dart';

const _background = Color(0xFFF6F5F1);
const _surface = Color(0xFFFFFEFC);
const _ink = Color(0xFF343B38);
const _muted = Color(0xFF5F6862);
const _accent = Color(0xFF805F58);
const _error = Color(0xFFA14F46);
const _border = Color(0xFFE5E5DF);
const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
const _monthTitles = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];
const _weekdays = [
  'ПОНЕДЕЛЬНИК',
  'ВТОРНИК',
  'СРЕДА',
  'ЧЕТВЕРГ',
  'ПЯТНИЦА',
  'СУББОТА',
  'ВОСКРЕСЕНЬЕ',
];

String _prettyDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';
DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.repository, this.initialDate});
  final EventRepository repository;
  final DateTime? initialDate;

  @override
  State<CalendarPage> createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage> {
  late DateTime _selected = _day(widget.initialDate ?? DateTime.now());
  late DateTime _shownMonth = DateTime(_selected.year, _selected.month);
  List<CalendarEvent> _events = const [];
  Set<String> _busyDates = const {};
  final ScrollController _plansScroll = ScrollController();
  bool _loading = true;
  bool _expanded = false;
  String? _loadError;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final events = await widget.repository.list(dayKey(_selected));
      final busyDates = await widget.repository.busyDays(
        _shownMonth.year,
        _shownMonth.month,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _events = events;
        _busyDates = busyDates;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loadError = '$error';
        _loading = false;
      });
    }
  }

  void _select(DateTime date) {
    setState(() {
      _selected = _day(date);
      _shownMonth = DateTime(date.year, date.month);
    });
    _refresh();
  }

  void _moveMonth(int delta) {
    final next = DateTime(_shownMonth.year, _shownMonth.month + delta);
    setState(() => _shownMonth = next);
    _select(DateTime(next.year, next.month, 1));
  }

  @override
  void dispose() {
    _plansScroll.dispose();
    super.dispose();
  }

  Future<void> createPlan() async {
    final changed = await _showPanel<CalendarEvent>(
      context,
      _EventForm(repository: widget.repository, initialDate: _selected),
    );
    if (changed != null) _select(DateTime.parse(changed.date));
  }

  Future<void> _preview(CalendarEvent event) async {
    final result = await _showPanel<_PreviewAction>(
      context,
      _EventPreview(event: event),
    );
    if (!mounted) return;
    if (result == _PreviewAction.edit) {
      final updated = await _showPanel<CalendarEvent>(
        context,
        _EventForm(
          repository: widget.repository,
          initialDate: _selected,
          event: event,
        ),
      );
      if (updated != null && mounted) {
        _select(DateTime.parse(updated.date));
      }
    } else if (result == _PreviewAction.delete) {
      final confirmed = await _showPanel<bool>(
        context,
        _DeletePanel(event: event),
      );
      if (confirmed == true) {
        try {
          await widget.repository.delete(event.id, event.revision);
          if (mounted) _refresh();
        } on EventConflict catch (conflict) {
          if (mounted) {
            await _showPanel<void>(
              context,
              _InfoPanel(
                title: 'План изменён на другом устройстве',
                message: conflict.current == null
                    ? 'План уже удалён. Обновите календарь.'
                    : 'Откройте актуальную версию перед удалением.',
                action: 'Обновить календарь',
              ),
            );
            _refresh();
          }
        } catch (error) {
          if (mounted) {
            await _showPanel<void>(
              context,
              _InfoPanel(
                title: 'Не удалось удалить план',
                message: '$error',
                action: 'Вернуться',
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final calendar = _calendar(wide);
        final plans = _plans(wide);
        return ColoredBox(
          color: _background,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: wide
                ? ListView(
                    padding: const EdgeInsets.all(28),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_weekdays[_selected.weekday - 1]}, ${_prettyDate(_selected).toUpperCase()}',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Мой день',
                                  style: TextStyle(
                                    fontSize: 31,
                                    fontWeight: FontWeight.w600,
                                    color: _ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: createPlan,
                            icon: const Icon(Icons.add),
                            label: const Text('Новый план'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 9, child: calendar),
                          const SizedBox(width: 16),
                          Expanded(flex: 11, child: plans),
                        ],
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
                    children: [
                      Text(
                        '${_weekdays[_selected.weekday - 1]}, ${_prettyDate(_selected).toUpperCase()}',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Мой день',
                        style: TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 28),
                      calendar,
                      const SizedBox(height: 30),
                      plans,
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _calendar(bool wide) {
    final first = DateTime(_shownMonth.year, _shownMonth.month, 1);
    final monday = first.subtract(Duration(days: first.weekday - 1));
    final last = DateTime(_shownMonth.year, _shownMonth.month + 1, 0);
    final monthCells = ((last.difference(monday).inDays + 7) ~/ 7) * 7;
    final weekStart = _selected.subtract(Duration(days: _selected.weekday - 1));
    final dates = wide || _expanded
        ? List.generate(monthCells, (i) => monday.add(Duration(days: i)))
        : List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: wide
                    ? null
                    : () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '${_monthTitles[_shownMonth.month - 1]} ${_shownMonth.year}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                    if (!wide) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: _ink,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _NavArrow(
              icon: Icons.chevron_left,
              label: 'Предыдущий месяц',
              onTap: () => _moveMonth(-1),
            ),
            const SizedBox(width: 4),
            _NavArrow(
              icon: Icons.chevron_right,
              label: 'Следующий месяц',
              onTap: () => _moveMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            for (final name in const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
              Expanded(
                child: Center(
                  child: Text(
                    name,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dates.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 48,
            mainAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            final date = dates[index];
            final selected = dayKey(date) == dayKey(_selected);
            final today = dayKey(date) == dayKey(DateTime.now());
            final inMonth = date.month == _shownMonth.month;
            // A constant cell height keeps the date baseline fixed with or without a dot.
            return Semantics(
              label:
                  '${_prettyDate(date)}${selected ? ', выбрано' : ''}${_busyDates.contains(dayKey(date)) ? ', есть планы' : ''}',
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => _select(date),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected ? _accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: today && !selected
                          ? Border.all(color: _accent)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : inMonth
                                ? _ink
                                : _muted.withValues(alpha: 0.55),
                            fontSize: 15,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 5,
                          child: selected && _busyDates.contains(dayKey(date))
                              ? const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(width: 5, height: 5),
                                )
                              : _busyDates.contains(dayKey(date))
                              ? const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xFF4F8767),
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(width: 5, height: 5),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (wide) ...[
          const Spacer(),
          const Divider(height: 28, color: _border),
          Text(
            '${_prettyDate(_selected)} · ${_events.length} ${_countWord(_events.length)}',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      ],
    );
    return wide
        ? SizedBox(height: 596, child: _Card(child: content))
        : _Card(child: content);
  }

  Widget _plans(bool wide) {
    if (wide) {
      return SizedBox(
        height: 596,
        child: _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dayKey(_selected) == dayKey(DateTime.now())
                    ? 'Планы на сегодня'
                    : 'Планы на ${_selected.day} ${_months[_selected.month - 1]}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_events.length} ${_countWord(_events.length)}',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                    ? Center(child: _LoadFailure(onRetry: _refresh))
                    : _events.isEmpty
                    ? Center(child: _EmptyDay(onCreate: createPlan))
                    : Scrollbar(
                        controller: _plansScroll,
                        child: ListView.separated(
                          controller: _plansScroll,
                          itemCount: _events.length,
                          itemBuilder: (context, index) => _PlanCard(
                            event: _events[index],
                            wide: true,
                            onTap: () => _preview(_events[index]),
                          ),
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                dayKey(_selected) == dayKey(DateTime.now())
                    ? 'Планы на сегодня'
                    : 'Планы на ${_selected.day} ${_months[_selected.month - 1]}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
            Text(
              '${_events.length} ${_countWord(_events.length)}',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_loadError != null)
          _LoadFailure(onRetry: _refresh)
        else if (_events.isEmpty)
          _EmptyDay(onCreate: createPlan)
        else ...[
          for (var i = 0; i < _events.length; i++) ...[
            _PlanCard(
              event: _events[i],
              wide: false,
              onTap: () => _preview(_events[i]),
            ),
            if (i != _events.length - 1) const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

String _countWord(int count) => count % 10 == 1 && count % 100 != 11
    ? 'план'
    : (count % 10 >= 2 &&
          count % 10 <= 4 &&
          (count % 100 < 12 || count % 100 > 14))
    ? 'плана'
    : 'планов';

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
    ),
    child: child,
  );
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _background,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: _ink),
          ),
        ),
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.event,
    required this.wide,
    required this.onTap,
  });
  final CalendarEvent event;
  final bool wide;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: wide ? _background : _surface,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          border: wide ? null : Border.all(color: _border),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${event.startTime}–${event.endTime}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: Color(
                  eventColors[event.color] ?? eventColors['neutral']!,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFF2E9E5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.calendar_today_outlined, color: _ink),
        ),
        const SizedBox(height: 16),
        const Text(
          'Этот день свободен',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Добавьте план, чтобы выделить время для важного.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: onCreate, child: const Text('Создать план')),
      ],
    ),
  );
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Column(
      children: [
        const Icon(Icons.warning_amber_rounded, color: _error, size: 30),
        const SizedBox(height: 12),
        const Text(
          'Не удалось загрузить планы',
          style: TextStyle(color: _error, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Проверьте соединение и попробуйте ещё раз.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    ),
  );
}

enum _PreviewAction { edit, delete }

Future<T?> _showPanel<T>(BuildContext context, Widget child) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: child,
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    ),
  );
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.sizeOf(context).width < 720)
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 22),
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          child,
        ],
      ),
    ),
  );
}

class _EventPreview extends StatelessWidget {
  const _EventPreview({required this.event});
  final CalendarEvent event;
  @override
  Widget build(BuildContext context) => _PanelFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'План',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: 'Закрыть',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Text(
          event.title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _prettyDate(DateTime.parse(event.date)),
          style: const TextStyle(color: _muted),
        ),
        const SizedBox(height: 22),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule_outlined, color: _muted),
                  const SizedBox(width: 8),
                  Text(
                    '${event.startTime}–${event.endTime}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Color(eventColors[event.color]!),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
              if (event.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(event.description, style: const TextStyle(color: _muted)),
              ],
              const SizedBox(height: 12),
              Text(
                'Метка: ${eventColorNames[event.color]}',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, _PreviewAction.delete),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Удалить план'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _error,
              side: const BorderSide(color: _error),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _PreviewAction.edit),
                child: const Text('Изменить план'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DeletePanel extends StatelessWidget {
  const _DeletePanel({required this.event});
  final CalendarEvent event;
  @override
  Widget build(BuildContext context) => _PanelFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _error),
            SizedBox(width: 10),
            Text(
              'Удалить план?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '«${event.title}» исчезнет из календаря. Время снова станет свободным.',
          style: const TextStyle(color: _muted),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: _error),
                child: const Text('Удалить'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.message,
    required this.action,
  });
  final String title;
  final String message;
  final String action;
  @override
  Widget build(BuildContext context) => _PanelFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(message, style: const TextStyle(color: _muted)),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(action),
          ),
        ),
      ],
    ),
  );
}

class _EventForm extends StatefulWidget {
  const _EventForm({
    required this.repository,
    required this.initialDate,
    this.event,
  });
  final EventRepository repository;
  final DateTime initialDate;
  final CalendarEvent? event;
  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _key = GlobalKey<FormState>();
  late final _date = TextEditingController(
    text: widget.event?.date ?? dayKey(widget.initialDate),
  );
  late final _start = TextEditingController(
    text: widget.event?.startTime ?? '09:00',
  );
  late final _end = TextEditingController(
    text: widget.event?.endTime ?? '10:00',
  );
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _description = TextEditingController(
    text: widget.event?.description ?? '',
  );
  late String _color = widget.event?.color ?? 'neutral';
  late int? _baseRevision = widget.event?.revision;
  bool _busy = false;
  String? _errorMessage;
  CalendarEvent? _conflict;

  @override
  void dispose() {
    for (final controller in [_date, _start, _end, _title, _description]) {
      controller.dispose();
    }
    super.dispose();
  }

  EventDraft get _draft => EventDraft(
    date: _date.text.trim(),
    startTime: _start.text.trim(),
    endTime: _end.text.trim(),
    title: _title.text,
    description: _description.text,
    color: _color,
  );

  Future<void> _save({int? replacementRevision}) async {
    if (_busy || !_key.currentState!.validate()) return;
    final draft = _draft;
    final error = validateEvent(draft);
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final event = widget.event == null
          ? await widget.repository.create(draft)
          : await widget.repository.update(
              widget.event!.id,
              draft,
              replacementRevision ?? _baseRevision!,
            );
      if (mounted) Navigator.pop(context, event);
    } on EventConflict catch (conflict) {
      if (mounted) setState(() => _conflict = conflict.current);
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Не удалось сохранить. Проверьте календарь: запись могла сохраниться. $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveConflict() async {
    final current = _conflict;
    if (current == null) return;
    final choice = await _showPanel<String>(
      context,
      _ConflictPanel(current: current),
    );
    if (!mounted) return;
    if (choice == 'load') {
      setState(() {
        _date.text = current.date;
        _start.text = current.startTime;
        _end.text = current.endTime;
        _title.text = current.title;
        _description.text = current.description;
        _color = current.color;
        _baseRevision = current.revision;
        _conflict = null;
      });
    } else if (choice == 'overwrite') {
      final confirmed = await _showPanel<bool>(
        context,
        const _ConfirmOverwrite(),
      );
      if (confirmed == true && mounted) {
        setState(() => _conflict = null);
        await _save(replacementRevision: current.revision);
      }
    }
  }

  Future<void> _checkCalendar() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final draft = _draft;
      final events = await widget.repository.list(draft.date);
      if (!mounted) return;
      for (final event in events) {
        if (event.startTime == draft.startTime &&
            event.endTime == draft.endTime &&
            event.title == draft.title.trim() &&
            event.description == draft.description.trim() &&
            event.color == draft.color) {
          Navigator.pop(context, event);
          return;
        }
      }
      setState(
        () => _errorMessage = 'План не найден в календаре. Проверьте данные и повторите сохранение.',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Не удалось проверить календарь. $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PanelFrame(
    child: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.pop(context);
              return null;
            },
          ),
        },
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.event == null ? 'Новый план' : 'Изменить план',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8E9E6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: _error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: _error),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: _busy ? null : _checkCalendar,
                        child: const Text('Проверить календарь'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_conflict != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8E9E6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'План изменён на другом устройстве',
                        style: TextStyle(
                          color: _error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _resolveConflict,
                        child: const Text('Посмотреть варианты'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _field(
                'Дата',
                _date,
                hint: 'ГГГГ-ММ-ДД',
                validator: (v) {
                  final parsed = DateTime.tryParse(v ?? '');
                  return parsed != null && dayKey(parsed) == v
                      ? null
                      : 'Укажите дату в формате ГГГГ-ММ-ДД';
                },
                autofocus: MediaQuery.sizeOf(context).width >= 720,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      'Начало',
                      _start,
                      hint: '09:00',
                      validator: _timeValidator,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      'Конец',
                      _end,
                      hint: '10:00',
                      validator: (value) {
                        final formatError = _timeValidator(value);
                        if (formatError != null) return formatError;
                        if (_timeValidator(_start.text) == null &&
                            value!.compareTo(_start.text) <= 0) {
                          return 'Позже начала';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(
                'Название',
                _title,
                hint: 'Например, прогулка',
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) return 'Укажите название';
                  if (value!.trim().length > 120) {
                    return 'Не более 120 символов';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _field(
                'Описание · необязательно',
                _description,
                hint: 'Что вы планируете?',
                maxLines: 2,
                validator: (value) => (value ?? '').length > 2000
                    ? 'Не более 2000 символов'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Цветовая метка',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final entry in eventColors.entries)
                    Semantics(
                      label: eventColorNames[entry.key],
                      selected: _color == entry.key,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => _color = entry.key),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 44,
                          height: 44,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _color == entry.key ? _accent : _border,
                              width: _color == entry.key ? 2 : 1,
                            ),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(entry.value),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Выбрано: ${eventColorNames[_color]}',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              widget.event == null
                                  ? 'Создать план'
                                  : 'Сохранить',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String? _timeValidator(String? value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value ?? '')
      ? null
      : 'Формат ЧЧ:ММ';

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool autofocus = false,
  }) => TextFormField(
    controller: controller,
    autofocus: autofocus,
    validator: validator,
    maxLines: maxLines,
    textInputAction: maxLines == 1
        ? TextInputAction.next
        : TextInputAction.done,
    onFieldSubmitted: (_) {
      if (controller == _description) _save();
    },
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: _background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
    ),
  );
}

class _ConflictPanel extends StatelessWidget {
  const _ConflictPanel({required this.current});
  final CalendarEvent current;
  @override
  Widget build(BuildContext context) => _PanelFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'План изменён на другом устройстве',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Актуальная версия: ${current.title}, ${current.startTime}–${current.endTime}. Ваши правки остаются в форме.',
          style: const TextStyle(color: _muted),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, 'load'),
            child: const Text('Загрузить актуальное'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, 'overwrite'),
            child: const Text('Сохранить мои изменения'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Вернуться к форме'),
          ),
        ),
      ],
    ),
  );
}

class _ConfirmOverwrite extends StatelessWidget {
  const _ConfirmOverwrite();
  @override
  Widget build(BuildContext context) => _PanelFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Заменить актуальный план?',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Версия с другого устройства будет заменена вашими изменениями.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Заменить'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
