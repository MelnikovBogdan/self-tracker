import 'package:flutter/material.dart';

import '../activities/activity_module.dart';
import '../api/api_client.dart';
import '../auth/session_controller.dart';
import 'profile_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.registry});
  final SessionController session;
  final ActivityRegistry registry;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selected = 0;
  bool _signingOut = false;

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dashboard_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Активности появятся здесь',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Основа приложения готова для подключения модулей.'),
            if (widget.session.connectionNotice != null) ...[
              const SizedBox(height: 20),
              Text(widget.session.connectionNotice!),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Главная',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Профиль',
      ),
      for (final module in widget.registry.modules)
        NavigationDestination(icon: Icon(module.icon), label: module.title),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final page = _page();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Self Tracker'),
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
                    NavigationRail(
                      selectedIndex: _selected,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (index) =>
                          setState(() => _selected = index),
                      destinations: [
                        for (final destination in destinations)
                          NavigationRailDestination(
                            icon: destination.icon,
                            selectedIcon: destination.selectedIcon,
                            label: Text(destination.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: page),
                  ],
                )
              : page,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selected,
                  destinations: destinations,
                  onDestinationSelected: (index) =>
                      setState(() => _selected = index),
                ),
        );
      },
    );
  }
}
