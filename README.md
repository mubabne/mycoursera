# MyCoursera

Your own university: several courses side by side (self-study and university),
a plan for each, sessions with an AI tutor, and a record of what you've shown you can do.

```
MyCoursera/
  docs/SPEC.md                decisions, screens, data model, rules, backlog
  docs/sample-ai-course.json  starter plan for the AI course (weeks 1-3) to test import
  supabase/schema.sql         database tables + row-level security
  web/                        the Flutter app (web now; Android/iOS later from the same code)
```

## One-time setup

1. **Flutter.** Install it (https://docs.flutter.dev/get-started/install/windows) and check with
   `flutter doctor`. Chrome is enough for the web version.
2. **Supabase project.** On https://supabase.com create a free project, then:
   - SQL Editor → New query → paste all of `supabase/schema.sql` → Run.
   - Authentication → Providers → Email: for a personal app you can turn off
     **Confirm email**, so sign-up logs you straight in.
   - Project Settings → API keys: copy the **Project URL** and the **anon / publishable key**.
3. **Config.** In `web/`, copy `env.example.json` to `env.json` and paste the two values.
   `env.json` is git-ignored, so it never gets committed.
4. **Platform files.** The `web/` folder has the app code but not Flutter's generated
   platform files. In a terminal:
   ```
   cd Desktop\MyCoursera\web
   flutter create . --platforms=web --project-name mycoursera
   flutter pub get
   ```
   `flutter create .` only adds missing files; it doesn't touch `lib/` or `test/`.

## Run

```
cd Desktop\MyCoursera\web
flutter run -d chrome --dart-define-from-file=env.json
```

Checks:
```
flutter analyze
flutter test
```

## Try it in 5 minutes

1. Create an account and sign in.
2. **Courses → New course → Import plan JSON** → paste `docs/sample-ai-course.json` → Preview → Create course.
3. **Today** shows the first activity and why. Open it.
4. In the session: pick **Hint**, **Copy prompt**, paste it into Claude or ChatGPT, paste the answer back, **Save to history**.
5. Write an answer. **Copy evaluation prompt** → paste into the AI → paste its JSON reply → **Apply AI result**.
   Try it once with "Worked solution" selected as help: a pass then adds a **Fresh check**.
6. Add a **university course**, add a lab with a due date, then choose **I missed this** on it: a catch-up appears first on Today.
7. On the course page, **Change weekly time** shows the new finish date before you save.

To plan a real course: **New course → Plan a course with AI**, fill in the form, copy the prompt,
paste it into your AI, then paste its JSON reply.

## Later: Android

```
flutter create . --platforms=android
flutter run -d <your-phone> --dart-define-from-file=env.json
```
Same code, same Supabase data. On a phone the side rail becomes a bottom bar.
