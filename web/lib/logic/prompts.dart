// Prompt builders for the copy-paste AI flow (decision D7).
// Later these same builders can feed an API or a local model instead.

import '../models.dart';
import 'format.dart';

/// What you tell the plan wizard.
class PlanRequest {
  const PlanRequest({
    required this.topic,
    required this.level,
    required this.outcome,
    required this.weeklyHours,
    required this.equipment,
    required this.notes,
  });

  final String topic;
  final String level;
  final String outcome;
  final double weeklyHours;
  final String equipment;
  final String notes;
}

const planFormatExample = r'''
{
  "schemaVersion": 1,
  "course": {
    "title": "Course title",
    "kind": "self",
    "goal": "What I will be able to do at the end (observable)",
    "weeklyHours": 6
  },
  "skills": [
    { "id": "skill-id", "name": "Skill name", "description": "One line" }
  ],
  "milestones": [
    {
      "id": "m1-short-name",
      "title": "Milestone title",
      "activities": [
        {
          "id": "act-01",
          "title": "Activity title",
          "kind": "lesson",
          "objective": "What I can do after this",
          "content": "Short lesson in Markdown",
          "task": "A concrete practice task",
          "criteria": "How to check it: expected output, edge cases, or explain in own words",
          "estimatedMinutes": 45,
          "prerequisites": [],
          "skills": ["skill-id"],
          "dueAt": null
        }
      ]
    }
  ]
}''';

String _orDash(String s) => s.trim().isEmpty ? '-' : s.trim();

String planPrompt(PlanRequest r) {
  final hours = fmtHours(r.weeklyHours);
  return '''
You are designing a self-study course for me inside my personal learning app, MyCoursera.

About me and the goal
- I want to learn: ${_orDash(r.topic)}
- My current level: ${_orDash(r.level)}
- At the end I want to be able to: ${_orDash(r.outcome)}
- Time I have: $hours hours per week
- Equipment and tools: ${_orDash(r.equipment)}
- Other notes: ${_orDash(r.notes)}

Design rules
- Split the course into milestones, and each milestone into small activities of 15-90 minutes.
- Start with what I am missing (prerequisites) before the main topic.
- The activities for the first week must fit into $hours hours.
- Every activity needs an "objective" and "criteria" I can check myself (expected output, edge cases, or "explain it in your own words").
- "kind" is one of: "lesson", "exercise", "check", "project". Use a "check" at the end of each milestone: a problem solved without help.
- Put a short lesson (max ~300 words, Markdown) in "content" and a concrete practice task in "task".
- List the skills I will demonstrate and link each activity to its skills by id.
- IDs are short, lowercase, hyphenated and unique (e.g. "py-01"). "prerequisites" lists ids of earlier activities.
- Keep "dueAt" null (this is self-paced).

Reply with ONLY the JSON, in exactly this format, with no comments or extra text:
$planFormatExample
''';
}

String planRevisionPrompt({
  required String currentPlanJson,
  required String progress,
  required String change,
}) {
  return '''
Here is my current course plan from my learning app, MyCoursera, and my progress so far.
Please revise the plan for this change: ${_orDash(change)}

Rules
- Keep the ids of activities and skills that still apply, so my history stays linked to them.
- Never reuse an old id for a different activity. New activities get new ids.
- Keep completed activities unless they truly no longer fit.
- Same JSON format as below. Reply with ONLY the JSON.

My progress
$progress

Current plan
$currentPlanJson
''';
}

String _activityContext(Course course, Activity a, String attempt) {
  return '''
Course: ${course.title}
Course goal: ${_orDash(course.goal)}
Activity: ${a.title} (${a.kind.label.toLowerCase()})
Objective: ${_orDash(a.objective)}
Success criteria: ${_orDash(a.criteria)}
Task: ${_orDash(a.task)}

Lesson notes:
${_orDash(a.content)}

My current attempt:
${attempt.trim().isEmpty ? '(nothing yet)' : attempt.trim()}''';
}

String _instruction(TutorHelp help) => switch (help) {
      TutorHelp.hint => 'Give me ONE hint that moves me one step forward. '
          'Do not give the solution and do not write the code for me.',
      TutorHelp.explain => 'Explain the idea I am missing, starting from my attempt. '
          'Point out what is wrong and why. Do not solve the whole task for me.',
      TutorHelp.worked => 'Show a fully worked solution, step by step. '
          'Then sum up the key idea in two sentences so I can do the next one alone.',
      TutorHelp.freshProblem => 'Give me ONE new problem that tests the same objective, with the '
          'expected result or test cases so I can check myself. Do not include the solution.',
      TutorHelp.lesson => 'Write a short lesson for this activity (max ~400 words, Markdown): '
          'the explanation, one worked example, and one practice task with how to check it.',
    };

/// Tutor prompt inside a lesson: includes the lesson and the current attempt.
String tutorPrompt({
  required Course course,
  required Activity activity,
  required String question,
  required String attempt,
  required TutorHelp help,
}) {
  return '''
You are my tutor in my personal learning app, MyCoursera.

${_activityContext(course, activity, attempt)}

My question: ${question.trim().isEmpty ? '(no specific question)' : question.trim()}

${_instruction(help)}
''';
}

/// Tutor prompt outside a lesson (the Tutor tab).
String standalonePrompt({required String question, required TutorHelp help, Course? course}) {
  final ctx = course == null
      ? ''
      : 'This is related to my course "${course.title}" (goal: ${_orDash(course.goal)}).\n\n';
  return '''
You are my tutor in my personal learning app, MyCoursera.
$ctx
My question:
${_orDash(question)}

${_instruction(help)}
''';
}

/// Asks the AI to judge an attempt and reply with a machine-readable verdict.
String evaluationPrompt({
  required Course course,
  required Activity activity,
  required String attempt,
  required HelpLevel help,
}) {
  return '''
Evaluate my attempt strictly against the success criteria.

${_activityContext(course, activity, attempt)}

Help I used during this attempt: ${help.label.toLowerCase()}

Reply with ONLY this JSON:
{"verdict": "pass", "feedback": "2-4 sentences", "gap": ""}

- "verdict" is "pass", "fail" or "uncertain".
- "pass" only if the attempt meets every success criterion.
- "uncertain" if you cannot judge from what I gave you (for example, code whose output I did not include). Say in "feedback" what you would need.
- "gap": if "fail", the one specific missing skill or misconception in a few words; otherwise "".
''';
}

/// Short text summary of progress for the revision prompt.
String progressSummary(List<Activity> activities, List<Skill> skills) {
  final done = activities.where((a) => a.isDone).map((a) => a.key).toList();
  final missed = activities.where((a) => a.state == ActivityState.missed).map((a) => a.key).toList();
  final lines = <String>[
    'Completed activity ids: ${done.isEmpty ? '(none)' : done.join(', ')}',
    if (missed.isNotEmpty) 'Missed activity ids: ${missed.join(', ')}',
    for (final s in skills) 'Skill "${s.key}": ${s.status.label.toLowerCase()}',
  ];
  return lines.join('\n');
}
