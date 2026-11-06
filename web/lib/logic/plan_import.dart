// Plan JSON (schemaVersion 1): parse, validate, compare with an existing course, export.
// Format: docs/SPEC.md section 7.

import 'dart:convert';

import '../models.dart';
import 'json_util.dart';

const supportedSchemaVersion = 1;

class PlanSkill {
  const PlanSkill({required this.id, required this.name, required this.description});

  final String id;
  final String name;
  final String description;
}

class PlanActivity {
  const PlanActivity({
    required this.id,
    required this.title,
    required this.kind,
    required this.objective,
    required this.content,
    required this.task,
    required this.criteria,
    required this.estMinutes,
    required this.prerequisites,
    required this.skills,
    this.dueAt,
  });

  final String id;
  final String title;
  final ActivityKind kind;
  final String objective;
  final String content;
  final String task;
  final String criteria;
  final int estMinutes;
  final List<String> prerequisites;
  final List<String> skills;
  final DateTime? dueAt;
}

class PlanMilestone {
  const PlanMilestone({required this.id, required this.title, required this.activities});

  final String id;
  final String title;
  final List<PlanActivity> activities;
}

class PlanDraft {
  const PlanDraft({
    required this.title,
    required this.kind,
    required this.goal,
    required this.weeklyHours,
    required this.skills,
    required this.milestones,
  });

  final String title;
  final CourseKind kind;
  final String goal;
  final double weeklyHours;
  final List<PlanSkill> skills;
  final List<PlanMilestone> milestones;

  List<PlanActivity> get allActivities => [for (final m in milestones) ...m.activities];

  int get totalMinutes => allActivities.fold<int>(0, (sum, a) => sum + a.estMinutes);
}

class PlanValidation {
  const PlanValidation({this.plan, this.errors = const [], this.warnings = const []});

  final PlanDraft? plan;
  final List<String> errors;
  final List<String> warnings;

  bool get ok => plan != null && errors.isEmpty;
}

String _str(dynamic v) => v == null ? '' : v.toString().trim();

List<String> _strList(dynamic v) =>
    v is List ? v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() : <String>[];

/// Parses an AI reply into a plan and lists everything wrong with it.
PlanValidation parsePlan(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(extractJsonObject(raw));
  } on FormatException catch (e) {
    return PlanValidation(errors: ['This is not valid JSON: ${e.message}']);
  }
  if (decoded is! Map) {
    return const PlanValidation(
      errors: ['The JSON must be an object with "schemaVersion", "course" and "milestones".'],
    );
  }
  final root = decoded;
  final errors = <String>[];
  final warnings = <String>[];

  final version = root['schemaVersion'];
  if (version != supportedSchemaVersion) {
    errors.add('schemaVersion must be $supportedSchemaVersion (got ${version ?? 'nothing'}).');
  }

  // course
  final courseRaw = root['course'];
  final Map course = courseRaw is Map ? courseRaw : const {};
  if (courseRaw is! Map) errors.add('Missing the "course" object.');
  final courseTitle = _str(course['title']);
  if (courseTitle.isEmpty) errors.add('course.title is empty.');
  final kindStr = _str(course['kind']);
  final courseKind = kindStr == 'university' ? CourseKind.university : CourseKind.self;
  if (kindStr.isNotEmpty && kindStr != 'self' && kindStr != 'university') {
    warnings.add('course.kind "$kindStr" is unknown; using "self".');
  }
  var weeklyHours = 6.0;
  final wh = course['weeklyHours'];
  if (wh is num && wh > 0) {
    weeklyHours = wh.toDouble();
  } else {
    warnings.add('course.weeklyHours is missing; using 6.');
  }

  // skills
  final skills = <PlanSkill>[];
  final skillIds = <String>{};
  final skillsRaw = root['skills'];
  if (skillsRaw != null && skillsRaw is! List) errors.add('"skills" must be a list.');
  if (skillsRaw is List) {
    for (var i = 0; i < skillsRaw.length; i++) {
      final s = skillsRaw[i];
      if (s is! Map) {
        errors.add('skills[$i] is not an object.');
        continue;
      }
      final id = _str(s['id']);
      if (id.isEmpty) {
        errors.add('skills[$i] has no id.');
        continue;
      }
      if (!skillIds.add(id)) {
        errors.add('Skill id "$id" is used twice.');
        continue;
      }
      final name = _str(s['name']);
      skills.add(PlanSkill(id: id, name: name.isEmpty ? id : name, description: _str(s['description'])));
    }
  }

  // milestones and activities
  final milestones = <PlanMilestone>[];
  final milestoneIds = <String>{};
  final activityIds = <String>{};
  final order = <String, int>{};
  final msRaw = root['milestones'];
  if (msRaw is! List || msRaw.isEmpty) {
    errors.add('"milestones" must be a non-empty list.');
  } else {
    for (var mi = 0; mi < msRaw.length; mi++) {
      final m = msRaw[mi];
      if (m is! Map) {
        errors.add('milestones[$mi] is not an object.');
        continue;
      }
      final mid = _str(m['id']);
      if (mid.isEmpty) {
        errors.add('milestones[$mi] has no id.');
        continue;
      }
      if (!milestoneIds.add(mid)) {
        errors.add('Milestone id "$mid" is used twice.');
        continue;
      }
      final acts = <PlanActivity>[];
      final aRaw = m['activities'];
      if (aRaw is! List || aRaw.isEmpty) {
        warnings.add('Milestone "$mid" has no activities.');
      } else {
        for (var ai = 0; ai < aRaw.length; ai++) {
          final a = aRaw[ai];
          final where = '$mid.activities[$ai]';
          if (a is! Map) {
            errors.add('$where is not an object.');
            continue;
          }
          final id = _str(a['id']);
          if (id.isEmpty) {
            errors.add('$where has no id.');
            continue;
          }
          if (!activityIds.add(id)) {
            errors.add('Activity id "$id" is used twice.');
            continue;
          }
          final title = _str(a['title']);
          if (title.isEmpty) errors.add('Activity "$id" has no title.');
          final kindRaw = _str(a['kind']);
          final kind = ActivityKind.tryDb(kindRaw);
          if (kind == null) warnings.add('Activity "$id": kind "$kindRaw" is unknown; using "lesson".');
          var minutes = 30;
          final em = a['estimatedMinutes'];
          if (em is num && em > 0) {
            minutes = em.round();
          } else {
            warnings.add('Activity "$id": estimatedMinutes is missing; using 30.');
          }
          DateTime? due;
          final dueRaw = _str(a['dueAt']);
          if (dueRaw.isNotEmpty && dueRaw != 'null') {
            due = DateTime.tryParse(dueRaw);
            if (due == null) {
              errors.add('Activity "$id": dueAt "$dueRaw" is not a date '
                  '(use ISO 8601, e.g. 2026-11-13T14:00:00+08:00).');
            }
          }
          order[id] = order.length;
          acts.add(PlanActivity(
            id: id,
            title: title,
            kind: kind ?? ActivityKind.lesson,
            objective: _str(a['objective']),
            content: _str(a['content']),
            task: _str(a['task']),
            criteria: _str(a['criteria']),
            estMinutes: minutes,
            prerequisites: _strList(a['prerequisites']),
            skills: _strList(a['skills']),
            dueAt: due,
          ));
        }
      }
      final mtitle = _str(m['title']);
      milestones.add(PlanMilestone(id: mid, title: mtitle.isEmpty ? mid : mtitle, activities: acts));
    }
  }

  // cross-references
  for (final m in milestones) {
    for (final a in m.activities) {
      for (final p in a.prerequisites) {
        if (p == a.id) {
          errors.add('Activity "${a.id}" lists itself as a prerequisite.');
        } else if (!activityIds.contains(p)) {
          errors.add('Activity "${a.id}" needs "$p", which is not in the plan.');
        } else if ((order[p] ?? 0) > (order[a.id] ?? 0)) {
          warnings.add('Activity "${a.id}" needs "$p", which comes later in the plan.');
        }
      }
      for (final s in a.skills) {
        if (!skillIds.contains(s)) {
          errors.add('Activity "${a.id}" uses skill "$s", which is not in "skills".');
        }
      }
    }
  }

  return PlanValidation(
    plan: PlanDraft(
      title: courseTitle,
      kind: courseKind,
      goal: _str(course['goal']),
      weeklyHours: weeklyHours,
      skills: skills,
      milestones: milestones,
    ),
    errors: errors,
    warnings: warnings,
  );
}

// --------------------------------------------------------------------- diff

class PlanDiff {
  const PlanDiff({required this.added, required this.updated, required this.archived});

  final List<String> added;
  final List<String> updated;

  /// Activities that leave the plan. They are archived, and their attempts are kept.
  final List<String> archived;
}

/// What importing [plan] into a course with [existing] activities would change.
PlanDiff diffPlan(PlanDraft plan, List<Activity> existing) {
  final fromPlan = existing.where((a) => a.origin == Origin.plan).toList();
  final byKey = {for (final a in fromPlan) a.key: a};
  final newKeys = {for (final a in plan.allActivities) a.id};
  return PlanDiff(
    added: [for (final a in plan.allActivities) if (!byKey.containsKey(a.id)) a.title],
    updated: [for (final a in plan.allActivities) if (byKey.containsKey(a.id)) a.title],
    archived: [for (final a in fromPlan) if (!a.archived && !newKeys.contains(a.key)) a.title],
  );
}

// ------------------------------------------------------------------- export

/// The course's current plan in the same JSON format (for revision by an AI).
Map<String, dynamic> exportPlan(
  Course course,
  List<Milestone> milestones,
  List<Activity> activities,
  List<Skill> skills,
) {
  final ms = milestones.where((m) => !m.archived).toList()..sort((a, b) => a.position.compareTo(b.position));
  final acts = activities.where((a) => a.origin == Origin.plan && !a.archived).toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  return {
    'schemaVersion': supportedSchemaVersion,
    'course': {
      'title': course.title,
      'kind': course.kind.db,
      'goal': course.goal,
      'weeklyHours': course.weeklyHours,
    },
    'skills': [
      for (final s in skills) {'id': s.key, 'name': s.name, 'description': s.description},
    ],
    'milestones': [
      for (final m in ms)
        {
          'id': m.key,
          'title': m.title,
          'activities': [
            for (final a in acts.where((x) => x.milestoneId == m.id))
              {
                'id': a.key,
                'title': a.title,
                'kind': a.kind.db,
                'objective': a.objective,
                'content': a.content,
                'task': a.task,
                'criteria': a.criteria,
                'estimatedMinutes': a.estMinutes,
                'prerequisites': a.prerequisites,
                'skills': a.skillKeys,
                'dueAt': a.dueAt?.toUtc().toIso8601String(),
              },
          ],
        },
    ],
  };
}

String exportPlanJson(Course course, List<Milestone> ms, List<Activity> acts, List<Skill> skills) =>
    const JsonEncoder.withIndent('  ').convert(exportPlan(course, ms, acts, skills));
