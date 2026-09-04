import 'package:flutter/material.dart';

import '../../models/goal_model.dart';
import '../../models/goal_phase_model.dart';
import '../../models/schedule_model.dart';
import '../../database/db_helper.dart';
import '../../utils/id_generator.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/primary_button.dart';
import '../../services/insights_service.dart';
import '../../utils/schedule_conflict.dart';
import '../main_nav_screen.dart';
import 'create_phase_screen.dart';

 List<String> _kWeekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Lets the user build their own multi-stage plan for a goal —
/// "Phase 1: Learn the Skill" -> "Phase 2: Build Portfolio" -> etc.
///
/// Aspire Lock never invents phases or their tasks; this screen is
/// purely a structure/container the user fills in themselves. Only
/// one phase is ever `active` at a time — its tasks are what actually
/// generate daily (see [DBHelper.getGenerationRulesForGoal]); other
/// phases just sit there until their turn.
///
/// This is the *only* planning step for a new goal — there is no
/// separate AI-drafted schedule anymore. When [isOnboarding] is true
/// (freshly created goal), a "Continue" bar lets the user move on to
/// picking which apps to lock once they've set up at least one phase.
/// Opened later from the Home screen's goal menu, [isOnboarding] is
/// false and the screen is just a plain management view.
class PhaseListScreen extends StatefulWidget {
  final Goal goal;
  final bool isOnboarding;
   PhaseListScreen({
    super.key,
    required this.goal,
    this.isOnboarding = false,
  });

  @override
  State<PhaseListScreen> createState() => _PhaseListScreenState();
}

class _PhaseListScreenState extends State<PhaseListScreen> {
  List<GoalPhase> _phases = [];
  Map<String, List<ScheduleRule>> _tasksByPhase = {};
  bool _loading = true;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final phases = await DBHelper.instance.getPhasesForGoal(widget.goal.id);
    final rules = await DBHelper.instance.getActiveRulesForGoal(widget.goal.id);

    final grouped = <String, List<ScheduleRule>>{};
    for (final rule in rules) {
      if (rule.phaseId == null) continue;
      grouped.putIfAbsent(rule.phaseId!, () => []).add(rule);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.time.compareTo(b.time));
    }

    if (!mounted) return;
    setState(() {
      _phases = phases;
      _tasksByPhase = grouped;
      _loading = false;
      // Keep the active phase expanded by default so its tasks are
      // visible without an extra tap.
      final active = phases.where((p) => p.status == PhaseStatus.active);
      if (active.isNotEmpty) _expanded.add(active.first.id);
    });
  }

  Future<void> _addPhase() async {
    final input = await CreatePhaseSheet.show(context);
    if (input == null) return;

    final isFirstPhase = _phases.isEmpty;
    final phase = GoalPhase(
      id: generateId(),
      goalId: widget.goal.id,
      title: input.title,
      orderIndex: _phases.length + 1,
      durationDays: input.durationDays,
    );
    await DBHelper.instance.insertPhase(phase);

    // The very first phase a user adds becomes active immediately so
    // there's always something for task generation to work from —
    // later phases wait their turn (see completePhaseAndActivateNext).
    if (isFirstPhase) {
      await DBHelper.instance.activateFirstPhase(widget.goal.id);
    }

    await _load();
  }

  Future<void> _addTask(GoalPhase phase) async {
    final rule = await _AddPhaseTaskSheet.show(context, widget.goal.id, phase.id);
    if (rule == null) return;
    await DBHelper.instance.insertScheduleRule(rule);
    await _load();
  }

  Future<void> _completePhase(GoalPhase phase) async {
    final isLast = phase.orderIndex == _phases.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text('Mark phase complete?'),
        content: Text(
          isLast
              ? '"${phase.title}" is your last phase — marking it complete '
                  'won\'t activate a new one.'
              : '"${phase.title}" will be marked complete and the next '
                  'phase will become active. Its own tasks will start '
                  'generating daily instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:  Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:  Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    await DBHelper.instance.completePhaseAndActivateNext(phase);
    await _load();
  }

  Future<void> _editPhase(GoalPhase phase) async {
    final input = await CreatePhaseSheet.show(context, existing: phase);
    if (input == null) return;

    // Built directly (not via copyWith) so switching to "Ongoing" can
    // actually clear durationDays to null — copyWith's `??` pattern
    // can't distinguish "leave unchanged" from "set to null".
    final updated = GoalPhase(
      id: phase.id,
      goalId: phase.goalId,
      title: input.title,
      orderIndex: phase.orderIndex,
      durationDays: input.durationDays,
      status: phase.status,
      createdAt: phase.createdAt,
      startedAt: phase.startedAt,
    );
    await DBHelper.instance.updatePhase(updated);
    await _load();
  }

  Future<void> _deletePhase(GoalPhase phase) async {
    if (phase.status == PhaseStatus.active) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
          content: Text('Complete the active phase before deleting it.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text('Delete phase?'),
        content: Text(
          'This removes "${phase.title}" and its tasks won\'t generate '
          'anymore. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:  Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child:  Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DBHelper.instance.deletePhase(phase.id);
    await _load();
  }

  /// Onboarding's final step now that app-locking has been removed —
  /// once phases exist, there's nothing left to configure, so this
  /// goes straight into the main app shell.
  Future<void> _continue() async {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavScreen()),
      (route) => false,
    );
  }

  /// Always gives the user a way out of this screen, regardless of how
  /// they arrived here. Normally there's a route underneath (Home, or
  /// the category picker) so a simple pop is enough — but this screen
  /// can also be reached via a `pushReplacement` (e.g. the "you already
  /// have this goal" dialog), so we fall back to the main app shell
  /// instead of leaving the user stuck with no way back.
  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.goal.title} · Phases'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: _goBack,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPhase,
        backgroundColor: AppColors.primary,
        icon:  Icon(Icons.add, color: Colors.white),
        label:  Text('Add Phase', style: TextStyle(color: Colors.white)),
      ),
      bottomNavigationBar: widget.isOnboarding && !_loading
          ? SafeArea(
              child: Padding(
                padding:  EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: PrimaryButton(
                  label: 'Continue',
                  onPressed: _phases.isEmpty ? null : _continue,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ?  Center(child: CircularProgressIndicator())
            : _phases.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding:  EdgeInsets.fromLTRB(20, 12, 20, 100),
                    itemCount: _phases.length,
                    separatorBuilder: (_, __) =>  SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final phase = _phases[index];
                      return _PhaseCard(
                        phase: phase,
                        tasks: _tasksByPhase[phase.id] ??  [],
                        expanded: _expanded.contains(phase.id),
                        onToggleExpand: () => setState(() {
                          if (!_expanded.add(phase.id)) {
                            _expanded.remove(phase.id);
                          }
                        }),
                        onAddTask: () => _addTask(phase),
                        onComplete: phase.status == PhaseStatus.active
                            ? () => _completePhase(phase)
                            : null,
                        onEdit: () => _editPhase(phase),
                        onDelete: () => _deletePhase(phase),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding:  EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Icon(Icons.stacked_bar_chart_rounded,
                size: 42, color: AppColors.textMuted),
             SizedBox(height: 16),
             Text('Build your own plan', style: AppTextStyles.h2),
             SizedBox(height: 8),
            Text(
              'Break "${widget.goal.title}" into phases — e.g. "Learn the '
              'Skill" then "Build Portfolio" then "Pitch Clients". Add '
              'daily tasks under each one; only the active phase\'s '
              'tasks generate day to day.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
             SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _addPhase,
              icon:  Icon(Icons.add),
              label:  Text('Add Your First Phase'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  final GoalPhase phase;
  final List<ScheduleRule> tasks;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onAddTask;
  final VoidCallback? onComplete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

   _PhaseCard({
    required this.phase,
    required this.tasks,
    required this.expanded,
    required this.onToggleExpand,
    required this.onAddTask,
    required this.onComplete,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _statusColor {
    switch (phase.status) {
      case PhaseStatus.active:
        return AppColors.pulse;
      case PhaseStatus.completed:
        return AppColors.success;
      case PhaseStatus.upcoming:
        return AppColors.textMuted;
    }
  }

  String get _statusLabel {
    switch (phase.status) {
      case PhaseStatus.active:
        return 'Active';
      case PhaseStatus.completed:
        return 'Completed';
      case PhaseStatus.upcoming:
        return 'Upcoming';
    }
  }

  String get _durationLabel {
    if (phase.durationDays == null) return 'Ongoing';
    if (phase.status == PhaseStatus.active && phase.startedAt != null) {
      final elapsed = DateTime.now().difference(phase.startedAt!).inDays;
      final remaining = phase.durationDays! - elapsed;
      if (remaining > 0) return '$remaining of ${phase.durationDays} days left';
      return 'Duration up';
    }
    return '${phase.durationDays} days';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding:  EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${phase.orderIndex}',
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                   SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(phase.title, style: AppTextStyles.h3),
                         SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding:  EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _statusLabel,
                                style: TextStyle(
                                  color: _statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                             SizedBox(width: 8),
                            Text(_durationLabel, style: AppTextStyles.caption),
                            Text(
                              '  ·  ${tasks.length} task${tasks.length == 1 ? '' : 's'}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon:  Icon(Icons.more_vert_rounded,
                        color: AppColors.textMuted),
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) =>  [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: AppColors.danger)),
                      ),
                    ],
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
             Divider(height: 1),
            Padding(
              padding:  EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tasks.isEmpty)
                     Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'No daily tasks yet for this phase.',
                        style: AppTextStyles.bodyMuted,
                      ),
                    )
                  else
                    ...tasks.map((t) => Padding(
                          padding:  EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                               Icon(Icons.circle,
                                  size: 5, color: AppColors.textMuted),
                               SizedBox(width: 8),
                              Expanded(
                                child: Text(t.taskTitle, style: AppTextStyles.body),
                              ),
                              Text(t.time, style: AppTextStyles.bodyMuted),
                            ],
                          ),
                        )),
                   SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onAddTask,
                        icon:  Icon(Icons.add, size: 18),
                        label:  Text('Add Task'),
                      ),
                       Spacer(),
                      if (onComplete != null)
                        TextButton(
                          onPressed: onComplete,
                          child:  Text('Mark Complete →'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet form for adding a new daily task (recurring
/// [ScheduleRule]) under a specific phase. Mirrors the "Edit Schedule"
/// form in `manage_schedule_screen.dart`, but creates a new rule
/// instead of editing one, and stamps it with [phaseId] so it only
/// generates tasks while that phase is active.
class _AddPhaseTaskSheet extends StatefulWidget {
  final String goalId;
  final String phaseId;
   _AddPhaseTaskSheet({required this.goalId, required this.phaseId});

  static Future<ScheduleRule?> show(
      BuildContext context, String goalId, String phaseId) {
    return showModalBottomSheet<ScheduleRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPhaseTaskSheet(goalId: goalId, phaseId: phaseId),
    );
  }

  @override
  State<_AddPhaseTaskSheet> createState() => _AddPhaseTaskSheetState();
}

class _AddPhaseTaskSheetState extends State<_AddPhaseTaskSheet> {
  final TextEditingController _titleController = TextEditingController();
  TimeOfDay _time =  TimeOfDay(hour: 9, minute: 0);
  int _durationMinutes = 30;
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  bool _requiresPhotoProof = false;

  // Best hour for this goal based on its own local completion
  // history (see InsightsService — purely on-device, no external
  // API). Null until loaded, or if there isn't enough history yet.
  TimeOfDay? _suggestedTime;

  // Set when the last save attempt clashed with another task that's
  // already active at the same time on an overlapping day.
  String? _conflictError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    InsightsService.instance.suggestedTimeOfDay(widget.goalId).then((time) {
      if (mounted) setState(() => _suggestedTime = time);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() {
        _time = picked;
        _conflictError = null;
      });
    }
  }

  void _applySuggestedTime() {
    if (_suggestedTime != null) {
      setState(() {
        _time = _suggestedTime!;
        _conflictError = null;
      });
    }
  }

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty &&
      _weekdays.isNotEmpty &&
      !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    final timeStr =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    final weekdays = _weekdays.toList()..sort();

    setState(() {
      _saving = true;
      _conflictError = null;
    });

    // Only rules that could actually fire at the same time as this one
    // count as a real conflict — see getAllActiveGenerationRules.
    final existingRules = await DBHelper.instance.getAllActiveGenerationRules();
    final conflict = ScheduleConflict.findConflict(
      time: timeStr,
      durationMinutes: _durationMinutes,
      weekdays: weekdays,
      existingRules: existingRules,
    );

    if (conflict != null) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _conflictError =
            '"${conflict.taskTitle}" is already scheduled at ${conflict.time} '
            'and overlaps this time. Pick a different time.';
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      ScheduleRule(
        id: generateId(),
        goalId: widget.goalId,
        phaseId: widget.phaseId,
        taskTitle: _titleController.text.trim(),
        time: timeStr,
        durationMinutes: _durationMinutes,
        activeWeekdays: weekdays,
        requiresPhotoProof: _requiresPhotoProof,
        isActive: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration:  BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding:  EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text('Add Task', style: AppTextStyles.h2),
               SizedBox(height: 4),
               Text(
                'Repeats daily on the days you pick, while this phase '
                'is active.',
                style: AppTextStyles.bodyMuted,
              ),
               SizedBox(height: 18),
              TextField(
                controller: _titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration:  InputDecoration(
                  labelText: 'Task title',
                  hintText: 'e.g. Practice Figma for 1 hour',
                ),
                onChanged: (_) => setState(() {}),
              ),
               SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration:  InputDecoration(labelText: 'Time'),
                        child: Text(_time.format(context)),
                      ),
                    ),
                  ),
                   SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _durationMinutes,
                      decoration:  InputDecoration(labelText: 'Duration'),
                      items:  [15, 30, 45, 60, 90, 120]
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text('$m min'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _durationMinutes = v);
                      },
                    ),
                  ),
                ],
              ),
              if (_conflictError != null) ...[
                 SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Icon(Icons.error_outline_rounded,
                        size: 16, color: AppColors.danger),
                     SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _conflictError!,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ],
              if (_suggestedTime != null &&
                  (_suggestedTime!.hour != _time.hour ||
                      _suggestedTime!.minute != _time.minute)) ...[
                 SizedBox(height: 8),
                InkWell(
                  onTap: _applySuggestedTime,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                       Icon(Icons.insights_rounded,
                          size: 15, color: AppColors.success),
                       SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "You're usually most consistent around "
                          '${_suggestedTime!.format(context)} — tap to use it',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
               SizedBox(height: 16),
               Text('Repeat on', style: AppTextStyles.bodyMuted),
               SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(7, (i) {
                  final day = i + 1; // 1 = Monday ... 7 = Sunday
                  final selected = _weekdays.contains(day);
                  return FilterChip(
                    label: Text(_kWeekdayShort[i]),
                    selected: selected,
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          _weekdays.add(day);
                        } else {
                          _weekdays.remove(day);
                        }
                        _conflictError = null;
                      });
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: AppColors.surface,
                  );
                }),
              ),
               SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title:  Text('Require photo proof', style: AppTextStyles.body),
                value: _requiresPhotoProof,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _requiresPhotoProof = v),
              ),
               SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSave ? _save : null,
                  child: _saving
                      ?  SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      :  Text('Add Task'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
