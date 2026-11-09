import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../models.dart';
import 'course_page.dart';
import 'import_page.dart';
import 'theme.dart';
import 'widgets.dart';

class _CoursesData {
  _CoursesData(this.courses, this.activities);

  final List<Course> courses;
  final List<Activity> activities;
}

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  late Future<_CoursesData> _future = _load();

  Future<_CoursesData> _load() async => _CoursesData(await repo.courses(), await repo.activities());

  void _reload() => setState(() => _future = _load());

  Future<void> _openCourse(String courseId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CoursePage(courseId: courseId)));
    if (mounted) _reload();
  }

  Future<void> _newCourse() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        Widget option(String value, IconData icon, Color color, String title, String subtitle) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: IconBadge(icon: icon, color: color, size: 44),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(subtitle),
              trailing: Icon(Icons.chevron_right, color: scheme.outline),
              onTap: () => Navigator.pop(context, value),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Start a new course', style: Theme.of(context).textTheme.titleLarge),
                ),
                option('wizard', Icons.auto_awesome_outlined, scheme.primary, 'Plan a course with AI',
                    'Answer a few questions, copy the prompt, paste the plan back.'),
                option('university', Icons.account_balance_outlined, const Color(0xFF059669), 'University course',
                    'Track labs, assignments and deadlines; catch up when you miss one.'),
                option('import', Icons.data_object, const Color(0xFFD97706), 'Import plan JSON',
                    'You already have a plan in the MyCoursera format.'),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;

    String? courseId;
    if (choice == 'wizard') {
      courseId = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const PlanWizardPage()));
    } else if (choice == 'import') {
      courseId = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ImportPage()));
    } else if (choice == 'university') {
      final title = await _askTitle();
      if (title == null || title.isEmpty) return;
      try {
        courseId = (await repo.createCourse(title: title, kind: CourseKind.university)).id;
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
    }
    if (!mounted) return;
    if (courseId != null) {
      await _openCourse(courseId);
    } else {
      _reload();
    }
  }

  Future<String?> _askTitle() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('University course'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Course name', hintText: 'e.g. Database Systems'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newCourse,
        icon: const Icon(Icons.add),
        label: const Text('New course'),
      ),
      body: Loader<_CoursesData>(
        future: _future,
        builder: (context, d) {
          if (d.courses.isEmpty) {
            return PageList(
              children: [
                InfoCard(
                  icon: Icons.school_outlined,
                  title: 'No courses yet',
                  body: 'Start with your AI course: plan it with AI, then paste the plan.',
                  action: FilledButton.icon(
                    onPressed: _newCourse,
                    icon: const Icon(Icons.add),
                    label: const Text('New course'),
                  ),
                ),
              ],
            );
          }
          return PageList(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final c in d.courses) _courseCard(c, d.activities.where((a) => a.courseId == c.id).toList()),
            ],
          );
        },
      ),
    );
  }

  Widget _courseCard(Course c, List<Activity> acts) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = acts.where((a) => a.origin != Origin.adaptive).length;
    final done = acts.where((a) => a.origin != Origin.adaptive && a.isDone).length;
    final ratio = total == 0 ? 0.0 : done / total;
    final color = courseColor(context, c.id);
    return Card(
      child: InkWell(
        onTap: () => _openCourse(c.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 5, color: color),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(
                        icon: c.kind == CourseKind.university ? Icons.account_balance_outlined : Icons.school_outlined,
                        color: color,
                        size: 44,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(c.kind.label,
                                style: text.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.outline),
                    ],
                  ),
                  if (c.goal.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      c.goal,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: ProgressBar(value: ratio, color: color)),
                      const SizedBox(width: 12),
                      Text('${(ratio * 100).round()}%',
                          style: text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('$done of $total activities done',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
