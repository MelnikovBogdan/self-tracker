import 'package:flutter/material.dart';

import '../activities/activity_module.dart';
import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../calendar/calendar_page.dart';
import '../calendar/events.dart';
import 'profile_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.session,
    required this.registry,
    this.eventRepository,
  });
  final SessionController session;
  final ActivityRegistry registry;
  final EventRepository? eventRepository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selected = 0;
  bool _signingOut = false;
  late final EventRepository _events =
      widget.eventRepository ?? MemoryEventRepository();
  final _calendarKey = GlobalKey<CalendarPageState>();

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.session.logout();
    } on UnauthorizedException {
      await widget.session.sessionExpired();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Widget _page() {
    if (_selected == 1) return ProfilePage(session: widget.session);
    if (_selected >= 2) {
      return widget.registry.modules[_selected - 2].home(context);
    }
    return CalendarPage(key: _calendarKey, repository: _events);
  }

  Widget _sidebar() => Container(
    width: 238,
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
    decoration: const BoxDecoration(
      color: Color(0xFFFFFEFC),
      border: Border(right: BorderSide(color: Color(0xFFE5E5DF))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFF2E9E5),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: Color(0xFF343B38),
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Планировщик',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF343B38),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
        const Padding(
          padding: EdgeInsets.only(left: 10, bottom: 16),
          child: Text(
            'ЛИЧНОЕ ПРОСТРАНСТВО',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF5F6862),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _SidebarItem(
          icon: Icons.calendar_today_outlined,
          label: 'Календарь',
          selected: _selected == 0,
          onTap: () => setState(() => _selected = 0),
        ),
        for (
          var index = 0;
          index < widget.registry.modules.length;
          index++
        ) ...[
          const SizedBox(height: 6),
          _SidebarItem(
            icon: widget.registry.modules[index].icon,
            label: widget.registry.modules[index].title,
            selected: _selected == index + 2,
            onTap: () => setState(() => _selected = index + 2),
          ),
        ],
        const Spacer(),
        _SidebarItem(
          icon: Icons.person_outline,
          label: 'Профиль',
          selected: _selected == 1,
          onTap: () => setState(() => _selected = 1),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _signingOut ? null : _logout,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Выйти'),
        ),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Планы помогают заранее выделить время для важного.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFF5F6862),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final page = _page();
        return Scaffold(
          appBar: wide || _selected == 0
              ? null
              : AppBar(
                  title: const Text('Планировщик'),
                  actions: [
                    IconButton(
                      tooltip: 'Выйти',
                      onPressed: _signingOut ? null : _logout,
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
          body: wide
              ? Row(
                  children: [
                    _sidebar(),
                    Expanded(child: page),
                  ],
                )
              : _selected == 0
              ? SafeArea(child: page)
              : page,
          bottomNavigationBar: wide
              ? null
              : Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFEFC),
                    border: Border(top: BorderSide(color: Color(0xFFE5E5DF))),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        _BottomItem(
                          icon: Icons.calendar_today_outlined,
                          label: 'Календарь',
                          selected: _selected == 0,
                          onTap: () => setState(() => _selected = 0),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (_selected != 0) setState(() => _selected = 0);
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _calendarKey.currentState?.createPlan(),
                              );
                            },
                            child: const SizedBox(
                              height: 78,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(0xFF805F58),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(16),
                                      ),
                                    ),
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(
                                        Icons.add,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Новый план',
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF5F6862),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _BottomItem(
                          icon: Icons.person_outline,
                          label: 'Профиль',
                          selected: _selected == 1,
                          onTap: () => setState(() => _selected = 1),
                        ),
                        for (
                          var index = 0;
                          index < widget.registry.modules.length;
                          index++
                        )
                          _BottomItem(
                            icon: widget.registry.modules[index].icon,
                            label: widget.registry.modules[index].title,
                            selected: _selected == index + 2,
                            onTap: () => setState(() => _selected = index + 2),
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFF2E9E5) : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? const Color(0xFF805F58)
                    : const Color(0xFF343B38),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF805F58)
                        : const Color(0xFF343B38),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 78,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFF805F58)
                  : const Color(0xFF5F6862),
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? const Color(0xFF805F58)
                    : const Color(0xFF5F6862),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
