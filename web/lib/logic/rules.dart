// Adaptation rules (docs/SPEC.md section 6). Pure functions: no I/O, easy to test.
// The AI only proposes a verdict; these rules decide what happens next.

import '../models.dart';
import 'format.dart';

// ------------------------------------------------------------ skill status

/// Skill status after an attempt with [verdict] and [help].
SkillStatus nextSkillStatus(SkillStatus current, Verdict verdict, HelpLevel help) {
  return switch (verdict) {
    Verdict.pass => help.isSupported
        ? (current == SkillStatus.demonstrated ? SkillStatus.demonstrated : SkillStatus.practicing)
        : SkillStatus.demonstrated,
    Verdict.fail => SkillStatus.practicing,
    Verdict.uncertain => current,
  };
}

/// Activity state after an attempt: a pass completes it, anything else keeps it open.
ActivityState activityStateAfter(Verdict verdict) =>
    verdict == Verdict.pass ? ActivityState.completed : ActivityState.inProgress;

// --------------------------------------------------------------- follow-ups

/// An activity the app adds by itself (fresh check, gap exercise, catch-up).
class FollowUp {
  const FollowUp({
    required this.kind,
    required this.title,
    required this.task,
    required this.note,
    required this.estMinutes,
  });

  final ActivityKind kind;
  final String title;
  final String task;

  /// Why it exists; shown as the reason on Today and in the session.
  final String note;
  final int estMinutes;
}

final _prefix = RegExp(r'^(Fresh check|Another check|Practice|Catch up): ');

/// "Fresh check: Fresh check: Loops" -> "Loops".
String baseTitle(String title) {
  var t = title;
  while (_prefix.hasMatch(t)) {
    t = t.replaceFirst(_prefix, '');
  }
  return t;
}

/// What to add after an attempt, or null when nothing is needed.
FollowUp? followUpFor(Activity a, Verdict verdict, HelpLevel help, {String gap = ''}) {
  final name = baseTitle(a.title);
  final g = gap.trim();
  return switch (verdict) {
    Verdict.pass => help.isSupported
        ? FollowUp(
            kind: ActivityKind.check,
            title: 'Fresh check: $name',
            task: 'Get a new problem on the same objective (tutor: "New problem") and solve it '
                'without explanations or worked solutions. Then submit your answer.',
            note: 'You passed "$name" with ${help.label.toLowerCase()}. A fresh problem solved on '
                'your own shows whether the skill is really yours.',
            estMinutes: 20,
          )
        : null,
    Verdict.fail => FollowUp(
        kind: ActivityKind.exercise,
        title: g.isEmpty ? 'Practice: $name' : 'Practice: $g',
        task: g.isEmpty
            ? 'Do a short exercise on the part of "$name" you got stuck on (tutor: "New problem"), '
                'then retry "$name".'
            : 'Short exercise on: $g. Ask the tutor for a small problem on exactly this '
                '(tutor: "New problem"), solve it, then go back to "$name".',
        note: g.isEmpty
            ? 'Your last attempt on "$name" did not pass yet. A short exercise comes before you retry.'
            : 'Your attempt on "$name" showed a gap: $g. A short exercise on it comes before you retry.',
        estMinutes: 15,
      ),
    Verdict.uncertain => FollowUp(
        kind: ActivityKind.check,
        title: 'Another check: $name',
        task: 'Solve one more problem on this objective (tutor: "New problem"). Include the output '
            'you got, or explain your answer in your own words, so the result can be judged.',
        note: 'The last result for "$name" could not be judged, so the skill stays as it was. '
            'Another check settles it.',
        estMinutes: 15,
      ),
  };
}

// ----------------------------------------------------------------- ordering

int _byPosition(Activity a, Activity b) => a.position.compareTo(b.position);

int _byDueThenPosition(Activity a, Activity b) {
  final ad = a.dueAt;
  final bd = b.dueAt;
  if (ad != null && bd != null) {
    final c = ad.compareTo(bd);
    if (c != 0) return c;
  } else if (ad != null) {
    return -1;
  } else if (bd != null) {
    return 1;
  }
  return _byPosition(a, b);
}

List<Activity> sortedByPosition(Iterable<Activity> xs) => xs.toList()..sort(_byPosition);

/// True when every prerequisite (by key, same course) is completed.
/// Prerequisites that no longer exist or are archived don't block.
bool prerequisitesMet(Activity a, Map<String, Activity> byKey) {
  for (final k in a.prerequisites) {
    final p = byKey[k];
    if (p != null && !p.archived && !p.isDone) return false;
  }
  return true;
}

/// Next thing to do inside one course: open follow-ups first, then the first
/// open activity (by position) whose prerequisites are done.
Activity? nextEligible(List<Activity> courseActivities) {
  final adaptive = courseActivities.where((a) => a.isOpen && a.origin == Origin.adaptive).toList()
    ..sort(_byDueThenPosition);
  if (adaptive.isNotEmpty) return adaptive.first;
  final byKey = {for (final a in courseActivities) a.key: a};
  for (final a in sortedByPosition(courseActivities)) {
    if (a.isOpen && prerequisitesMet(a, byKey)) return a;
  }
  return null;
}

class NextAction {
  const NextAction(this.activity, this.reason);

  final Activity activity;
  final String reason;
}

/// The one thing Today recommends, with the reason it was picked.
/// Order: follow-ups -> items due within 3 days -> in progress -> next eligible.
NextAction? pickNextAction(List<Activity> activities, Map<String, Course> courses, DateTime now) {
  final open = activities.where((a) => a.isOpen && courses.containsKey(a.courseId)).toList();
  if (open.isEmpty) return null;
  String courseOf(Activity a) => courses[a.courseId]!.title;

  final adaptive = open.where((a) => a.origin == Origin.adaptive).toList()..sort(_byDueThenPosition);
  if (adaptive.isNotEmpty) {
    final a = adaptive.first;
    return NextAction(a, a.note.isNotEmpty ? a.note : 'Follow-up from your last session in ${courseOf(a)}.');
  }

  final soon = open
      .where((a) => a.dueAt != null && a.dueAt!.isBefore(now.add(const Duration(days: 3))))
      .toList()
    ..sort(_byDueThenPosition);
  if (soon.isNotEmpty) {
    final a = soon.first;
    final due = a.dueAt!;
    return NextAction(
      a,
      due.isBefore(now)
          ? 'Overdue since ${describeDue(due, now)} in ${courseOf(a)}.'
          : 'Due ${describeDue(due, now)} in ${courseOf(a)}.',
    );
  }

  final started = open.where((a) => a.state == ActivityState.inProgress).toList()..sort(_byPosition);
  if (started.isNotEmpty) {
    final a = started.first;
    return NextAction(a, 'You started this in ${courseOf(a)}. Pick up where you left off.');
  }

  for (final c in courses.values) {
    final next = nextEligible(activities.where((a) => a.courseId == c.id).toList());
    if (next != null) {
      return NextAction(
        next,
        next.prerequisites.isEmpty
            ? 'Next step in ${c.title}.'
            : 'Next step in ${c.title}. Everything it builds on is done.',
      );
    }
  }
  return null;
}

/// Open items with a due date before now + [days], overdue ones included, soonest first.
List<Activity> upcomingDeadlines(List<Activity> activities, DateTime now, {int days = 7}) {
  final limit = now.add(Duration(days: days));
  return activities.where((a) => a.isOpen && a.dueAt != null && a.dueAt!.isBefore(limit)).toList()
    ..sort(_byDueThenPosition);
}

// ----------------------------------------------------------------- schedule

class ScheduleEstimate {
  const ScheduleEstimate({
    required this.remainingMinutes,
    required this.weeks,
    required this.finish,
    required this.thisWeek,
  });

  final int remainingMinutes;
  final double weeks;
  final DateTime? finish;

  /// Open activities that fit into one week's budget (always at least one).
  final List<Activity> thisWeek;
}

/// Time left and finish date for one course at [weeklyHours] per week.
ScheduleEstimate estimateSchedule(List<Activity> courseActivities, double weeklyHours, DateTime now) {
  final open = sortedByPosition(courseActivities.where((a) => a.isOpen));
  final ordered = [
    ...open.where((a) => a.origin == Origin.adaptive),
    ...open.where((a) => a.origin != Origin.adaptive),
  ];
  final remaining = ordered.fold<int>(0, (sum, a) => sum + a.estMinutes);
  final weeklyMinutes = weeklyHours * 60;
  if (weeklyMinutes <= 0) {
    return ScheduleEstimate(remainingMinutes: remaining, weeks: 0, finish: null, thisWeek: const []);
  }
  final weeks = remaining / weeklyMinutes;
  final finish = remaining == 0 ? null : now.add(Duration(minutes: (weeks * 7 * 24 * 60).round()));

  final thisWeek = <Activity>[];
  var used = 0;
  for (final a in ordered) {
    if (thisWeek.isNotEmpty && used + a.estMinutes > weeklyMinutes) break;
    thisWeek.add(a);
    used += a.estMinutes;
  }
  return ScheduleEstimate(remainingMinutes: remaining, weeks: weeks, finish: finish, thisWeek: thisWeek);
}

// ----------------------------------------------------------------- catch-up

/// The next open dated item in the same course after [now], other than [missed].
Activity? nextDatedItem(Activity missed, List<Activity> courseActivities, DateTime now) {
  final upcoming = courseActivities
      .where((a) => a.id != missed.id && a.isOpen && a.dueAt != null && a.dueAt!.isAfter(now))
      .toList()
    ..sort(_byDueThenPosition);
  return upcoming.isEmpty ? null : upcoming.first;
}

/// When the catch-up should be done: a day before the next item, or halfway
/// there if that is too close, or in two days if nothing is scheduled.
DateTime catchUpDue(Activity? next, DateTime now) {
  final nextDue = next?.dueAt;
  if (nextDue == null) return now.add(const Duration(days: 2));
  final dayBefore = nextDue.subtract(const Duration(days: 1));
  if (dayBefore.isAfter(now.add(const Duration(hours: 2)))) return dayBefore;
  return now.add(nextDue.difference(now) ~/ 2);
}

/// The catch-up activity for a missed item (assumption A3: one ~45 min session).
FollowUp catchUpFor(Activity missed, Activity? next, DateTime now) {
  var before = '';
  var nextLine = '';
  if (next != null) {
    before = ' before "${next.title}"';
    final nextDue = next.dueAt;
    if (nextDue != null) {
      nextLine = ' "${next.title}" is ${describeDue(nextDue, now)} and may build on it.';
    }
  }
  return FollowUp(
    kind: ActivityKind.exercise,
    title: 'Catch up: ${baseTitle(missed.title)}',
    task: 'Cover what "${missed.title}" taught$before. Use the tutor\'s "Write the lesson" prompt '
        'for a short catch-up lesson, then do its practice task.',
    note: 'You missed "${missed.title}".$nextLine',
    estMinutes: 45,
  );
}
