# MyCoursera — build spec (v1)

A personal "online university": several courses side by side, a plan for each,
sessions with an AI tutor, and a record of what you have actually shown you can do.

---

## 1. Decision log

| # | Decision | Date |
|---|---|---|
| D1 | First learner is Muba. Personal tool first; production later is possible but not a constraint. | 2026-11-06 |
| D2 | Several courses at once is a core feature from the start. | 2026-11-06 |
| D3 | Two kinds of course: **self** (system designs and adjusts the plan) and **university** (dates come from outside; the system tracks labs/deadlines, plans catch-ups, reminds). | 2026-11-06 |
| D4 | First course to build and test with: *Intro to AI Engineering — train a model, build an agent*. ~6 h/week, ~11 weeks, starts with a 1-week Python bridge. Odysseus is the hands-on lab. Dell G15 (RTX 4050/4060) + Colab as backup. | 2026-11-06 |
| D5 | Stack: **Flutter + Supabase**. One Flutter codebase for web and mobile. | 2026-11-06 |
| D6 | **Web first**, mobile next from the same codebase. | 2026-11-06 |
| D7 | AI by **copy-paste** in v1: the app builds the prompt, you paste it into Claude/ChatGPT, then paste the answer back. No API key or cost. Plans come in as JSON the same way. | 2026-11-06 |
| D8 | Code lives in `Desktop/MyCoursera/web`. | 2026-11-06 |

## 2. Assumptions being tested

- A1. "Independent" evidence = an attempt with **no help or only hints**. Explanations and worked solutions count as **supported**.
- A2. A failed attempt on a Demonstrated skill moves it back to Practicing (a review can undo "demonstrated").
- A3. One catch-up activity (≈45 min) due a day before the next university item is enough for a missed lab.
- A4. Muba already programs in C#, so Python is a new language, not new programming.
- A5. A plan written by an external AI, checked by the app's validator, is good enough to follow.

## 3. Open questions

- What went wrong with AI-generated roadmaps tried before? (tells us what the plan must do differently)
- Reminders on web are in-app only in v1. Push notifications come with the mobile build — which reminders matter most?
- Later: switch the tutor from copy-paste to an API (Claude/OpenAI) or the local Odysseus model, behind the same prompt builders.

---

## 4. Screens (v1, web)

| Screen | What you see and do |
|---|---|
| **Sign in** | Email + password (Supabase Auth). |
| **Today** | One next action with a time estimate and the reason it was picked. Deadlines and reminders for the next 7 days (overdue in red). What's next in each course. |
| **Courses** | All courses with progress. *New course*: plan with AI (self-study), university course, or import plan JSON. |
| **Course** | Goal, weekly hours, time left and finish estimate, "this week" list, milestones and activities. Change weekly time (preview before saving). Update plan from JSON (preview of what changes). Copy plan as JSON / copy a revision prompt. University: add items with due dates, mark an item missed → catch-up. |
| **Session** | Why this activity, objective, lesson, task, criteria. Answer box. Tutor panel: Hint / Explain / Worked solution / New problem / Write the lesson → copy prompt → paste answer → saved. Submit: AI evaluation (paste JSON verdict) or self-assessment. Result shows the recommendation and why. |
| **Tutor** | Ask anything outside a lesson. Attach the question to a course or turn it into a practice activity. |
| **Progress** | Per course: activities completed (separate), skills with status, and the attempts behind each status. |

## 5. Data model (Supabase / Postgres)

All tables have `user_id` (defaults to `auth.uid()`) and row-level security: you only see your own rows.

- **courses** — title, kind (`self`/`university`), goal, weekly_hours, status
- **milestones** — course, key, title, position
- **skills** — course, key, name, description, **status** (`unassessed`/`practicing`/`demonstrated`)
- **activities** — course, milestone, key, title, kind (`lesson`/`exercise`/`check`/`lab`/`assignment`/`exam`/`project`), objective, content, task, criteria, est_minutes, position, prerequisites (activity keys), skill_keys, due_at, **state** (`not_started`/`in_progress`/`completed`/`missed`), origin (`plan`/`manual`/`adaptive`), note (why it exists), source_activity_id, archived
- **attempts** — activity, client_attempt_id (unique → double-submit makes one attempt), answer, help_level (`none`/`hint`/`explanation`/`worked_solution`), verdict (`pass`/`fail`/`uncertain`), evaluated_by (`self`/`ai`), feedback, gap
- **tutor_exchanges** — optional course and activity, help_type, question, prompt, response

Plan IDs (`key`) are stable. Re-importing a plan matches activities by key, so attempts and states stay attached. Activities that disappear from a new plan are **archived**, never deleted.

## 6. Adaptation rules (app applies them; the AI only proposes a verdict)

| Signal | What the app does |
|---|---|
| Pass, no help or hints | Skill → **Demonstrated**. Activity completed. Next eligible activity. |
| Pass after explanation / worked solution | Skill → **Practicing** (stays Demonstrated if it already was). Activity completed. Adds a **fresh check** right after it. |
| Fail with a gap | Skill → **Practicing**. Activity stays in progress. Adds a **short exercise on the gap** first. |
| Uncertain | Skill unchanged. Adds **another check**. |
| Missed university item | Item marked missed. Adds a **catch-up** due a day before the next item in that course. |
| Weekly time changes | Time left and finish date recalculated; preview before saving. History untouched. |
| You disagree | You can open any activity or mark a lesson complete yourself. Evidence is kept. |

**Next action order (Today):** adaptive items (catch-ups, checks, gap exercises) → university items due within 3 days → anything in progress → next activity whose prerequisites are done.

## 7. Plan JSON (schemaVersion 1)

```json
{
  "schemaVersion": 1,
  "course": { "title": "Intro to AI Engineering", "kind": "self", "goal": "Train a tiny model, fine-tune a small one, build an agent", "weeklyHours": 6 },
  "skills": [ { "id": "py-basics", "name": "Python basics", "description": "Syntax, lists, dicts, functions" } ],
  "milestones": [
    {
      "id": "m1-python",
      "title": "Python bridge",
      "activities": [
        {
          "id": "py-01",
          "title": "Python vs C#: syntax tour",
          "kind": "lesson",
          "objective": "Read and write basic Python",
          "content": "Short lesson text…",
          "task": "Rewrite this C# loop in Python…",
          "criteria": "Runs and prints the expected output; uses a for loop",
          "estimatedMinutes": 45,
          "prerequisites": [],
          "skills": ["py-basics"],
          "dueAt": null
        }
      ]
    }
  ]
}
```

The validator rejects: wrong schemaVersion, missing title, duplicate IDs, prerequisites or skills that point nowhere. It warns about unknown kinds, missing minutes and prerequisites that come later in the plan.

## 8. Backlog

**In this build (first slice)**
1. Sign in; per-user data with RLS
2. Courses (self + university), plan prompt, JSON import with preview and diff
3. Today: next action with reason, deadlines, up-next per course
4. Session: lesson, tutor copy-paste (5 prompt types), answer, AI or self evaluation
5. Adaptation rules: fresh check, gap exercise, another check, skill status changes
6. Missed item → catch-up; weekly-time change with preview
7. Progress with evidence; standalone tutor with attach / turn into practice
8. Plan export JSON and revision prompt

**Next**
9. Android build from the same code; push reminders (Firebase Cloud Messaging)
10. Live sync between devices (Supabase Realtime)
11. Review queue (spaced review of demonstrated skills)
12. Tutor through an API or the local Odysseus model
13. Image questions, running code submissions

## 9. Acceptance criteria (first slice)

1. Given a goal and weekly hours, you can import a plan, see the outcome, and see a first activity that fits one week.
2. You can open that activity, copy a tutor prompt that includes the lesson and your attempt, save the answer, submit work, and reopen the session with the attempt there.
3. A pass after a worked solution adds a fresh check; an independent pass marks the skill Demonstrated. Both show why.
4. Changing weekly hours shows the new finish estimate before saving; completed work and attempts are unchanged. Marking a university item missed adds a catch-up before the next item.
5. Submitting the same attempt twice records one attempt. (Cross-device check comes with the mobile build.)
