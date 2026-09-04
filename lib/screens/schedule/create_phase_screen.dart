import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../models/goal_phase_model.dart';

/// What the user entered for a phase — [CreatePhaseSheet] hands this
/// back to the caller, which is responsible either for turning it into
/// a new [GoalPhase] (assigning id/goalId/orderIndex) or applying it
/// as an edit to an existing one.
class NewPhaseInput {
  final String title;

  /// Null means "ongoing" — no fixed end, keeps running until the user
  /// marks it complete manually.
  final int? durationDays;

   NewPhaseInput({required this.title, this.durationDays});
}

/// Bottom sheet form for adding or editing a user-defined [GoalPhase].
/// Aspire Lock never invents phase content or duration — this sheet
/// only collects what the user types; it doesn't suggest or generate
/// anything. Pops with a [NewPhaseInput], or null if cancelled.
///
/// Pass [existing] to open it pre-filled for editing that phase's
/// title/duration instead of creating a new one — the caller decides
/// what to do with the result either way.
class CreatePhaseSheet extends StatefulWidget {
  final GoalPhase? existing;

   CreatePhaseSheet({super.key, this.existing});

  static Future<NewPhaseInput?> show(BuildContext context, {GoalPhase? existing}) {
    return showModalBottomSheet<NewPhaseInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreatePhaseSheet(existing: existing),
    );
  }

  @override
  State<CreatePhaseSheet> createState() => _CreatePhaseSheetState();
}

class _CreatePhaseSheetState extends State<CreatePhaseSheet> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _daysController = TextEditingController(
    text: widget.existing?.durationDays?.toString() ?? '',
  );
  late bool _isOngoing =
      widget.existing != null && widget.existing!.durationDays == null;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _titleController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_titleController.text.trim().isEmpty) return false;
    if (_isOngoing) return true;
    final days = int.tryParse(_daysController.text.trim());
    return days != null && days > 0;
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      NewPhaseInput(
        title: _titleController.text.trim(),
        durationDays:
            _isOngoing ? null : int.parse(_daysController.text.trim()),
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
               Text(_isEditing ? 'Edit Phase' : 'Add a Phase',
                  style: AppTextStyles.h2),
               SizedBox(height: 4),
               Text(
                _isEditing
                    ? 'Update the name or duration — its tasks stay the same.'
                    : 'A stage of your goal — e.g. "Learn the Skill" or '
                        '"Build Portfolio". You\'ll add its daily tasks next.',
                style: AppTextStyles.bodyMuted,
              ),
               SizedBox(height: 18),
              TextField(
                controller: _titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration:  InputDecoration(labelText: 'Phase name'),
                onChanged: (_) => setState(() {}),
              ),
               SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _daysController,
                      enabled: !_isOngoing,
                      keyboardType: TextInputType.number,
                      decoration:  InputDecoration(
                        labelText: 'Duration (days)',
                        hintText: 'e.g. 21',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
               SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title:  Text('Ongoing (no fixed end)', style: AppTextStyles.body),
                subtitle:  Text(
                  'Runs until you mark it complete yourself.',
                  style: AppTextStyles.caption,
                ),
                value: _isOngoing,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _isOngoing = v),
              ),
               SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(_isEditing ? 'Save Changes' : 'Add Phase'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
