import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../logic/plan_import.dart';
import '../logic/prompts.dart';
import 'widgets.dart';

/// Step 1 of planning with AI: describe the goal and copy the prompt.
class PlanWizardPage extends StatefulWidget {
  const PlanWizardPage({super.key});

  @override
  State<PlanWizardPage> createState() => _PlanWizardPageState();
}

class _PlanWizardPageState extends State<PlanWizardPage> {
  final _topic = TextEditingController();
  final _level = TextEditingController();
  final _outcome = TextEditingController();
  final _hours = TextEditingController(text: '6');
  final _equipment = TextEditingController();
  final _notes = TextEditingController();
  bool _copied = false;

  @override
  void dispose() {
    for (final c in [_topic, _level, _outcome, _hours, _equipment, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _copyPrompt() async {
    final hours = double.tryParse(_hours.text.replaceAll(',', '.')) ?? 6;
    final prompt = planPrompt(PlanRequest(
      topic: _topic.text,
      level: _level.text,
      outcome: _outcome.text,
      weeklyHours: hours <= 0 ? 6 : hours,
      equipment: _equipment.text,
      notes: _notes.text,
    ));
    await copyText(context, prompt, message: 'Prompt copied. Paste it into Claude or ChatGPT.');
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _next() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ImportPage()));
    if (!mounted) return;
    if (id != null) Navigator.of(context).pop(id);
  }

  Widget _field(TextEditingController c, String label, {String? hint, int lines = 1, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 3,
        keyboardType: type,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a course with AI')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('1. Tell the AI what you want. The more specific, the better the plan.'),
              const SizedBox(height: 16),
              _field(_topic, 'What do you want to learn?',
                  hint: 'Intro to AI engineering: train a tiny model and build an agent'),
              _field(_level, 'Your current level',
                  hint: 'C# developer, Python only hello world, no ML yet', lines: 2),
              _field(_outcome, 'At the end I want to be able to…',
                  hint: 'Train a tiny model, fine-tune a small one, build an agent with my own tool', lines: 2),
              _field(_hours, 'Hours per week', type: const TextInputType.numberWithOptions(decimal: true)),
              _field(_equipment, 'Equipment and tools',
                  hint: 'Dell G15 laptop (RTX 4050/4060), Odysseus installed, Colab as backup', lines: 2),
              _field(_notes, 'Anything else (optional)',
                  hint: 'Use Odysseus as the hands-on lab; start with a 1-week Python bridge', lines: 2),
              FilledButton.icon(
                onPressed: _copyPrompt,
                icon: const Icon(Icons.copy),
                label: const Text('Copy prompt for your AI'),
              ),
              const SizedBox(height: 24),
              const Text('2. Paste the prompt into Claude or ChatGPT. When it answers with JSON, copy the reply.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _next,
                icon: const Icon(Icons.arrow_forward),
                label: Text(_copied ? 'Next: paste the plan' : 'I already have the plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paste a plan JSON, preview it (errors, warnings, changes), then import.
/// With [courseId] it updates that course; otherwise it creates a new one.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.courseId});

  final String? courseId;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _json = TextEditingController();
  PlanValidation? _result;
  PlanDiff? _diff;
  bool _busy = false;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    final result = parsePlan(_json.text);
    PlanDiff? diff;
    final plan = result.plan;
    if (widget.courseId != null && plan != null) {
      try {
        final existing = await repo.activities(courseId: widget.courseId, includeArchived: true);
        diff = diffPlan(plan, existing);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    if (mounted) {
      setState(() {
        _result = result;
        _diff = diff;
      });
    }
  }

  Future<void> _import() async {
    final plan = _result?.plan;
    if (plan == null || !(_result?.ok ?? false)) return;
    setState(() => _busy = true);
    try {
      final id = await repo.importPlan(plan, courseId: widget.courseId);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(widget.courseId == null ? 'Import plan' : 'Update plan')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Paste the AI\'s reply. Text around the JSON and ``` fences are fine.'),
              const SizedBox(height: 12),
              TextField(
                controller: _json,
                minLines: 10,
                maxLines: 24,
                style: monoStyle,
                decoration: const InputDecoration(hintText: '{ "schemaVersion": 1, ... }'),
                onChanged: (_) {
                  if (_result != null) setState(() => _result = null);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _preview,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: (r?.ok ?? false) && !_busy ? _import : null,
                    icon: const Icon(Icons.download_done),
                    label: Text(widget.courseId == null ? 'Create course' : 'Apply changes'),
                  ),
                ],
              ),
              if (r != null) ..._previewWidgets(context, r),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _previewWidgets(BuildContext context, PlanValidation r) {
    final scheme = Theme.of(context).colorScheme;
    final plan = r.plan;
    final diff = _diff;
    return [
      const SizedBox(height: 16),
      if (r.errors.isNotEmpty)
        Card(
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fix these first (${r.errors.length})',
                    style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onErrorContainer)),
                for (final e in r.errors) Text('• $e', style: TextStyle(color: scheme.onErrorContainer)),
              ],
            ),
          ),
        ),
      if (r.warnings.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Warnings (${r.warnings.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final w in r.warnings) Text('• $w'),
              ],
            ),
          ),
        ),
      if (plan != null) ...[
        SectionHeader(plan.title.isEmpty ? '(untitled)' : plan.title),
        if (plan.goal.isNotEmpty) Text('Goal: ${plan.goal}'),
        Text(
          '${plan.kind.label} · ${plan.milestones.length} milestones · ${plan.allActivities.length} activities · '
          '${fmtMinutes(plan.totalMinutes)} in total · about '
          '${(plan.totalMinutes / (plan.weeklyHours * 60)).toStringAsFixed(1)} weeks at '
          '${fmtHours(plan.weeklyHours)} h/week',
        ),
        if (diff != null) ...[
          const SizedBox(height: 8),
          Text(
            'Changes: ${diff.added.length} new · ${diff.updated.length} updated · '
            '${diff.archived.length} leave the plan (archived, attempts kept)',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (diff.archived.isNotEmpty) Text('Leaving: ${diff.archived.join(', ')}'),
        ],
        const SizedBox(height: 8),
        for (final m in plan.milestones)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(m.title),
            subtitle: Text('${m.activities.length} activities · '
                '${fmtMinutes(m.activities.fold<int>(0, (s, a) => s + a.estMinutes))}'),
            children: [
              for (final a in m.activities)
                ListTile(
                  dense: true,
                  title: Text(a.title),
                  subtitle: Text([
                    a.kind.label,
                    fmtMinutes(a.estMinutes),
                    if (a.prerequisites.isNotEmpty) 'needs ${a.prerequisites.join(', ')}',
                    if (a.dueAt != null) 'due ${fmtDateTime(a.dueAt!.toLocal())}',
                  ].join(' · ')),
                ),
            ],
          ),
      ],
    ];
  }
}
