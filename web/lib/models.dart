// Data classes and enums shared by the logic, data and UI layers.
// Enum `db` values match the check constraints in supabase/schema.sql.

enum CourseKind {
  self('self', 'Self-study'),
  university('university', 'University');

  const CourseKind(this.db, this.label);
  final String db;
  final String label;

  static CourseKind fromDb(String? v) =>
      CourseKind.values.firstWhere((e) => e.db == v, orElse: () => CourseKind.self);
}

enum ActivityKind {
  lesson('lesson', 'Lesson'),
  exercise('exercise', 'Exercise'),
  check('check', 'Check'),
  lab('lab', 'Lab'),
  assignment('assignment', 'Assignment'),
  exam('exam', 'Exam'),
  project('project', 'Project');

  const ActivityKind(this.db, this.label);
  final String db;
  final String label;

  static ActivityKind? tryDb(String? v) {
    for (final e in ActivityKind.values) {
      if (e.db == v) return e;
    }
    return null;
  }

  static ActivityKind fromDb(String? v) => tryDb(v) ?? ActivityKind.lesson;
}

enum ActivityState {
  notStarted('not_started', 'Not started'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  missed('missed', 'Missed');

  const ActivityState(this.db, this.label);
  final String db;
  final String label;

  static ActivityState fromDb(String? v) =>
      ActivityState.values.firstWhere((e) => e.db == v, orElse: () => ActivityState.notStarted);
}

enum Origin {
  plan('plan'),
  manual('manual'),
  adaptive('adaptive');

  const Origin(this.db);
  final String db;

  static Origin fromDb(String? v) =>
      Origin.values.firstWhere((e) => e.db == v, orElse: () => Origin.plan);
}

enum SkillStatus {
  unassessed('unassessed', 'Unassessed'),
  practicing('practicing', 'Practicing'),
  demonstrated('demonstrated', 'Demonstrated');

  const SkillStatus(this.db, this.label);
  final String db;
  final String label;

  static SkillStatus fromDb(String? v) =>
      SkillStatus.values.firstWhere((e) => e.db == v, orElse: () => SkillStatus.unassessed);
}

/// How much help was used during an attempt. Order matters: later = more help.
enum HelpLevel {
  none('none', 'No help'),
  hint('hint', 'Hints'),
  explanation('explanation', 'Explanation'),
  workedSolution('worked_solution', 'Worked solution');

  const HelpLevel(this.db, this.label);
  final String db;
  final String label;

  static HelpLevel fromDb(String? v) =>
      HelpLevel.values.firstWhere((e) => e.db == v, orElse: () => HelpLevel.none);

  /// Explanations and worked solutions make an attempt "supported" (assumption A1).
  bool get isSupported => index >= HelpLevel.explanation.index;

  HelpLevel max(HelpLevel other) => other.index > index ? other : this;
}

enum Verdict {
  pass('pass', 'Pass'),
  fail('fail', 'Not yet'),
  uncertain('uncertain', 'Uncertain');

  const Verdict(this.db, this.label);
  final String db;
  final String label;

  static Verdict? tryDb(String? v) {
    for (final e in Verdict.values) {
      if (e.db == v) return e;
    }
    return null;
  }

  static Verdict fromDb(String? v) => tryDb(v) ?? Verdict.uncertain;
}

/// The kinds of help the tutor panel can ask an external AI for.
enum TutorHelp {
  hint('hint', 'Hint', HelpLevel.hint),
  explain('explain', 'Explain', HelpLevel.explanation),
  worked('worked', 'Worked solution', HelpLevel.workedSolution),
  freshProblem('fresh_problem', 'New problem', HelpLevel.none),
  lesson('lesson', 'Write the lesson', HelpLevel.none);

  const TutorHelp(this.db, this.label, this.level);
  final String db;
  final String label;

  /// The help level this counts as for the current attempt.
  final HelpLevel level;

  static TutorHelp fromDb(String? v) =>
      TutorHelp.values.firstWhere((e) => e.db == v, orElse: () => TutorHelp.explain);
}

// ------------------------------------------------------------------ helpers

String _s(dynamic v) => v == null ? '' : v.toString();

double _d(dynamic v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;

int _i(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

List<String> _list(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

// ------------------------------------------------------------------ classes

class Course {
  Course({
    required this.id,
    required this.title,
    required this.kind,
    required this.goal,
    required this.weeklyHours,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String title;
  final CourseKind kind;
  final String goal;
  final double weeklyHours;
  final String status;
  final DateTime? createdAt;

  factory Course.fromMap(Map<String, dynamic> m) => Course(
        id: _s(m['id']),
        title: _s(m['title']),
        kind: CourseKind.fromDb(m['kind'] as String?),
        goal: _s(m['goal']),
        weeklyHours: _d(m['weekly_hours'], 6),
        status: _s(m['status']),
        createdAt: _dt(m['created_at']),
      );
}

class Milestone {
  Milestone({
    required this.id,
    required this.courseId,
    required this.key,
    required this.title,
    required this.position,
    required this.archived,
  });

  final String id;
  final String courseId;
  final String key;
  final String title;
  final double position;
  final bool archived;

  factory Milestone.fromMap(Map<String, dynamic> m) => Milestone(
        id: _s(m['id']),
        courseId: _s(m['course_id']),
        key: _s(m['key']),
        title: _s(m['title']),
        position: _d(m['position']),
        archived: m['archived'] == true,
      );
}

class Skill {
  Skill({
    required this.id,
    required this.courseId,
    required this.key,
    required this.name,
    required this.description,
    required this.status,
  });

  final String id;
  final String courseId;
  final String key;
  final String name;
  final String description;
  final SkillStatus status;

  factory Skill.fromMap(Map<String, dynamic> m) => Skill(
        id: _s(m['id']),
        courseId: _s(m['course_id']),
        key: _s(m['key']),
        name: _s(m['name']),
        description: _s(m['description']),
        status: SkillStatus.fromDb(m['status'] as String?),
      );
}

class Activity {
  Activity({
    required this.id,
    required this.courseId,
    this.milestoneId,
    required this.key,
    required this.title,
    this.kind = ActivityKind.lesson,
    this.objective = '',
    this.content = '',
    this.task = '',
    this.criteria = '',
    this.estMinutes = 30,
    this.position = 0,
    this.prerequisites = const [],
    this.skillKeys = const [],
    this.dueAt,
    this.state = ActivityState.notStarted,
    this.origin = Origin.plan,
    this.note = '',
    this.sourceActivityId,
    this.archived = false,
    this.completedAt,
  });

  final String id;
  final String courseId;
  final String? milestoneId;
  final String key;
  final String title;
  final ActivityKind kind;
  final String objective;
  final String content;
  final String task;
  final String criteria;
  final int estMinutes;
  final double position;
  final List<String> prerequisites;
  final List<String> skillKeys;
  final DateTime? dueAt;
  final ActivityState state;
  final Origin origin;
  final String note;
  final String? sourceActivityId;
  final bool archived;
  final DateTime? completedAt;

  bool get isDone => state == ActivityState.completed;

  /// Still something to do: not done, not missed, not archived.
  bool get isOpen => !archived && state != ActivityState.completed && state != ActivityState.missed;

  factory Activity.fromMap(Map<String, dynamic> m) => Activity(
        id: _s(m['id']),
        courseId: _s(m['course_id']),
        milestoneId: m['milestone_id'] as String?,
        key: _s(m['key']),
        title: _s(m['title']),
        kind: ActivityKind.fromDb(m['kind'] as String?),
        objective: _s(m['objective']),
        content: _s(m['content']),
        task: _s(m['task']),
        criteria: _s(m['criteria']),
        estMinutes: _i(m['est_minutes'], 30),
        position: _d(m['position']),
        prerequisites: _list(m['prerequisites']),
        skillKeys: _list(m['skill_keys']),
        dueAt: _dt(m['due_at']),
        state: ActivityState.fromDb(m['state'] as String?),
        origin: Origin.fromDb(m['origin'] as String?),
        note: _s(m['note']),
        sourceActivityId: m['source_activity_id'] as String?,
        archived: m['archived'] == true,
        completedAt: _dt(m['completed_at']),
      );
}

class Attempt {
  Attempt({
    required this.id,
    required this.activityId,
    required this.answer,
    required this.help,
    required this.verdict,
    required this.evaluatedBy,
    required this.feedback,
    required this.gap,
    this.createdAt,
  });

  final String id;
  final String activityId;
  final String answer;
  final HelpLevel help;
  final Verdict verdict;
  final String evaluatedBy;
  final String feedback;
  final String gap;
  final DateTime? createdAt;

  factory Attempt.fromMap(Map<String, dynamic> m) => Attempt(
        id: _s(m['id']),
        activityId: _s(m['activity_id']),
        answer: _s(m['answer']),
        help: HelpLevel.fromDb(m['help_level'] as String?),
        verdict: Verdict.fromDb(m['verdict'] as String?),
        evaluatedBy: _s(m['evaluated_by']),
        feedback: _s(m['feedback']),
        gap: _s(m['gap']),
        createdAt: _dt(m['created_at']),
      );
}

class TutorExchange {
  TutorExchange({
    required this.id,
    this.courseId,
    this.activityId,
    required this.help,
    required this.question,
    required this.prompt,
    required this.response,
    this.createdAt,
  });

  final String id;
  final String? courseId;
  final String? activityId;
  final TutorHelp help;
  final String question;
  final String prompt;
  final String response;
  final DateTime? createdAt;

  factory TutorExchange.fromMap(Map<String, dynamic> m) => TutorExchange(
        id: _s(m['id']),
        courseId: m['course_id'] as String?,
        activityId: m['activity_id'] as String?,
        help: TutorHelp.fromDb(m['help_type'] as String?),
        question: _s(m['question']),
        prompt: _s(m['prompt']),
        response: _s(m['response']),
        createdAt: _dt(m['created_at']),
      );
}
