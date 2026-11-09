import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../models.dart';
import 'theme.dart';
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
                leading: IconBadge(icon: verdictIcon(t.verdict), color: verdictColor(context, t.verdict)),
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
            return const PageList(
              children: [
                InfoCard(
                  icon: Icons.insights_outlined,
                  title: 'No courses yet',
                  body: 'Progress shows up here once you start a course.',
                ),
              ],
            );
          }
          final total = d.activities.where((a) => a.origin != Origin.adaptive).length;
          final done = d.activities.where((a) => a.origin != Origin.adaptive && a.isDone).length;
          final shown = d.skills.where((s) => s.status == SkillStatus.demonstrated).length;
          final passes = d.attempts.where((t) => t.verdict == Verdict.pass).length;
          return PageList(
            children: [
              Row(
                children: [
                  Expanded(child: StatTile(value: '$done/$total', label: 'activities done')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(value: '$shown', label: 'skills shown', color: const Color(0xFF059669)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(value: '$passes', label: 'passed checks', color: const Color(0xFFD97706)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final c in d.courses) _courseCard(context, c, d),
            ],
          );
        },
      ),
    );
  }

  Widget _courseCard(BuildContext context, Course c, _ProgressData d) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = courseColor(context, c.id);
    final acts = d.activities.where((a) => a.courseId == c.id && a.origin != Origin.adaptive).toList();
    final done = acts.where((a) => a.isDone).length;
    final skills = d.skills.where((s) => s.courseId == c.id).toList();
    int count(SkillStatus s) => skills.where((x) => x.status == s).length;
    const green = Color(0xFF059669);
    const amber = Color(0xFFD97706);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: c.kind == CourseKind.university ? Icons.account_balance_outlined : Icons.school_outlined,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(c.title, style: text.titleLarge)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Activities', style: text.labelLarge),
                const Spacer(),
                Text('$done of ${acts.length}', style: text.labelLarge?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 6),
            ProgressBar(value: acts.isEmpty ? 0 : done / acts.length, color: color),
            if (skills.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Skills', style: text.labelLarge),
                  const Spacer(),
                  Text('${count(SkillStatus.demonstrated)} of ${skills.length} demonstrated',
                      style: text.labelLarge?.copyWith(color: green)),
                ],
              ),
              const SizedBox(height: 6),
              _SkillBar(
                demonstrated: count(SkillStatus.demonstrated),
                practicing: count(SkillStatus.practicing),
                total: skills.length,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _legend(context, green, '${count(SkillStatus.demonstrated)} demonstrated'),
                  _legend(context, amber, '${count(SkillStatus.practicing)} practicing'),
                  _legend(context, scheme.outlineVariant, '${count(SkillStatus.unassessed)} unassessed'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (skills.isEmpty)
              Text('This course has no skills defined.', style: TextStyle(color: scheme.onSurfaceVariant)),
            for (final s in skills)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showEvidence(s, d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                            if (s.description.isNotEmpty)
                              Text(s.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SkillStatusChip(s.status),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

/// A stacked bar: demonstrated (green), practicing (amber), the rest unassessed.
class _SkillBar extends StatelessWidget {
  const _SkillBar({required this.demonstrated, required this.practicing, required this.total});

  final int demonstrated;
  final int practicing;
  final int total;

  @override
  Widget build(BuildContext context) {
    final rest = total - demonstrated - practicing;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            if (demonstrated > 0) Expanded(flex: demonstrated, child: Container(color: const Color(0xFF059669))),
            if (practicing > 0) Expanded(flex: practicing, child: Container(color: const Color(0xFFD97706))),
            if (rest > 0) Expanded(flex: rest, child: Container(color: Theme.of(context).colorScheme.outlineVariant)),
          ],
        ),
      ),
    );
  }
}
