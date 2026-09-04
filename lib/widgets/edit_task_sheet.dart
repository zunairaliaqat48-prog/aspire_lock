import 'package:flutter/material.dart';

import '../models/task_model.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// Result of editing a task in [EditTaskSheet].
class EditedTaskDetails {
  final String title;
  final String scheduledTime; // "HH:mm"
  final int durationMinutes;
  final bool requiresPhotoProof;

   EditedTaskDetails({
    required this.title,
    required this.scheduledTime,
    required this.durationMinutes,
    required this.requiresPhotoProof,
  });
}

/// Bottom sheet form for editing a single task occurrence (today's
/// task, not the recurring rule it came from — see
/// `ManageScheduleScreen` for editing the recurring rule itself).
/// Pops with [EditedTaskDetails], or null if cancelled.
class EditTaskSheet extends StatefulWidget {
  final Task task;
   EditTaskSheet({super.key, required this.task});

  static Future<EditedTaskDetails?> show(BuildContext context, Task task) {
    return showModalBottomSheet<EditedTaskDetails>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditTaskSheet(task: task),
    );
  }

  @override
  State<EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends State<EditTaskSheet> {
  late final TextEditingController _titleController;
  late TimeOfDay _time;
  late int _durationMinutes;
  late bool _requiresPhotoProof;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    final parts = widget.task.scheduledTime.split(':');
    _time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    _durationMinutes = widget.task.durationMinutes;
    _requiresPhotoProof = widget.task.requiresPhotoProof;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final timeStr =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

    Navigator.pop(
      context,
      EditedTaskDetails(
        title: title,
        scheduledTime: timeStr,
        durationMinutes: _durationMinutes,
        requiresPhotoProof: _requiresPhotoProof,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _titleController.text.trim().isNotEmpty;

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
               Text('Edit Task', style: AppTextStyles.h2),
               SizedBox(height: 4),
               Text(
                'Changes apply to today\'s task only.',
                style: AppTextStyles.bodyMuted,
              ),
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
                  onPressed: canSave ? _save : null,
                  child:  Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
