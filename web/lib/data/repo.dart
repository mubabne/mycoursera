// All reads and writes to Supabase. Row-level security limits every query to
// the signed-in user, and `user_id` is filled in by the database default.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/ids.dart';
import '../logic/plan_import.dart';
import '../logic/rules.dart';
import '../models.dart';

/// Set once in main() after Supabase.initialize.
late final Repo repo;

String _now() => DateTime.now().toUtc().toIso8601String();

class SubmitResult {
  const SubmitResult({required this.duplicate, this.followUp, this.skillChanges = const {}});

  /// True when this attempt id was already recorded (double submit or retry).
  final bool duplicate;
  final Activity? followUp;

  /// Skill name -> status after this attempt.
  final Map<String, SkillStatus> skillChanges;
}

class Repo {
  Repo(this._db);

  final SupabaseClient _db;

  // ---------------------------------------------------------------- courses

  Future<List<Course>> courses() async {
    final rows = await _db.from('courses').select().order('created_at', ascending: true);
    return rows.map(Course.fromMap).toList();
  }

  Future<Course> course(String id) async {
    final row = await _db.from('courses').select().eq('id', id).single();
    return Course.fromMap(row);
  }

  Future<Course> createCourse({
    required String title,
    required CourseKind kind,
    String goal = '',
    double weeklyHours = 6,
  }) async {
    final row = await _db
        .from('courses')
        .insert({'title': title, 'kind': kind.db, 'goal': goal, 'weekly_hours': weeklyHours})
        .select()
        .single();
    return Course.fromMap(row);
  }

  Future<void> updateCourse(String id, Map<String, dynamic> values) async {
    await _db.from('courses').update(values).eq('id', id);
  }

  // ------------------------------------------------------ milestones/skills

  Future<List<Milestone>> milestones(String courseId, {bool includeArchived = false}) async {
    var q = _db.from('milestones').select().eq('course_id', courseId);
    if (!includeArchived) q = q.eq('archived', false);
    final rows = await q.order('position', ascending: true);
    return rows.map(Milestone.fromMap).toList();
  }

  Future<List<Skill>> skills({String? courseId}) async {
    var q = _db.from('skills').select();
    if (courseId != null) q = q.eq('course_id', courseId);
    final rows = await q.order('key', ascending: true);
    return rows.map(Skill.fromMap).toList();
  }

  // ------------------------------------------------------------- activities

  Future<List<Activity>> activities({String? courseId, bool includeArchived = false}) async {
    var q = _db.from('activities').select();
    if (courseId != null) q = q.eq('course_id', courseId);
    if (!includeArchived) q = q.eq('archived', false);
    final rows = await q.order('position', ascending: true);
    return rows.map(Activity.fromMap).toList();
  }

  Future<Activity> activity(String id) async {
    final row = await _db.from('activities').select().eq('id', id).single();
    return Activity.fromMap(row);
  }

  Future<void> setActivityState(Activity a, ActivityState state) async {
    await _db.from('activities').update({
      'state': state.db,
      'completed_at': state == ActivityState.completed ? _now() : null,
    }).eq('id', a.id);
  }

  Future<void> updateActivityContent(String id, String content) async {
    await _db.from('activities').update({'content': content}).eq('id', id);
  }

  Future<double> _nextPosition(String courseId) async {
    final rows = await _db
        .from('activities')
        .select('position')
        .eq('course_id', courseId)
        .order('position', ascending: false)
        .limit(1);
    if (rows.isEmpty) return 0.0;
    final p = rows.first['position'];
    return p is num ? p.toDouble() + 10 : 10.0;
  }

  /// Adds an activity by hand (university item, practice from a question).
  Future<Activity> addActivity({
    required String courseId,
    required String title,
    String? milestoneId,
    ActivityKind kind = ActivityKind.exercise,
    String objective = '',
    String task = '',
    String criteria = '',
    int estMinutes = 30,
    DateTime? dueAt,
    String note = '',
  }) async {
    final position = await _nextPosition(courseId);
    final row = await _db
        .from('activities')
        .insert({
          'course_id': courseId,
          'milestone_id': milestoneId,
          'key': newKey('manual'),
          'title': title,
          'kind': kind.db,
          'objective': objective,
          'task': task,
          'criteria': criteria,
          'est_minutes': estMinutes,
          'position': position,
          'due_at': dueAt?.toUtc().toIso8601String(),
          'origin': Origin.manual.db,
          'note': note,
        })
        .select()
        .single();
    return Activity.fromMap(row);
  }

  Future<Activity> _insertFollowUp(Activity source, FollowUp f, {DateTime? dueAt}) async {
    final row = await _db
        .from('activities')
        .insert({
          'course_id': source.courseId,
          'milestone_id': source.milestoneId,
          'key': newKey('adaptive'),
          'title': f.title,
          'kind': f.kind.db,
          'objective': source.objective,
          'task': f.task,
          'criteria': source.criteria,
          'est_minutes': f.estMinutes,
          'position': source.position + 0.5,
          'skill_keys': source.skillKeys,
          'due_at': dueAt?.toUtc().toIso8601String(),
          'origin': Origin.adaptive.db,
          'note': f.note,
          'source_activity_id': source.id,
        })
        .select()
        .single();
    return Activity.fromMap(row);
  }

  /// Marks a (university) item missed and adds a catch-up before the next item.
  Future<Activity> markMissed(Activity missed) async {
    await setActivityState(missed, ActivityState.missed);
    final now = DateTime.now();
    final courseActivities = await activities(courseId: missed.courseId);
    final next = nextDatedItem(missed, courseActivities, now);
    return _insertFollowUp(missed, catchUpFor(missed, next, now), dueAt: catchUpDue(next, now));
  }

  // --------------------------------------------------------------- attempts

  Future<List<Attempt>> attempts({String? activityId}) async {
    var q = _db.from('attempts').select();
    if (activityId != null) q = q.eq('activity_id', activityId);
    final rows = await q.order('created_at', ascending: false);
    return rows.map(Attempt.fromMap).toList();
  }

  /// Records an attempt once (by [clientAttemptId]) and applies the adaptation rules.
  Future<SubmitResult> submitAttempt({
    required Activity activity,
    required String clientAttemptId,
    required String answer,
    required HelpLevel help,
    required Verdict verdict,
    required String evaluatedBy,
    String feedback = '',
    String gap = '',
  }) async {
    try {
      await _db.from('attempts').insert({
        'activity_id': activity.id,
        'client_attempt_id': clientAttemptId,
        'answer': answer,
        'help_level': help.db,
        'verdict': verdict.db,
        'evaluated_by': evaluatedBy,
        'feedback': feedback,
        'gap': gap,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const SubmitResult(duplicate: true);
      rethrow;
    }

    await setActivityState(activity, activityStateAfter(verdict));

    final changes = <String, SkillStatus>{};
    if (activity.skillKeys.isNotEmpty) {
      final rows = await _db
          .from('skills')
          .select()
          .eq('course_id', activity.courseId)
          .inFilter('key', activity.skillKeys);
      for (final s in rows.map(Skill.fromMap)) {
        final next = nextSkillStatus(s.status, verdict, help);
        if (next != s.status) {
          await _db.from('skills').update({'status': next.db, 'status_updated_at': _now()}).eq('id', s.id);
        }
        changes[s.name] = next;
      }
    }

    final f = followUpFor(activity, verdict, help, gap: gap);
    final created = f == null ? null : await _insertFollowUp(activity, f);
    return SubmitResult(duplicate: false, followUp: created, skillChanges: changes);
  }

  // ------------------------------------------------------------ plan import

  /// Creates a course from [plan], or updates [courseId] in place.
  /// Activities are matched by id, so states and attempts stay attached.
  Future<String> importPlan(PlanDraft plan, {String? courseId}) async {
    final String id;
    if (courseId == null) {
      final c = await createCourse(
        title: plan.title,
        kind: plan.kind,
        goal: plan.goal,
        weeklyHours: plan.weeklyHours,
      );
      id = c.id;
    } else {
      id = courseId;
      await updateCourse(id, {'title': plan.title, 'goal': plan.goal, 'weekly_hours': plan.weeklyHours});
    }

    if (plan.skills.isNotEmpty) {
      await _db.from('skills').upsert(
        [
          for (final s in plan.skills)
            {'course_id': id, 'key': s.id, 'name': s.name, 'description': s.description},
        ],
        onConflict: 'course_id,key',
      );
    }

    final msRows = await _db.from('milestones').upsert(
      [
        for (var i = 0; i < plan.milestones.length; i++)
          {
            'course_id': id,
            'key': plan.milestones[i].id,
            'title': plan.milestones[i].title,
            'position': i * 10.0,
            'archived': false,
          },
      ],
      onConflict: 'course_id,key',
    ).select();
    final milestoneIdByKey = {
      for (final r in msRows) r['key'].toString(): r['id'].toString(),
    };

    final existing = await activities(courseId: id, includeArchived: true);
    final existingByKey = {for (final a in existing) a.key: a};
    final rows = <Map<String, dynamic>>[];
    var index = 0;
    for (final m in plan.milestones) {
      for (final a in m.activities) {
        final old = existingByKey[a.id];
        rows.add({
          'course_id': id,
          'milestone_id': milestoneIdByKey[m.id],
          'key': a.id,
          'title': a.title,
          'kind': a.kind.db,
          'objective': a.objective,
          // Keep a lesson you saved from the tutor if the new plan has none.
          'content': a.content.isNotEmpty ? a.content : (old?.content ?? ''),
          'task': a.task,
          'criteria': a.criteria,
          'est_minutes': a.estMinutes,
          'position': index * 10.0,
          'prerequisites': a.prerequisites,
          'skill_keys': a.skills,
          'due_at': a.dueAt?.toUtc().toIso8601String(),
          'origin': Origin.plan.db,
          'archived': false,
        });
        index++;
      }
    }
    if (rows.isNotEmpty) {
      await _db.from('activities').upsert(rows, onConflict: 'course_id,key');
    }

    // Archive (never delete) plan activities and milestones that left the plan.
    final newKeys = {for (final a in plan.allActivities) a.id};
    final toArchive = [
      for (final a in existing)
        if (a.origin == Origin.plan && !a.archived && !newKeys.contains(a.key)) a.id,
    ];
    if (toArchive.isNotEmpty) {
      await _db.from('activities').update({'archived': true}).inFilter('id', toArchive);
    }
    final newMilestoneKeys = {for (final m in plan.milestones) m.id};
    final oldMilestones = await milestones(id, includeArchived: true);
    final msToArchive = [
      for (final m in oldMilestones)
        if (!m.archived && !newMilestoneKeys.contains(m.key)) m.id,
    ];
    if (msToArchive.isNotEmpty) {
      await _db.from('milestones').update({'archived': true}).inFilter('id', msToArchive);
    }
    return id;
  }

  // -------------------------------------------------------------- tutoring

  /// Exchanges for one activity, or standalone ones (no activity) when null.
  Future<List<TutorExchange>> exchanges({String? activityId}) async {
    var q = _db.from('tutor_exchanges').select();
    q = activityId == null ? q.isFilter('activity_id', null) : q.eq('activity_id', activityId);
    final rows = await q.order('created_at', ascending: false);
    return rows.map(TutorExchange.fromMap).toList();
  }

  Future<void> saveExchange({
    String? courseId,
    String? activityId,
    required TutorHelp help,
    required String question,
    required String prompt,
    required String response,
  }) async {
    await _db.from('tutor_exchanges').insert({
      'course_id': courseId,
      'activity_id': activityId,
      'help_type': help.db,
      'question': question,
      'prompt': prompt,
      'response': response,
    });
  }

  Future<void> attachExchange(String exchangeId, String courseId) async {
    await _db.from('tutor_exchanges').update({'course_id': courseId}).eq('id', exchangeId);
  }
}
