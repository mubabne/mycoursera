import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../models.dart';
import 'widgets.dart';

class _ProgressData {
  _ProgressData(this.courses, this.skills, this.activities, this.attempts);

  final List<Course> courses;
  final List<Skill> skills;
  final List<Activity> activities;
  final List<Attempt> attempts;
}

/// Skills and the evidence behind them. Activity completion is shown separately.
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  late final Future<_ProgressData> _future = _load();

  Future<_ProgressData> _load() async => _ProgressData(
        await repo.courses(),
        await repo.skills(),
        await repo.activities(),
        await repo.attempts(),
      );

  void _showEvidence(Skill skill, _ProgressData d) {
    final byId = {for (final a in d.activities) a.id: a};
    final evidence = d.attempts.where((t) {
      final a = byId[t.activityId];
      return a != null && a.courseId == skill.courseId && a.skillKeys.contains(skill.key);
    }).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(child: Text(skill.name, style: Theme.of(context).textTheme.titleLarge)),
                SkillStatusChip(skill.status),
              ],
            ),
            if (skill.description.isNotEmpty) Text(skill.description),
            SectionHeader('Evidence (${evidence.length} attempts)'),
            if (evidence.isEmpty) const Text('No attempts on this skill yet.'),
            for (final t in evidence)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(verdictIcon(t.verdict)),
                title: Text(byId[t.activityId]?.title ?? ''),
                subtitle: Text([
                  [
                    if (t.createdAt != null) fmtDateTime(t.createdAt!),
                    t.verdict.label,
                    t.help.label,
                    t.evaluatedBy == 'ai' ? 'AI check' : 'self check',
                  ].join(' · '),
                  if (t.feedback.isNotEmpty) t.feedback,
                ].join('\n')),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: Loader<_ProgressData>(
        future: _future,
        builder: (context, d) {
          if (d.courses.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: InfoCard(title: 'No courses yet', body: 'Progress shows up here once you start a course.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final c in d.courses) _courseCard(context, c, d)],
          );
        },
      ),
    );
  }

  Widget _courseCard(BuildContext context, Course c, _ProgressData d) {
    final acts = d.activities.where((a) => a.courseId == c.id && a.origin != Origin.adaptive).toList();
    final done = acts.where((a) => a.isDone).length;
    final skills = d.skills.where((s) => s.courseId == c.id).toList();
    int count(SkillStatus s) => skills.where((x) => x.status == s).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Activities completed: $done of ${acts.length}'),
            if (skills.isNotEmpty)
              Text(
                'Skills: ${count(SkillStatus.demonstrated)} demonstrated · '
                '${count(SkillStatus.practicing)} practicing · ${count(SkillStatus.unassessed)} unassessed',
              ),
            const SizedBox(height: 8),
            if (skills.isEmpty) const Text('This course has no skills defined.'),
            for (final s in skills)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                subtitle: s.description.isEmpty ? null : Text(s.description),
                trailing: SkillStatusChip(s.status),
                onTap: () => _showEvidence(s, d),
              ),
          ],
        ),
      ),
    );
  }
}
