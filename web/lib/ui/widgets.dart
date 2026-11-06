import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';

/// Loads [future] inside a page body: spinner, error, or [builder].
class Loader<T extends Object> extends StatelessWidget {
  const Loader({super.key, required this.future, required this.builder});

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!);
        final data = snap.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return builder(context, data);
      },
    );
  }
}

/// Like [Loader], for a whole route: shows a Scaffold while loading or on error.
class RouteLoader<T extends Object> extends StatelessWidget {
  const RouteLoader({super.key, required this.future, required this.builder, this.title = ''});

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final String title;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        final data = snap.data;
        if (!snap.hasError && data != null) return builder(context, data);
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: snap.hasError
              ? ErrorView(error: snap.error!)
              : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Something went wrong:\n$error',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.title, required this.body, this.icon = Icons.info_outline});

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(body),
      ),
    );
  }
}

/// A titled block of text (objective, lesson, task...).
class TextBlock extends StatelessWidget {
  const TextBlock({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(text),
        ],
      ),
    );
  }
}

class SkillStatusChip extends StatelessWidget {
  const SkillStatusChip(this.status, {super.key});

  final SkillStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      SkillStatus.unassessed => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      SkillStatus.practicing => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      SkillStatus.demonstrated => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status.label, style: TextStyle(color: fg, fontSize: 12)),
    );
  }
}

IconData stateIcon(ActivityState s) => switch (s) {
      ActivityState.notStarted => Icons.radio_button_unchecked,
      ActivityState.inProgress => Icons.timelapse,
      ActivityState.completed => Icons.check_circle,
      ActivityState.missed => Icons.event_busy,
    };

IconData verdictIcon(Verdict v) => switch (v) {
      Verdict.pass => Icons.check_circle_outline,
      Verdict.fail => Icons.replay,
      Verdict.uncertain => Icons.help_outline,
    };

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Error: $error'),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

Future<void> copyText(BuildContext context, String text, {String message = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessage(context, message);
}

/// Date then time picker. Returns null if either is cancelled.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final base = initial ?? DateTime(now.year, now.month, now.day + 1, 9);
  final date = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: now.subtract(const Duration(days: 365)),
    lastDate: now.add(const Duration(days: 730)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Lets you pick one course from a list.
Future<Course?> pickCourse(BuildContext context, List<Course> courses, {String title = 'Choose a course'}) {
  return showDialog<Course>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        if (courses.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No courses yet.')),
        for (final c in courses)
          SimpleDialogOption(onPressed: () => Navigator.pop(context, c), child: Text(c.title)),
      ],
    ),
  );
}

const monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 13);
