import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../logic/prompts.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

class _TutorData {
  _TutorData(this.courses, this.exchanges);

  final List<Course> courses;
  final List<TutorExchange> exchanges;
}

/// Ask the tutor outside a lesson. A question can be attached to a course or
/// turned into a practice activity.
class TutorPage extends StatefulWidget {
  const TutorPage({super.key});

  @override
  State<TutorPage> createState() => _TutorPageState();
}

class _TutorPageState extends State<TutorPage> {
  late Future<_TutorData> _future = _load();

  final _question = TextEditingController();
  final _response = TextEditingController();
  TutorHelp _help = TutorHelp.explain;
  String? _courseId;
  String? _lastPrompt;

  static const _helps = [TutorHelp.hint, TutorHelp.explain, TutorHelp.worked, TutorHelp.freshProblem];

  @override
  void dispose() {
    _question.dispose();
    _response.dispose();
    super.dispose();
  }

  Future<_TutorData> _load() async => _TutorData(await repo.courses(), await repo.exchanges());

  void _reload() => setState(() => _future = _load());

  Course? _course(List<Course> courses, String? id) {
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _copy(_TutorData d) async {
    if (_question.text.trim().isEmpty) {
      showMessage(context, 'Type your question first.');
      return;
    }
    final prompt = standalonePrompt(question: _question.text, help: _help, course: _course(d.courses, _courseId));
    await copyText(context, prompt, message: 'Prompt copied. Paste it into Claude or ChatGPT.');
    if (mounted) setState(() => _lastPrompt = prompt);
  }

  Future<void> _save() async {
    if (_response.text.trim().isEmpty) {
      showMessage(context, 'Paste the AI\'s answer first.');
      return;
    }
    try {
      await repo.saveExchange(
        courseId: _courseId,
        help: _help,
        question: _question.text.trim(),
        prompt: _lastPrompt ?? '',
        response: _response.text.trim(),
      );
      if (!mounted) return;
      _question.clear();
      _response.clear();
      _lastPrompt = null;
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _attach(TutorExchange x, List<Course> courses) async {
    final c = await pickCourse(context, courses, title: 'Attach to which course?');
    if (c == null) return;
    try {
      await repo.attachExchange(x.id, c.id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toPractice(TutorExchange x, List<Course> courses) async {
    final c =
        _course(courses, x.courseId) ?? await pickCourse(context, courses, title: 'Add practice to which course?');
    if (c == null) return;
    final q = x.question.trim();
    try {
      await repo.addActivity(
        courseId: c.id,
        title: q.length > 60 ? '${q.substring(0, 60)}…' : (q.isEmpty ? 'Practice from a question' : q),
        kind: ActivityKind.exercise,
        task: q,
        estMinutes: 20,
        note: 'From a question you asked the tutor. Solve a similar problem on your own.',
      );
      if (mounted) showMessage(context, 'Added a practice activity to ${c.title}.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutor')),
      body: Loader<_TutorData>(
        future: _future,
        builder: (context, d) {
          final scheme = Theme.of(context).colorScheme;
          return PageList(
            children: [
              _StepCard(
                step: 1,
                title: 'Ask your question',
                subtitle: 'Bring any question. You can connect it to a course afterwards.',
                children: [
                  TextField(
                    controller: _question,
                    minLines: 3,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Why does my C program return the wrong maximum? (paste the code)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final h in _helps)
                        ChoiceChip(
                          label: Text(h.label),
                          selected: _help == h,
                          onSelected: (_) => setState(() => _help = h),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _courseId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Course (optional)',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No course')),
                      for (final c in d.courses)
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _courseId = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _copy(d),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy prompt'),
                  ),
                ],
              ),
              _StepCard(
                step: 2,
                title: 'Paste the answer',
                subtitle: 'Paste the prompt into Claude or ChatGPT, then bring the reply back here.',
                children: [
                  TextField(
                    controller: _response,
                    minLines: 3,
                    maxLines: 12,
                    decoration: const InputDecoration(hintText: 'The AI\'s answer…'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _save,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save'),
                  ),
                ],
              ),
              SectionHeader('Past questions', icon: Icons.history, trailing: MetaPill('${d.exchanges.length}')),
              if (d.exchanges.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Nothing saved yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final x in d.exchanges) _exchangeTile(x, d),
            ],
          );
        },
      ),
    );
  }

  Widget _exchangeTile(TutorExchange x, _TutorData d) {
    final course = _course(d.courses, x.courseId);
    final color = course == null ? Theme.of(context).colorScheme.primary : courseColor(context, course.id);
    return Card(
      child: ExpansionTile(
        leading: IconBadge(icon: Icons.chat_bubble_outline, color: color, size: 36),
        title: Text(
          x.question.isEmpty ? '(no question)' : x.question,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text([
          x.help.label,
          if (course != null) course.title,
          if (x.createdAt != null) fmtDateTime(x.createdAt!),
        ].join(' · ')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(x.response, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (course == null)
                OutlinedButton.icon(
                  onPressed: () => _attach(x, d.courses),
                  icon: const Icon(Icons.link),
                  label: const Text('Attach to a course'),
                ),
              OutlinedButton.icon(
                onPressed: () => _toPractice(x, d.courses),
                icon: const Icon(Icons.fitness_center),
                label: const Text('Turn into practice'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A numbered step in a copy-paste flow.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.title, required this.subtitle, required this.children});

  final int step;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  child: Text('$step',
                      style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      Text(subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
