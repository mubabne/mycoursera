import 'dart:convert';

import '../models.dart';

/// Pulls the JSON object out of an AI reply: strips a surrounding ``` fence and
/// any text before the first "{" or after the last "}".
String extractJsonObject(String raw) {
  var s = raw.trim();
  if (s.startsWith('```')) {
    final newline = s.indexOf('\n');
    s = newline == -1 ? '' : s.substring(newline + 1);
    final close = s.lastIndexOf('```');
    if (close != -1) s = s.substring(0, close);
    s = s.trim();
  }
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start == -1 || end <= start) return s;
  return s.substring(start, end + 1);
}

/// What an external AI said about an attempt.
class AiVerdict {
  const AiVerdict({required this.verdict, required this.feedback, required this.gap});

  final Verdict verdict;
  final String feedback;
  final String gap;
}

/// Reads {"verdict": "...", "feedback": "...", "gap": "..."}; null if unreadable.
AiVerdict? parseAiVerdict(String raw) {
  try {
    final decoded = jsonDecode(extractJsonObject(raw));
    if (decoded is! Map) return null;
    final verdict = Verdict.tryDb(decoded['verdict']?.toString().trim().toLowerCase());
    if (verdict == null) return null;
    return AiVerdict(
      verdict: verdict,
      feedback: (decoded['feedback'] ?? '').toString().trim(),
      gap: (decoded['gap'] ?? '').toString().trim(),
    );
  } on FormatException {
    return null;
  }
}
