import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/repo.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  repo = Repo(Supabase.instance.client);
  runApp(const MyCourseraApp());
}

ThemeData _theme(Brightness brightness) => ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: brightness,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );

class MyCourseraApp extends StatelessWidget {
  const MyCourseraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyCoursera',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const AuthGate(),
    );
  }
}

/// Shows the login page or the app, following Supabase's auth state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) => auth.currentSession == null ? const LoginPage() : const HomeShell(),
    );
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: const Text(
                'Supabase is not configured.\n\n'
                '1. Copy env.example.json to env.json and fill in your project URL and anon key.\n'
                '2. Run: flutter run -d chrome --dart-define-from-file=env.json',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
