import 'package:flutter_test/flutter_test.dart';
import 'package:mycoursera/logic/rules.dart';
import 'package:mycoursera/models.dart';

Activity act(
  String key, {
  String course = 'c1',
  double position = 0,
  ActivityState state = ActivityState.notStarted,
  Origin origin = Origin.plan,
  List<String> prerequisites = const [],
  DateTime? dueAt,
  int minutes = 30,
  String note = '',
}) =>
    Activity(
      id: 'id-$key',
      courseId: course,
      key: key,
      title: 'Title $key',
      position: position,
      state: state,
      origin: origin,
      prerequisites: prerequisites,
      dueAt: dueAt,
      estMinutes: minutes,
      note: note,
    );

Course course(String id, {CourseKind kind = CourseKind.self}) =>
    Course(id: id, title: 'Course $id', kind: kind, goal: '', weeklyHours: 6, status: 'active');

void main() {
  group('nextSkillStatus', () {
    test('independent pass demonstrates the skill', () {
      expect(nextSkillStatus(SkillStatus.unassessed, Verdict.pass, HelpLevel.none), SkillStatus.demonstrated);
      expect(nextSkillStatus(SkillStatus.practicing, Verdict.pass, HelpLevel.hint), SkillStatus.demonstrated);
    });
    test('supported pass only reaches practicing', () {
      expect(nextSkillStatus(SkillStatus.unassessed, Verdict.pass, HelpLevel.workedSolution), SkillStatus.practicing);
      expect(nextSkillStatus(SkillStatus.unassessed, Verdict.pass, HelpLevel.explanation), SkillStatus.practicing);
    });
    test('supported pass keeps an already demonstrated skill', () {
      expect(
        nextSkillStatus(SkillStatus.demonstrated, Verdict.pass, HelpLevel.workedSolution),
        SkillStatus.demonstrated,
      );
    });
    test('fail moves back to practicing; uncertain changes nothing', () {
      expect(nextSkillStatus(SkillStatus.demonstrated, Verdict.fail, HelpLevel.none), SkillStatus.practicing);
      expect(nextSkillStatus(SkillStatus.unassessed, Verdict.uncertain, HelpLevel.none), SkillStatus.unassessed);
    });
  });

  group('followUpFor', () {
    final a = act('loops');
    test('worked solution + pass -> fresh check', () {
      final f = followUpFor(a, Verdict.pass, HelpLevel.workedSolution)!;
      expect(f.kind, ActivityKind.check);
      expect(f.title, 'Fresh check: Title loops');
    });
    test('independent pass -> nothing extra', () {
      expect(followUpFor(a, Verdict.pass, HelpLevel.none), isNull);
      expect(followUpFor(a, Verdict.pass, HelpLevel.hint), isNull);
    });
    test('fail with a gap -> short exercise on the gap', () {
      final f = followUpFor(a, Verdict.fail, HelpLevel.none, gap: 'running maximum')!;
      expect(f.kind, ActivityKind.exercise);
      expect(f.title, 'Practice: running maximum');
      expect(f.note, contains('running maximum'));
    });
    test('uncertain -> another check', () {
      expect(followUpFor(a, Verdict.uncertain, HelpLevel.none)!.title, 'Another check: Title loops');
    });
    test('titles do not stack prefixes', () {
      final check = act('x').copyTitle('Fresh check: Loops');
      expect(followUpFor(check, Verdict.pass, HelpLevel.explanation)!.title, 'Fresh check: Loops');
    });
  });

  group('nextEligible', () {
    test('waits for prerequisites', () {
      final list = [
        act('a', position: 0, state: ActivityState.completed),
        act('b', position: 10, prerequisites: ['c']),
        act('c', position: 20),
      ];
      expect(nextEligible(list)!.key, 'c');
    });
    test('follow-ups come first', () {
      final list = [
        act('a', position: 0),
        act('f', position: 10.5, origin: Origin.adaptive),
      ];
      expect(nextEligible(list)!.key, 'f');
    });
  });

  group('pickNextAction', () {
    final now = DateTime(2026, 11, 6, 16);
    final courses = {'c1': course('c1'), 'u1': course('u1', kind: CourseKind.university)};

    test('catch-up beats everything and gives its note as the reason', () {
      final list = [
        act('lab', course: 'u1', dueAt: now.add(const Duration(days: 1))),
        act('catch', course: 'u1', origin: Origin.adaptive, note: 'You missed Lab 3.'),
        act('py', position: 0),
      ];
      final n = pickNextAction(list, courses, now)!;
      expect(n.activity.key, 'catch');
      expect(n.reason, 'You missed Lab 3.');
    });
    test('item due within 3 days beats in-progress work', () {
      final list = [
        act('py', state: ActivityState.inProgress),
        act('lab', course: 'u1', dueAt: now.add(const Duration(days: 2))),
      ];
      expect(pickNextAction(list, courses, now)!.activity.key, 'lab');
    });
    test('in progress beats new work', () {
      final list = [
        act('a', position: 0),
        act('b', position: 10, state: ActivityState.inProgress),
      ];
      final n = pickNextAction(list, courses, now)!;
      expect(n.activity.key, 'b');
      expect(n.reason, contains('Pick up'));
    });
    test('null when everything is done', () {
      expect(pickNextAction([act('a', state: ActivityState.completed)], courses, now), isNull);
    });
  });

  group('estimateSchedule', () {
    final now = DateTime(2026, 11, 6);
    test('remaining time, weeks and this week fit the budget', () {
      final list = [
        act('a', position: 0, minutes: 120, state: ActivityState.completed),
        act('b', position: 10, minutes: 180),
        act('c', position: 20, minutes: 180),
        act('d', position: 30, minutes: 180),
      ];
      final e = estimateSchedule(list, 6, now);
      expect(e.remainingMinutes, 540);
      expect(e.weeks, closeTo(1.5, 0.001));
      expect(e.thisWeek.map((x) => x.key).toList(), ['b', 'c']);
      expect(e.finish, isNotNull);
    });
    test('fewer hours means a later finish', () {
      final list = [act('a', minutes: 600)];
      final six = estimateSchedule(list, 6, now).finish!;
      final four = estimateSchedule(list, 4, now).finish!;
      expect(four.isAfter(six), isTrue);
    });
    test('always offers at least one activity this week', () {
      final e = estimateSchedule([act('big', minutes: 900)], 2, now);
      expect(e.thisWeek.length, 1);
    });
  });

  group('catch-up', () {
    final now = DateTime(2026, 11, 3, 18); // Tuesday evening
    test('due a day before the next item', () {
      final missed = act('lab3', dueAt: DateTime(2026, 11, 3, 10));
      final lab4 = act('lab4', dueAt: DateTime(2026, 11, 6, 10)); // Friday
      final next = nextDatedItem(missed, [missed, lab4], now);
      expect(next!.key, 'lab4');
      expect(catchUpDue(next, now), DateTime(2026, 11, 5, 10));
      final f = catchUpFor(missed, next, now);
      expect(f.title, 'Catch up: Title lab3');
      expect(f.note, contains('Title lab4'));
    });
    test('halfway when the next item is very close', () {
      final next = act('lab4', dueAt: now.add(const Duration(hours: 20)));
      expect(catchUpDue(next, now), now.add(const Duration(hours: 10)));
    });
    test('two days when nothing else is scheduled', () {
      expect(catchUpDue(null, now), now.add(const Duration(days: 2)));
    });
  });
}

extension on Activity {
  Activity copyTitle(String title) => Activity(id: id, courseId: courseId, key: key, title: title);
}
