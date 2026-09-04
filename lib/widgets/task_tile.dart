import 'dart:io';

import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback? onTap;
  final Widget? trailing;

   TaskTile({
    super.key,
    required this.task,
    this.onTap,
    this.trailing,
  });

  Color _statusColor() {
    switch (task.status) {
      case TaskStatus.completed:
        return AppColors.success;
      case TaskStatus.missed:
        return AppColors.danger;
      case TaskStatus.inProgress:
        return AppColors.warning;
      case TaskStatus.pending:
        return AppColors.textMuted;
    }
  }

  IconData _statusIcon() {
    switch (task.status) {
      case TaskStatus.completed:
        return Icons.check_circle_rounded;
      case TaskStatus.missed:
        return Icons.cancel_rounded;
      case TaskStatus.inProgress:
        return Icons.play_circle_fill_rounded;
      case TaskStatus.pending:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  /// Completed tasks that have a saved proof photo show a small round
  /// thumbnail instead of the plain status icon, as a visual cue that
  /// tapping the tile opens that photo.
  bool get _hasViewableProof =>
      task.status == TaskStatus.completed &&
      task.proofImagePath != null &&
      task.proofImagePath!.isNotEmpty;

  Widget _leadingIcon() {
    if (_hasViewableProof) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.divider,
        backgroundImage: FileImage(File(task.proofImagePath!)),
      );
    }
    return Icon(_statusIcon(), color: _statusColor(), size: 28);
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == TaskStatus.completed;
    final isActionable = task.status != TaskStatus.completed &&
        task.status != TaskStatus.missed;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding:  EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _leadingIcon(),
               SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: AppTextStyles.h3.copyWith(
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                        color: isCompleted
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                     SizedBox(height: 4),
                    Row(
                      children: [
                        Text(task.scheduledTime,
                            style: AppTextStyles.mono(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                        Text('  ·  ${task.durationMinutes} min',
                            style: AppTextStyles.bodyMuted),
                        if (task.requiresPhotoProof) ...[
                           SizedBox(width: 6),
                           Icon(Icons.camera_alt_outlined,
                              size: 13, color: AppColors.textMuted),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!
              else if (isActionable)
                 Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted)
              else if (_hasViewableProof)
                 Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
