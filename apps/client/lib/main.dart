import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'activities/activity_module.dart';
import 'api/api_client.dart';
import 'auth/session_controller.dart';
import 'auth/session_store.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  SessionController? _session;
  ApiClient? _api;
  String? _configurationError;

  @override
  void initState() {
    super.initState();
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    final url = configuredUrl.isNotEmpty
        ? configuredUrl
        : Platform.isAndroid
        ? 'http://10.0.2.2:3000'
        : 'http://127.0.0.1:3000';
    try {
      _api = ApiClient(baseUri: Uri.parse(url));
      _session = SessionController(_api!, SecureSessionStore());
      _session!.restore();
    } catch (error) {
      _configurationError = kReleaseMode
          ? 'Для сборки укажите HTTPS-адрес API через API_BASE_URL.'
          : 'Некорректный адрес API: $error';
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self Tracker',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF42687B),
        useMaterial3: true,
      ),
      home: _configurationError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _configurationError!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          : AnimatedBuilder(
              animation: _session!,
              builder: (context, _) => switch (_session!.state) {
                SessionState.loading => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
                SessionState.signedOut => LoginPage(session: _session!),
                SessionState.signedIn => HomeShell(
                  session: _session!,
                  registry: activityRegistry,
                ),
              },
            ),
    );
  }
}
