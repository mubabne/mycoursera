import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../models.dart';
import 'course_page.dart';
import 'import_page.dart';
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Plan a course with AI'),
              subtitle: const Text('Answer a few questions, copy the prompt, paste the plan back.'),
              onTap: () => Navigator.pop(context, 'wizard'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('University course'),
              subtitle: const Text('Track labs, assignments and deadlines; catch up when you miss one.'),
              onTap: () => Navigator.pop(context, 'university'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Import plan JSON'),
              subtitle: const Text('You already have a plan in the MyCoursera format.'),
              onTap: () => Navigator.pop(context, 'import'),
            ),
          ],
        ),
      ),
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
            return const Padding(
              padding: EdgeInsets.all(16),
              child: InfoCard(
                icon: Icons.school_outlined,
                title: 'No courses yet',
                body: 'Tap "New course". Start with your AI course: plan it with AI, then paste the plan.',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              for (final c in d.courses) _courseCard(c, d.activities.where((a) => a.courseId == c.id).toList()),
            ],
          );
        },
      ),
    );
  }

  Widget _courseCard(Course c, List<Activity> acts) {
    final total = acts.where((a) => a.origin != Origin.adaptive).length;
    final done = acts.where((a) => a.origin != Origin.adaptive && a.isDone).length;
    return Card(
      child: ListTile(
        leading: Icon(c.kind == CourseKind.university ? Icons.account_balance_outlined : Icons.school_outlined),
        title: Text(c.title),
        subtitle: Text([
          c.kind.label,
          if (c.goal.isNotEmpty) c.goal,
          '$done of $total done',
        ].join(' · ')),
        trailing: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(value: total == 0 ? 0 : done / total, strokeWidth: 4),
        ),
        onTap: () => _openCourse(c.id),
      ),
    );
  }
}
