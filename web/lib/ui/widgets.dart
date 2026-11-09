import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'theme.dart';

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
          body: snap.hasError ? ErrorView(error: snap.error!) : const Center(child: CircularProgressIndicator()),
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
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBadge(icon: Icons.cloud_off_outlined, color: scheme.error, size: 56),
              const SizedBox(height: 16),
              Text('Something went wrong', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scrolling page body, centred and capped in width so it reads well on web too.
class PageList extends StatelessWidget {
  const PageList({
    super.key,
    required this.children,
    this.maxWidth = 760,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32),
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: padding,
          physics: const AlwaysScrollableScrollPhysics(),
          children: children,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing, this.icon});

  final String text;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10, left: 4, right: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.2,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A rounded square holding an icon on a soft tint of [color].
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// Empty states and hints: a friendly icon, a title and a sentence.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_outline,
    this.action,
  });

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: scheme.primary, size: 44),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(body, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  if (action != null) ...[const SizedBox(height: 12), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled block of text (objective, lesson, task...) in its own card.
class TextBlock extends StatelessWidget {
  const TextBlock({super.key, required this.title, required this.text, this.icon});

  final String title;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon ?? Icons.notes, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
          ],
        ),
      ),
    );
  }
}

/// A card with a small heading, for grouping controls.
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.title, required this.children, this.icon, this.subtitle});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  IconBadge(icon: icon!, color: scheme.primary, size: 32),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      if (subtitle != null)
                        Text(subtitle!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A small rounded label with an optional icon, e.g. "45 min" or "Due tomorrow".
class MetaPill extends StatelessWidget {
  const MetaPill(this.label, {super.key, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color == null ? scheme.surfaceContainerHigh : color!.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded linear progress bar.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color, this.height = 8});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        color: color ?? scheme.primary,
        backgroundColor: (color ?? scheme.primary).withValues(alpha: 0.12),
      ),
    );
  }
}

/// A number with a label, used in summary rows.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: (color ?? scheme.primary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: text.titleLarge?.copyWith(color: color ?? scheme.primary)),
          const SizedBox(height: 2),
          Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// One activity as a tappable row: coloured kind icon, title, meta line, optional trailing.
class ActivityTile extends StatelessWidget {
  const ActivityTile({
    super.key,
    required this.activity,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.warn = false,
  });

  final Activity activity;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Highlights the row (overdue or missed).
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final a = activity;
    final color = warn ? scheme.error : kindColor(context, a.kind.db);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconBadge(
                    icon: a.isDone ? Icons.check_rounded : kindIcon(a.kind), color: a.isDone ? scheme.primary : color),
                if (warn)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: a.isDone ? TextDecoration.lineThrough : null,
                      color: a.isDone ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: warn ? scheme.error : scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing! else if (onTap != null) Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
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
    final (Color color, IconData icon) = switch (status) {
      SkillStatus.unassessed => (scheme.outline, Icons.radio_button_unchecked),
      SkillStatus.practicing => (const Color(0xFFD97706), Icons.trending_up),
      SkillStatus.demonstrated => (const Color(0xFF059669), Icons.verified_outlined),
    };
    return MetaPill(status.label, icon: icon, color: color);
  }
}

IconData kindIcon(ActivityKind k) => switch (k) {
      ActivityKind.lesson => Icons.menu_book_outlined,
      ActivityKind.exercise => Icons.edit_note,
      ActivityKind.check => Icons.fact_check_outlined,
      ActivityKind.lab => Icons.science_outlined,
      ActivityKind.assignment => Icons.assignment_outlined,
      ActivityKind.exam => Icons.quiz_outlined,
      ActivityKind.project => Icons.rocket_launch_outlined,
    };

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

Color verdictColor(BuildContext context, Verdict v) => switch (v) {
      Verdict.pass => const Color(0xFF059669),
      Verdict.fail => const Color(0xFFD97706),
      Verdict.uncertain => Theme.of(context).colorScheme.outline,
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
        if (courses.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No courses yet.')),
        for (final c in courses)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, c),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                IconBadge(
                  icon: c.kind == CourseKind.university ? Icons.account_balance_outlined : Icons.school_outlined,
                  color: courseColor(context, c.id),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(c.title)),
              ],
            ),
          ),
      ],
    ),
  );
}

const monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4);
