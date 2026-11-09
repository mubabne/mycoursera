import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/format.dart';
import '../logic/plan_import.dart';
import '../logic/prompts.dart';
import '../logic/rules.dart';
import '../models.dart';
import 'import_page.dart';
import 'session_page.dart';
import 'theme.dart';
import 'widgets.dart';

class _CourseData {
  _CourseData(this.course, this.milestones, this.activities, this.skills);

  final Course course;
  final List<Milestone> milestones;
  final List<Activity> activities;
  final List<Skill> skills;
}

class CoursePage extends StatefulWidget {
  const CoursePage({super.key, required this.courseId});

  final String courseId;

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  late Future<_CourseData> _future = _load();

  Future<_CourseData> _load() async => _CourseData(
        await repo.course(widget.courseId),
        await repo.milestones(widget.courseId),
        await repo.activities(courseId: widget.courseId),
        await repo.skills(courseId: widget.courseId),
      );

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Activity a) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionPage(activityId: a.id)));
    if (mounted) _reload();
  }

  // ------------------------------------------------------------------ menu

  Future<void> _menu(String value, _CourseData d) async {
    switch (value) {
      case 'weekly':
        await _changeWeekly(d);
      case 'import':
        await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => ImportPage(courseId: d.course.id)),
        );
        if (mounted) _reload();
      case 'export':
        await copyText(
          context,
          exportPlanJson(d.course, d.milestones, d.activities, d.skills),
          message: 'Plan JSON copied.',
        );
      case 'revise':
        await _copyRevisionPrompt(d);
    }
  }

  Future<void> _copyRevisionPrompt(_CourseData d) async {
    final controller = TextEditingController();
    final change = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What should change?'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'e.g. I only have 4 hours a week now; add a milestone on RAG before agents',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Copy prompt'),
          ),
        ],
      ),
    );
    if (change == null || !mounted) return;
    final prompt = planRevisionPrompt(
      currentPlanJson: exportPlanJson(d.course, d.milestones, d.activities, d.skills),
      progress: progressSummary(d.activities, d.skills),
      change: change,
    );
    await copyText(
      context,
      prompt,
      message: 'Prompt copied. Paste the AI\'s JSON reply into "Update plan from JSON".',
    );
  }

  Future<void> _changeWeekly(_CourseData d) async {
    final controller = TextEditingController(text: fmtHours(d.course.weeklyHours));
    final now = DateTime.now();
    final current = estimateSchedule(d.activities, d.course.weeklyHours, now);
    final hours = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
          final double? newHours = parsed != null && parsed > 0 ? parsed : null;
          final proposed = newHours == null ? null : estimateSchedule(d.activities, newHours, now);
          return AlertDialog(
            title: const Text('Weekly time'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Hours per week'),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text('Now: ${_estimateShort(current, d.course.weeklyHours)}'),
                  if (proposed != null && newHours != null)
                    Text(
                      'New: ${_estimateShort(proposed, newHours)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 12),
                  const Text('Completed work and attempts stay as they are.'),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: newHours == null ? null : () => Navigator.pop(context, newHours),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (hours == null) return;
    try {
      await repo.updateCourse(d.course.id, {'weekly_hours': hours});
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _estimateShort(ScheduleEstimate e, double hours) {
    final finish = e.finish;
    if (e.remainingMinutes == 0 || finish == null) return 'nothing left to do';
    return '${fmtHours(hours)} h/week → about ${e.weeks.toStringAsFixed(1)} weeks, '
        'finish around ${fmtDate(finish)}';
  }

  // ------------------------------------------------------------ activities

  Future<void> _activityMenu(String value, Activity a) async {
    try {
      if (value == 'done') {
        await repo.setActivityState(a, ActivityState.completed);
        if (mounted) _reload();
      } else if (value == 'missed') {
        await _markMissed(a);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _markMissed(Activity a) async {
    final catchUp = await repo.markMissed(a);
    if (!mounted) return;
    _reload();
    final due = catchUp.dueAt;
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Catch-up added'),
        content: SizedBox(
          width: 420,
          child: Text(
            '${catchUp.note}\n\n'
            'Plan: "${catchUp.title}", ${fmtMinutes(catchUp.estMinutes)}, '
            'by ${due == null ? 'soon' : fmtDateTime(due)}.\n'
            'It stays first on Today until it is done.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('OK')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start now')),
        ],
      ),
    );
    if (start == true && mounted) await _open(catchUp);
  }

  Future<void> _addItem(_CourseData d) async {
    final item = await showDialog<_NewItem>(context: context, builder: (_) => const _AddItemDialog());
    if (item == null) return;
    try {
      await repo.addActivity(
        courseId: d.course.id,
        title: item.title,
        kind: item.kind,
        estMinutes: item.minutes,
        dueAt: item.dueAt,
      );
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return RouteLoader<_CourseData>(
      future: _future,
      title: 'Course',
      builder: (context, d) {
        final isSelf = d.course.kind == CourseKind.self;
        return Scaffold(
          appBar: AppBar(
            title: Text(d.course.title),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) => _menu(v, d),
                itemBuilder: (context) => [
                  if (isSelf) const PopupMenuItem(value: 'weekly', child: Text('Change weekly time')),
                  const PopupMenuItem(value: 'import', child: Text('Update plan from JSON')),
                  const PopupMenuItem(value: 'revise', child: Text('Copy plan-revision prompt')),
                  const PopupMenuItem(value: 'export', child: Text('Copy plan as JSON')),
                ],
              ),
            ],
          ),
          floatingActionButton: isSelf
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _addItem(d),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
          body: _body(context, d),
        );
      },
    );
  }

  Widget _body(BuildContext context, _CourseData d) {
    final now = DateTime.now();
    final isSelf = d.course.kind == CourseKind.self;
    final est = estimateSchedule(d.activities, d.course.weeklyHours, now);
    final milestoneIds = {for (final m in d.milestones) m.id};
    final loose = sortedByPosition(
      d.activities.where((x) => x.milestoneId == null || !milestoneIds.contains(x.milestoneId)),
    );
    final thisWeekMinutes = est.thisWeek.fold<int>(0, (s, x) => s + x.estMinutes);
    final openCount = d.activities.where((x) => x.isOpen).length;

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = courseColor(context, d.course.id);
    final planned = d.activities.where((x) => x.origin != Origin.adaptive).toList();
    final done = planned.where((x) => x.isDone).length;
    final ratio = planned.isEmpty ? 0.0 : done / planned.length;

    return PageList(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(
                      icon: isSelf ? Icons.school_outlined : Icons.account_balance_outlined,
                      color: color,
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.course.kind.label.toUpperCase(),
                              style: text.labelSmall
                                  ?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                          if (d.course.goal.isNotEmpty)
                            Text(d.course.goal, style: text.titleMedium)
                          else
                            Text(d.course.title, style: text.titleMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: ratio, color: color)),
                    const SizedBox(width: 12),
                    Text('${(ratio * 100).round()}%',
                        style: text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatTile(value: '$done/${planned.length}', label: 'done', color: color),
                    if (isSelf)
                      StatTile(value: fmtMinutes(est.remainingMinutes), label: 'left', color: color)
                    else
                      StatTile(value: '$openCount', label: 'open items', color: color),
                    if (isSelf) StatTile(value: '${fmtHours(d.course.weeklyHours)} h', label: 'per week', color: color),
                  ],
                ),
                if (isSelf) ...[
                  const SizedBox(height: 12),
                  Text(
                    est.remainingMinutes == 0
                        ? 'Everything in this plan is done.'
                        : _estimateShort(est, d.course.weeklyHours),
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _changeWeekly(d),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Change weekly time'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (d.activities.isEmpty)
          InfoCard(
            icon: Icons.inbox_outlined,
            title: 'Nothing here yet',
            body: isSelf
                ? 'Use the menu → "Update plan from JSON" to add a plan.'
                : 'Tap "Add item" to add a lab, assignment or exam with its due date.',
          ),
        if (isSelf && est.thisWeek.isNotEmpty)
          _group(context, 'This week', est.thisWeek, now,
              icon: Icons.date_range_outlined, trailing: fmtMinutes(thisWeekMinutes)),
        for (final m in d.milestones)
          _group(context, m.title, sortedByPosition(d.activities.where((x) => x.milestoneId == m.id)), now,
              icon: Icons.flag_outlined, showCount: true),
        if (loose.isNotEmpty)
          _group(context, isSelf ? 'Other activities' : 'Items', loose, now, icon: Icons.list_alt_outlined),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    List<Activity> items,
    DateTime now, {
    IconData? icon,
    String? trailing,
    bool showCount = false,
  }) {
    final done = items.where((a) => a.isDone).length;
    final label = trailing ?? (showCount && items.isNotEmpty ? '$done/${items.length}' : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title,
          icon: icon,
          trailing: label == null ? null : MetaPill(label),
        ),
        if (items.isEmpty)
          const SizedBox.shrink()
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [for (final a in items) _tile(context, a, now)]),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, Activity a, DateTime now) {
    final due = a.dueAt;
    final overdue = a.isOpen && due != null && due.isBefore(now);
    return ActivityTile(
      activity: a,
      warn: overdue || a.state == ActivityState.missed,
      subtitle: [
        a.kind.label,
        fmtMinutes(a.estMinutes),
        if (due != null) 'due ${describeDue(due, now)}',
        if (a.origin == Origin.adaptive) 'follow-up',
        if (a.state != ActivityState.notStarted) a.state.label.toLowerCase(),
      ].join(' · '),
      trailing: a.isOpen
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.outline),
              onSelected: (v) => _activityMenu(v, a),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'done',
                  child:
                      ListTile(leading: Icon(Icons.check), title: Text('Mark done'), contentPadding: EdgeInsets.zero),
                ),
                PopupMenuItem(
                  value: 'missed',
                  child: ListTile(
                      leading: Icon(Icons.event_busy), title: Text('I missed this'), contentPadding: EdgeInsets.zero),
                ),
              ],
            )
          : null,
      onTap: () => _open(a),
    );
  }
}

class _NewItem {
  const _NewItem(this.title, this.kind, this.dueAt, this.minutes);

  final String title;
  final ActivityKind kind;
  final DateTime? dueAt;
  final int minutes;
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog();

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _title = TextEditingController();
  final _minutes = TextEditingController(text: '90');
  ActivityKind _kind = ActivityKind.lab;
  DateTime? _due;

  static const _kinds = [
    ActivityKind.lab,
    ActivityKind.assignment,
    ActivityKind.exam,
    ActivityKind.lesson,
    ActivityKind.project,
  ];

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final picked = await pickDateTime(context, initial: _due);
    if (picked != null && mounted) setState(() => _due = picked);
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final minutes = int.tryParse(_minutes.text.trim()) ?? 60;
    Navigator.pop(context, _NewItem(title, _kind, _due, minutes <= 0 ? 60 : minutes));
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    return AlertDialog(
      title: const Text('Add item'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'Lab 4: SQL joins'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ActivityKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final k in _kinds)
                  DropdownMenuItem(
                    value: k,
                    child: Row(
                      children: [
                        Icon(kindIcon(k), size: 18, color: kindColor(context, k.db)),
                        const SizedBox(width: 10),
                        Text(k.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (k) => setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes it takes', suffixText: 'min'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDue,
              icon: const Icon(Icons.event),
              label: Text(due == null ? 'Pick a due date' : 'Due ${fmtDateTime(due)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
