import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../logic/rules.dart';
import '../models.dart';
import 'session_page.dart';
import 'theme.dart';
import 'widgets.dart';

class _TodayData {
  _TodayData(this.courses, this.activities);

  final List<Course> courses;
  final List<Activity> activities;
}

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late Future<_TodayData> _future = _load();

  Future<_TodayData> _load() async {
    final courses = await repo.courses();
    final activities = await repo.activities();
    return _TodayData(courses.where((c) => c.status == 'active').toList(), activities);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Activity a) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionPage(activityId: a.id)));
    if (mounted) _reload();
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _reload),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Loader<_TodayData>(
        future: _future,
        builder: (context, d) => RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: _body(context, d),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, _TodayData d) {
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final courses = {for (final c in d.courses) c.id: c};
    final next = pickNextAction(d.activities, courses, now);
    final deadlines = upcomingDeadlines(d.activities.where((a) => courses.containsKey(a.courseId)).toList(), now);

    return PageList(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fmtDate(now).toUpperCase(),
                  style: text.labelMedium?.copyWith(color: scheme.primary, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(_greeting(now), style: text.headlineMedium),
            ],
          ),
        ),
        if (d.courses.isEmpty)
          const InfoCard(
            icon: Icons.school_outlined,
            title: 'No courses yet',
            body: 'Open the Courses tab to plan a course with AI or add a university course.',
          ),
        if (next != null) _NextActionCard(action: next, course: courses[next.activity.courseId]!, onOpen: _open),
        if (next == null && d.courses.isNotEmpty)
          const InfoCard(
            icon: Icons.celebration_outlined,
            title: 'All caught up',
            body: 'Nothing is waiting right now. Add items or update a plan.',
          ),
        SectionHeader('Deadlines · next 7 days', icon: Icons.event_outlined),
        if (deadlines.isEmpty)
          const _QuietRow(icon: Icons.event_available_outlined, text: 'Nothing due. Enjoy the breathing room.')
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final a in deadlines) _deadlineRow(context, a, courses[a.courseId], now),
                ],
              ),
            ),
          ),
        if (d.courses.isNotEmpty) ...[
          const SectionHeader('Up next in each course', icon: Icons.playlist_play),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [for (final c in d.courses) _upNext(context, c, d.activities)]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _deadlineRow(BuildContext context, Activity a, Course? course, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = a.dueAt!.isBefore(now);
    final due = a.dueAt!;
    return InkWell(
      onTap: () => _open(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _DateBadge(date: due, color: overdue ? scheme.error : kindColor(context, a.kind.db)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${course?.title ?? ''} · ${fmtMinutes(a.estMinutes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MetaPill(
              overdue ? 'Overdue' : describeDue(due, now),
              icon: overdue ? Icons.warning_amber_rounded : Icons.schedule,
              color: overdue ? scheme.error : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _upNext(BuildContext context, Course c, List<Activity> all) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final next = nextEligible(all.where((a) => a.courseId == c.id).toList());
    final color = courseColor(context, c.id);
    return InkWell(
      onTap: next == null ? null : () => _open(next),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            IconBadge(
              icon: c.kind == CourseKind.university ? Icons.account_balance_outlined : Icons.school_outlined,
              color: color,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text(
                    next?.title ?? 'Nothing open',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: next == null ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ],
              ),
            ),
            if (next != null) ...[
              MetaPill(fmtMinutes(next.estMinutes), icon: Icons.timer_outlined),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuietRow extends StatelessWidget {
  const _QuietRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}

/// A calendar-style "13 / NOV" badge.
class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date, required this.color});

  final DateTime date;
  final Color color;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${date.day}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17, height: 1.1)),
          Text(_months[date.month - 1],
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({required this.action, required this.course, required this.onOpen});

  final NextAction action;
  final Course course;
  final void Function(Activity) onOpen;

  @override
  Widget build(BuildContext context) {
    final a = action.activity;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onPrimary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.7)!],
        ),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: fg),
                      const SizedBox(width: 4),
                      Text('NEXT UP',
                          style: text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ],
                  ),
                ),
                const Spacer(),
                Icon(kindIcon(a.kind), color: fg.withValues(alpha: 0.85)),
              ],
            ),
            const SizedBox(height: 16),
            Text(a.title, style: text.headlineSmall?.copyWith(color: fg)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (icon, label) in [
                  (Icons.school_outlined, course.title),
                  (kindIcon(a.kind), a.kind.label),
                  (Icons.timer_outlined, fmtMinutes(a.estMinutes)),
                ])
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: fg),
                        const SizedBox(width: 5),
                        Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              action.reason,
              style: text.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.9), height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: scheme.primary),
              onPressed: () => onOpen(a),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(a.state == ActivityState.inProgress ? 'Resume' : 'Start'),
            ),
          ],
        ),
      ),
    );
  }
}
