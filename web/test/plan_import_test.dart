import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycoursera/logic/json_util.dart';
import 'package:mycoursera/logic/plan_import.dart';
import 'package:mycoursera/logic/prompts.dart';
import 'package:mycoursera/models.dart';

const _valid = '''
Here is your plan:
```json
{
  "schemaVersion": 1,
  "course": {"title": "Intro to AI Engineering", "kind": "self", "goal": "Train and build", "weeklyHours": 6},
  "skills": [{"id": "py-basics", "name": "Python basics", "description": ""}],
  "milestones": [
    {"id": "m1", "title": "Python bridge", "activities": [
      {"id": "py-01", "title": "Syntax tour", "kind": "lesson", "objective": "Read Python",
       "content": "```python\\nprint('hi')\\n```", "task": "Port a loop", "criteria": "Runs",
       "estimatedMinutes": 45, "prerequisites": [], "skills": ["py-basics"], "dueAt": null},
      {"id": "py-02", "title": "Lists and dicts", "kind": "exercise", "objective": "", "content": "",
       "task": "", "criteria": "", "estimatedMinutes": 60, "prerequisites": ["py-01"], "skills": ["py-basics"], "dueAt": null}
    ]}
  ]
}
```
Good luck!''';

void main() {
  test('parses a valid plan wrapped in text and fences', () {
    final r = parsePlan(_valid);
    expect(r.errors, isEmpty);
    expect(r.ok, isTrue);
    expect(r.plan!.title, 'Intro to AI Engineering');
    expect(r.plan!.allActivities.length, 2);
    expect(r.plan!.totalMinutes, 105);
    expect(r.plan!.allActivities.first.content, contains("print('hi')"));
  });

  test('rejects broken references and duplicates', () {
    final r = parsePlan('''
{"schemaVersion": 2, "course": {"title": ""}, "skills": [],
 "milestones": [{"id": "m1", "title": "M", "activities": [
   {"id": "a", "title": "A", "kind": "lesson", "estimatedMinutes": 10, "prerequisites": ["zzz"], "skills": ["nope"]},
   {"id": "a", "title": "A again", "kind": "lesson", "estimatedMinutes": 10}
 ]}]}''');
    expect(r.ok, isFalse);
    expect(r.errors.join('\n'), allOf(
      contains('schemaVersion'),
      contains('course.title'),
      contains('"zzz"'),
      contains('"nope"'),
      contains('used twice'),
    ));
  });

  test('warns about unknown kinds and later prerequisites', () {
    final r = parsePlan('''
{"schemaVersion": 1, "course": {"title": "T", "weeklyHours": 4}, "skills": [],
 "milestones": [{"id": "m1", "title": "M", "activities": [
   {"id": "a", "title": "A", "kind": "video", "estimatedMinutes": 10, "prerequisites": ["b"]},
   {"id": "b", "title": "B", "kind": "lesson"}
 ]}]}''');
    expect(r.ok, isTrue);
    expect(r.warnings.join('\n'), allOf(contains('"video"'), contains('comes later'), contains('using 30')));
  });

  test('not JSON at all', () {
    expect(parsePlan('sorry, I cannot help').ok, isFalse);
  });

  test('diff: added, updated, archived', () {
    final plan = parsePlan(_valid).plan!;
    final existing = [
      Activity(id: '1', courseId: 'c', key: 'py-01', title: 'Syntax tour'),
      Activity(id: '2', courseId: 'c', key: 'old-01', title: 'Old lesson'),
      Activity(id: '3', courseId: 'c', key: 'adaptive-x', title: 'Fresh check', origin: Origin.adaptive),
    ];
    final d = diffPlan(plan, existing);
    expect(d.added, ['Lists and dicts']);
    expect(d.updated, ['Syntax tour']);
    expect(d.archived, ['Old lesson']);
  });

  test('export round-trips through the parser with the same ids', () {
    final course = Course(id: 'c', title: 'T', kind: CourseKind.self, goal: 'G', weeklyHours: 6, status: 'active');
    final ms = [Milestone(id: 'm-id', courseId: 'c', key: 'm1', title: 'M', position: 0, archived: false)];
    final acts = [
      Activity(id: '1', courseId: 'c', milestoneId: 'm-id', key: 'a1', title: 'A', skillKeys: const ['s1']),
      Activity(id: '2', courseId: 'c', milestoneId: 'm-id', key: 'a2', title: 'B', position: 10, prerequisites: const ['a1']),
      Activity(id: '3', courseId: 'c', milestoneId: 'm-id', key: 'adaptive-1', title: 'X', origin: Origin.adaptive),
    ];
    final skills = [
      Skill(id: 's', courseId: 'c', key: 's1', name: 'S', description: '', status: SkillStatus.practicing),
    ];
    final json = exportPlanJson(course, ms, acts, skills);
    final r = parsePlan(json);
    expect(r.errors, isEmpty);
    expect(r.plan!.allActivities.map((a) => a.id).toList(), ['a1', 'a2']);
    expect(jsonDecode(json)['schemaVersion'], 1);
  });

  test('the prompt example is itself a valid plan', () {
    expect(parsePlan(planFormatExample).errors, isEmpty);
  });

  group('AI verdict', () {
    test('reads fenced JSON', () {
      final v = parseAiVerdict('```json\n{"verdict": "FAIL", "feedback": "Off by one", "gap": "loop bounds"}\n```');
      expect(v!.verdict, Verdict.fail);
      expect(v.gap, 'loop bounds');
    });
    test('null for nonsense', () {
      expect(parseAiVerdict('looks good to me!'), isNull);
      expect(parseAiVerdict('{"verdict": "great"}'), isNull);
    });
    test('extractJsonObject keeps braces inside strings', () {
      expect(extractJsonObject('x {"a": "{b}"} y'), '{"a": "{b}"}');
    });
  });
}
