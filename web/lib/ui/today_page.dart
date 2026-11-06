import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../logic/rules.dart';
import '../models.dart';
import 'session_page.dart';
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
        ],
      ),
      body: Loader<_TodayData>(future: _future, builder: (context, d) => _body(context, d)),
    );
  }

  Widget _body(BuildContext context, _TodayData d) {
    final now = DateTime.now();
    final courses = {for (final c in d.courses) c.id: c};
    final next = pickNextAction(d.activities, courses, now);
    final deadlines = upcomingDeadlines(d.activities.where((a) => courses.containsKey(a.courseId)).toList(), now);
    final error = Theme.of(context).colorScheme.error;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        const SectionHeader('Deadlines and reminders (next 7 days)'),
        if (deadlines.isEmpty) const Text('Nothing due.'),
        for (final a in deadlines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              a.dueAt!.isBefore(now) ? Icons.warning_amber : Icons.event,
              color: a.dueAt!.isBefore(now) ? error : null,
            ),
            title: Text(a.title),
            subtitle: Text(
              '${courses[a.courseId]?.title ?? ''} · '
              '${a.dueAt!.isBefore(now) ? 'overdue since' : 'due'} ${describeDue(a.dueAt!, now)}'
              ' · ${fmtMinutes(a.estMinutes)}',
            ),
            onTap: () => _open(a),
          ),
        const SectionHeader('Up next in each course'),
        for (final c in d.courses) _upNext(c, d.activities),
      ],
    );
  }

  Widget _upNext(Course c, List<Activity> all) {
    final next = nextEligible(all.where((a) => a.courseId == c.id).toList());
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(c.kind == CourseKind.university ? Icons.account_balance_outlined : Icons.school_outlined),
      title: Text(next?.title ?? 'Nothing open'),
      subtitle: Text(next == null ? c.title : '${c.title} · ${fmtMinutes(next.estMinutes)}'),
      onTap: next == null ? null : () => _open(next),
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
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NEXT ACTION', style: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 8),
            Text(a.title, style: text.headlineSmall?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              '${course.title} · ${a.kind.label} · ${fmtMinutes(a.estMinutes)}',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text('Why: ${action.reason}', style: TextStyle(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onOpen(a),
              icon: const Icon(Icons.play_arrow),
              label: Text(a.state == ActivityState.inProgress ? 'Resume' : 'Start'),
            ),
          ],
        ),
      ),
    );
  }
}
