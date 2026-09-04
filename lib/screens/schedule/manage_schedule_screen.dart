import 'package:flutter/material.dart';

import '../../models/goal_model.dart';
import '../../models/schedule_model.dart';
import '../../database/db_helper.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../utils/schedule_conflict.dart';

 List<String> _kWeekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Lists a goal's active recurring [ScheduleRule]s and lets the user
/// edit (time/duration/weekdays/photo-proof) or delete each one.
///
/// Rules are normally created per-phase from `phase_list_screen.dart`
/// (each rule is stamped with the phase it belongs to). This screen is
/// a flat view across all of a goal's rules, regardless of phase,
/// for when the user just wants to review or tweak one. Editing/
/// deleting a rule only affects tasks generated *after* the change;
/// already-generated task rows for today/earlier are untouched (edit
/// those individually from the home screen instead).
class ManageScheduleScreen extends StatefulWidget {
  final Goal goal;
   ManageScheduleScreen({super.key, required this.goal});

  @override
  State<ManageScheduleScreen> createState() => _ManageScheduleScreenState();
}

class _ManageScheduleScreenState extends State<ManageScheduleScreen> {
  List<ScheduleRule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await DBHelper.instance.getActiveRulesForGoal(widget.goal.id);
    rules.sort((a, b) => a.time.compareTo(b.time));
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _loading = false;
    });
  }

  Future<void> _editRule(ScheduleRule rule) async {
    final updated = await showModalBottomSheet<ScheduleRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditRuleSheet(rule: rule),
    );
    if (updated == null) return;

    await DBHelper.instance.updateScheduleRule(updated);
    await _load();
  }

  Future<void> _deleteRule(ScheduleRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text('Delete schedule?'),
        content: Text(
          'This stops "${rule.taskTitle}" from generating new daily tasks. '
          'Tasks already created for today or earlier stay as they are.',
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

    await DBHelper.instance.deactivateScheduleRule(rule.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title:  Text('Manage Schedule')),
      body: SafeArea(
        child: _loading
            ?  Center(child: CircularProgressIndicator())
            : _rules.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding:  EdgeInsets.fromLTRB(24, 12, 24, 24),
                    itemCount: _rules.length,
                    separatorBuilder: (_, __) =>  SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final rule = _rules[index];
                      return _RuleCard(
                        rule: rule,
                        onEdit: () => _editRule(rule),
                        onDelete: () => _deleteRule(rule),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding:  EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Icon(Icons.event_busy_outlined,
                size: 40, color: AppColors.textMuted),
             SizedBox(height: 14),
             Text('No recurring schedule rules', style: AppTextStyles.h3),
             SizedBox(height: 6),
             Text(
              'This goal has no active recurring tasks set up.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final ScheduleRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

   _RuleCard({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  String _weekdaysLabel() {
    if (rule.activeWeekdays.length == 7) return 'Every day';
    final sorted = [...rule.activeWeekdays]..sort();
    return sorted.map((d) => _kWeekdayShort[d - 1]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding:  EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.taskTitle, style: AppTextStyles.h3),
                   SizedBox(height: 4),
                  Row(
                    children: [
                      Text(rule.time, style: AppTextStyles.bodyMuted),
                      Text('  ·  ${rule.durationMinutes} min',
                          style: AppTextStyles.bodyMuted),
                      if (rule.requiresPhotoProof) ...[
                         SizedBox(width: 6),
                         Icon(Icons.camera_alt_outlined,
                            size: 13, color: AppColors.textMuted),
                      ],
                    ],
                  ),
                   SizedBox(height: 3),
                  Text(_weekdaysLabel(), style: AppTextStyles.caption),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon:  Icon(Icons.more_vert_rounded,
                  color: AppColors.textMuted),
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) =>  [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet form for editing a rule's title, time, duration,
/// active weekdays, and photo-proof requirement. Pops with the
/// updated [ScheduleRule], or null if cancelled.
class _EditRuleSheet extends StatefulWidget {
  final ScheduleRule rule;
   _EditRuleSheet({required this.rule});

  @override
  State<_EditRuleSheet> createState() => _EditRuleSheetState();
}

class _EditRuleSheetState extends State<_EditRuleSheet> {
  late final TextEditingController _titleController;
  late TimeOfDay _time;
  late int _durationMinutes;
  late Set<int> _weekdays;
  late bool _requiresPhotoProof;

  String? _conflictError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.rule.taskTitle);
    final parts = widget.rule.time.split(':');
    _time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    _durationMinutes = widget.rule.durationMinutes;
    _weekdays = widget.rule.activeWeekdays.toSet();
    _requiresPhotoProof = widget.rule.requiresPhotoProof;
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

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _weekdays.isEmpty || _saving) return;

    final timeStr =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    final weekdays = _weekdays.toList()..sort();

    setState(() {
      _saving = true;
      _conflictError = null;
    });

    final existingRules = await DBHelper.instance.getAllActiveGenerationRules();
    final conflict = ScheduleConflict.findConflict(
      time: timeStr,
      durationMinutes: _durationMinutes,
      weekdays: weekdays,
      existingRules: existingRules,
      excludeRuleId: widget.rule.id,
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
        id: widget.rule.id,
        goalId: widget.rule.goalId,
        taskTitle: title,
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
    final canSave = _titleController.text.trim().isNotEmpty && _weekdays.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
               Text('Edit Schedule', style: AppTextStyles.h2),
               SizedBox(height: 18),
              TextField(
                controller: _titleController,
                decoration:  InputDecoration(labelText: 'Task title'),
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
                  onPressed: canSave && !_saving ? _save : null,
                  child: _saving
                      ?  SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      :  Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
