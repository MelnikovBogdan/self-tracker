import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.session});
  final SessionController session;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _name = TextEditingController();
  Profile? _profile;
  Profile? _conflict;
  bool _busy = false;
  String? _message;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _synced = false;
    });
    try {
      final current = await widget.session.api.getProfile(
        widget.session.token!,
      );
      if (!mounted) return;
      setState(() {
        _profile = current;
        _conflict = null;
        _name.text = current.displayName;
        _synced = true;
      });
    } on UnauthorizedException {
      await widget.session.sessionExpired();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() {
        _message = 'Укажите имя.';
        _synced = false;
      });
      return;
    }
    if (_profile == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _synced = false;
      _conflict = null;
    });
    try {
      final updated = await widget.session.api.updateProfile(
        widget.session.token!,
        name,
        _profile!.revision,
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _name.text = updated.displayName;
        _synced = true;
      });
    } on ConflictException catch (error) {
      if (mounted) {
        setState(() {
          _conflict = error.current;
          _message = error.message;
        });
      }
    } on UnauthorizedException {
      await widget.session.sessionExpired();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loadConflict() {
    final current = _conflict;
    if (current == null) return;
    setState(() {
      _profile = current;
      _name.text = current.displayName;
      _conflict = null;
      _message = null;
      _synced = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Профиль', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            if (_profile == null && _busy)
              const Center(child: CircularProgressIndicator()),
            if (_profile != null) ...[
              TextField(
                controller: _name,
                enabled: !_busy,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Отображаемое имя',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_synced) setState(() => _synced = false);
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Сохранить'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text('Обновить'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _busy
                    ? 'Связь с сервером…'
                    : _synced
                    ? 'Синхронизировано'
                    : 'Изменение не синхронизировано',
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_conflict != null) ...[
              const SizedBox(height: 12),
              Text('На другом устройстве сохранено: ${_conflict!.displayName}'),
              TextButton(
                onPressed: _loadConflict,
                child: const Text('Загрузить актуальное значение'),
              ),
            ],
            if (_profile == null && !_busy) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _refresh,
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
