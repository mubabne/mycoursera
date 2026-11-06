import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../logic/ids.dart';
import '../logic/json_util.dart';
import '../logic/prompts.dart';
import '../logic/rules.dart';
import '../models.dart';
import 'widgets.dart';

class _SessionData {
  _SessionData(this.activity, this.course, this.exchanges, this.attempts);

  final Activity activity;
  final Course course;
  final List<TutorExchange> exchanges;
  final List<Attempt> attempts;
}

/// What happened after a submit, shown under the evaluation.
class _Result {
  _Result({
    required this.verdict,
    required this.help,
    required this.feedback,
    required this.duplicate,
    required this.skillChanges,
    this.followUp,
    this.next,
  });

  final Verdict verdict;
  final HelpLevel help;
  final String feedback;
  final bool duplicate;
  final Map<String, SkillStatus> skillChanges;
  final Activity? followUp;
  final Activity? next;
}

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.activityId});

  final String activityId;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  late Future<_SessionData> _future = _load();

  final _answer = TextEditingController();
  final _question = TextEditingController();
  final _response = TextEditingController();
  final _aiReply = TextEditingController();
  final _gap = TextEditingController();

  TutorHelp _helpType = TutorHelp.hint;
  HelpLevel _helpUsed = HelpLevel.none;
  String? _lastPrompt;
  String _clientAttemptId = uuidV4();
  Verdict _selfVerdict = Verdict.pass;
  _Result? _result;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_answer, _question, _response, _aiReply, _gap]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<_SessionData> _load() async {
    var a = await repo.activity(widget.activityId);
    if (a.state == ActivityState.notStarted) {
      await repo.setActivityState(a, ActivityState.inProgress);
      a = await repo.activity(widget.activityId);
    }
    final course = await repo.course(a.courseId);
    final exchanges = await repo.exchanges(activityId: a.id);
    final attempts = await repo.attempts(activityId: a.id);
    return _SessionData(a, course, exchanges, attempts);
  }

  void _reload() => setState(() => _future = _load());

  // ----------------------------------------------------------------- tutor

  Future<void> _copyTutorPrompt(_SessionData d) async {
    final prompt = tutorPrompt(
      course: d.course,
      activity: d.activity,
      question: _question.text,
      attempt: _answer.text,
      help: _helpType,
    );
    await copyText(context, prompt, message: 'Prompt copied. Paste it into Claude or ChatGPT.');
    if (!mounted) return;
    setState(() {
      _lastPrompt = prompt;
      _helpUsed = _helpUsed.max(_helpType.level);
    });
  }

  Future<void> _saveExchange(_SessionData d, {bool asLesson = false}) async {
    final response = _response.text.trim();
    if (response.isEmpty) {
      showMessage(context, 'Paste the AI\'s answer first.');
      return;
    }
    try {
      await repo.saveExchange(
        courseId: d.course.id,
        activityId: d.activity.id,
        help: _helpType,
        question: _question.text.trim(),
        prompt: _lastPrompt ?? '',
        response: response,
      );
      if (asLesson) await repo.updateActivityContent(d.activity.id, response);
      if (!mounted) return;
      _response.clear();
      _question.clear();
      _lastPrompt = null;
      showMessage(context, asLesson ? 'Saved as the lesson.' : 'Saved to this session\'s history.');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ------------------------------------------------------------ evaluation

  Future<void> _copyEvaluationPrompt(_SessionData d) async {
    if (_answer.text.trim().isEmpty) {
      showMessage(context, 'Write or paste your answer first.');
      return;
    }
    final prompt = evaluationPrompt(
      course: d.course,
      activity: d.activity,
      attempt: _answer.text,
      help: _helpUsed,
    );
    await copyText(context, prompt, message: 'Evaluation prompt copied. Paste the JSON reply below.');
  }

  Future<void> _applyAiReply(_SessionData d) async {
    final v = parseAiVerdict(_aiReply.text);
    if (v == null) {
      showMessage(context, 'Could not read a verdict. The reply needs {"verdict": "pass" | "fail" | "uncertain", ...}.');
      return;
    }
    await _submit(d, verdict: v.verdict, evaluatedBy: 'ai', feedback: v.feedback, gap: v.gap);
  }

  Future<void> _submit(
    _SessionData d, {
    required Verdict verdict,
    required String evaluatedBy,
    String feedback = '',
    String gap = '',
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final help = _helpUsed;
    try {
      final res = await repo.submitAttempt(
        activity: d.activity,
        clientAttemptId: _clientAttemptId,
        answer: _answer.text,
        help: help,
        verdict: verdict,
        evaluatedBy: evaluatedBy,
        feedback: feedback,
        gap: gap,
      );
      final courseActivities = await repo.activities(courseId: d.activity.courseId);
      final next = nextEligible(courseActivities);
      if (!mounted) return;
      setState(() {
        _result = _Result(
          verdict: verdict,
          help: help,
          feedback: feedback,
          duplicate: res.duplicate,
          skillChanges: res.skillChanges,
          followUp: res.followUp,
          next: next != null && next.id != d.activity.id ? next : null,
        );
        if (!res.duplicate) {
          _clientAttemptId = uuidV4();
          _helpUsed = HelpLevel.none;
          _aiReply.clear();
          _gap.clear();
        }
        _future = _load();
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeLesson(_SessionData d) async {
    try {
      await repo.setActivityState(d.activity, ActivityState.completed);
      final next = nextEligible(await repo.activities(courseId: d.activity.courseId));
      if (!mounted) return;
      showMessage(context, next == null ? 'Lesson completed.' : 'Lesson completed. Next: ${next.title}');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _goTo(Activity a) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => SessionPage(activityId: a.id)),
    );
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return RouteLoader<_SessionData>(
      future: _future,
      title: 'Session',
      builder: (context, d) => Scaffold(
        appBar: AppBar(title: Text(d.activity.title)),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final work = _workColumn(context, d);
            final tutor = _tutorColumn(context, d);
            if (constraints.maxWidth >= 1000) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: ListView(padding: const EdgeInsets.all(16), children: work),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 2,
                    child: ListView(padding: const EdgeInsets.all(16), children: tutor),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [...work, const Divider(height: 32), ...tutor],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _workColumn(BuildContext context, _SessionData d) {
    final a = d.activity;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final due = a.dueAt;
    final isPlainLesson = a.kind == ActivityKind.lesson && a.task.isEmpty;

    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text(d.course.title)),
          Chip(label: Text(a.kind.label)),
          Chip(label: Text(fmtMinutes(a.estMinutes))),
          Chip(label: Text(a.state.label)),
          if (due != null) Chip(label: Text('Due ${describeDue(due, now)}')),
        ],
      ),
      const SizedBox(height: 12),
      if (a.note.isNotEmpty)
        Card(
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Why this: ${a.note}', style: TextStyle(color: scheme.onSecondaryContainer)),
          ),
        ),
      if (a.objective.isNotEmpty) TextBlock(title: 'Objective', text: a.objective),
      if (a.content.isNotEmpty)
        TextBlock(title: 'Lesson', text: a.content)
      else
        const InfoCard(
          icon: Icons.menu_book_outlined,
          title: 'No lesson text yet',
          body: 'In the tutor panel choose "Write the lesson", copy the prompt, then save the answer '
              'with "Save as lesson".',
        ),
      if (a.task.isNotEmpty) TextBlock(title: 'Task', text: a.task),
      if (a.criteria.isNotEmpty) TextBlock(title: 'How it is checked', text: a.criteria),
      if (isPlainLesson && !a.isDone)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.icon(
            onPressed: () => _completeLesson(d),
            icon: const Icon(Icons.check),
            label: const Text('Mark lesson complete'),
          ),
        ),
      if (!isPlainLesson) ..._attemptSection(context, d),
      if (_result != null) _resultCard(context, _result!),
      SectionHeader('Attempts (${d.attempts.length})'),
      if (d.attempts.isEmpty) const Text('No attempts yet.'),
      for (final t in d.attempts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(verdictIcon(t.verdict)),
          title: Text('${t.verdict.label} · ${t.help.label} · ${t.evaluatedBy == 'ai' ? 'AI' : 'self'} check'),
          subtitle: Text([
            if (t.createdAt != null) fmtDateTime(t.createdAt!),
            if (t.feedback.isNotEmpty) t.feedback,
            if (t.gap.isNotEmpty) 'Gap: ${t.gap}',
          ].join('\n')),
        ),
    ];
  }

  List<Widget> _attemptSection(BuildContext context, _SessionData d) {
    return [
      const SectionHeader('Your answer'),
      TextField(
        controller: _answer,
        minLines: 6,
        maxLines: 20,
        style: monoStyle,
        decoration: const InputDecoration(
          hintText: 'Paste your code and its output, or explain in your own words.',
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Text('Help used for this attempt: '),
          DropdownButton<HelpLevel>(
            value: _helpUsed,
            items: [for (final h in HelpLevel.values) DropdownMenuItem(value: h, child: Text(h.label))],
            onChanged: (h) => setState(() => _helpUsed = h ?? _helpUsed),
          ),
        ],
      ),
      Text(
        _helpUsed.isSupported
            ? 'With this much help, a pass is recorded as supported and a fresh check follows.'
            : 'No help or hints only: a pass counts as doing it on your own.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SectionHeader('Check your work'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('With AI', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _copyEvaluationPrompt(d),
                icon: const Icon(Icons.copy),
                label: const Text('Copy evaluation prompt'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _aiReply,
                minLines: 2,
                maxLines: 6,
                style: monoStyle,
                decoration: const InputDecoration(hintText: 'Paste the AI\'s JSON reply here'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : () => _applyAiReply(d),
                child: const Text('Apply AI result'),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Myself', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<Verdict>(
                segments: [
                  for (final v in Verdict.values) ButtonSegment(value: v, label: Text(v.label)),
                ],
                selected: {_selfVerdict},
                onSelectionChanged: (s) => setState(() => _selfVerdict = s.first),
              ),
              if (_selfVerdict == Verdict.fail) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _gap,
                  decoration: const InputDecoration(labelText: 'What was missing? (a few words)'),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _submit(d, verdict: _selfVerdict, evaluatedBy: 'self', gap: _gap.text.trim()),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _resultCard(BuildContext context, _Result r) {
    final scheme = Theme.of(context).colorScheme;
    final lines = <String>[];
    if (r.duplicate) {
      lines.add('This attempt was already recorded, so nothing changed.');
    } else {
      lines.add(switch (r.verdict) {
        Verdict.pass => r.help.isSupported
            ? 'Passed with ${r.help.label.toLowerCase()}. Recorded as a supported attempt.'
            : 'Passed on your own.',
        Verdict.fail => 'Not yet.',
        Verdict.uncertain => 'This could not be judged, so the skill status stays as it was.',
      });
      if (r.feedback.isNotEmpty) lines.add(r.feedback);
      for (final e in r.skillChanges.entries) {
        lines.add('Skill "${e.key}": ${e.value.label}.');
      }
      final f = r.followUp;
      if (f != null) {
        lines.add('Next: ${f.title}. ${f.note}');
      } else if (r.next != null) {
        lines.add('Next: ${r.next!.title}.');
      }
    }
    final target = r.followUp ?? r.next;
    return Card(
      color: r.verdict == Verdict.pass ? scheme.primaryContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (target != null)
                  FilledButton(onPressed: () => _goTo(target), child: Text('Start: ${target.title}')),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _tutorColumn(BuildContext context, _SessionData d) {
    return [
      Text('Tutor', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('The prompt includes this lesson and your current answer.'),
      const SizedBox(height: 12),
      TextField(
        controller: _question,
        minLines: 1,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'What are you stuck on? (optional)'),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final h in TutorHelp.values)
            ChoiceChip(
              label: Text(h.label),
              selected: _helpType == h,
              onSelected: (_) => setState(() => _helpType = h),
            ),
        ],
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: () => _copyTutorPrompt(d),
        icon: const Icon(Icons.copy),
        label: const Text('Copy prompt'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _response,
        minLines: 3,
        maxLines: 12,
        decoration: const InputDecoration(labelText: 'Paste the AI\'s answer'),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonal(onPressed: () => _saveExchange(d), child: const Text('Save to history')),
          if (_helpType == TutorHelp.lesson)
            OutlinedButton(
              onPressed: () => _saveExchange(d, asLesson: true),
              child: const Text('Save as lesson'),
            ),
        ],
      ),
      SectionHeader('History (${d.exchanges.length})'),
      if (d.exchanges.isEmpty) const Text('Nothing saved yet.'),
      for (final x in d.exchanges)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('${x.help.label}: ${x.question.isEmpty ? '(no question)' : x.question}'),
          subtitle: x.createdAt == null ? null : Text(fmtDateTime(x.createdAt!)),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [SelectableText(x.response)],
        ),
    ];
  }
}
