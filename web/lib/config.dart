import 'dart:convert';

import 'package:flutter/services.dart';

/// Values come from env.json, which is bundled as an asset so a plain `flutter run` picks it up.
/// `--dart-define=SUPABASE_URL=...` (or `--dart-define-from-file`) still overrides it.
class AppConfig {
  static String supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
  static String supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> load() async {
    if (isConfigured) return;
    try {
      final env = jsonDecode(await rootBundle.loadString('env.json')) as Map<String, dynamic>;
      supabaseUrl = (env['SUPABASE_URL'] as String? ?? '').trim();
      supabaseAnonKey = (env['SUPABASE_ANON_KEY'] as String? ?? '').trim();
    } catch (_) {
      // Missing or malformed env.json: main() shows the setup screen.
    }
  }
}
