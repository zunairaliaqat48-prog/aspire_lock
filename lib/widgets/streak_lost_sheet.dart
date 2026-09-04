import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import 'primary_button.dart';

/// Shown once, right when HomeScreen notices a goal's streak dropped
/// since it was last shown (see HomeScreen._checkForBrokenStreak and
/// Goal.lastSeenStreak) — the "felt" counterpart to the streak badge's
/// color-escalation: breaking a streak should register as a distinct
/// moment, not just quietly become a smaller number next time the app
/// happens to open.
class StreakLostSheet extends StatelessWidget {
  final String goalTitle;
  final int lostStreak;

  const StreakLostSheet({
    super.key,
    required this.goalTitle,
    required this.lostStreak,
  });

  static Future<void> show(
    BuildContext context, {
    required String goalTitle,
    required int lostStreak,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => StreakLostSheet(goalTitle: goalTitle, lostStreak: lostStreak),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_fire_department_outlined,
              color: AppColors.danger,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your $lostStreak-day streak broke',
            textAlign: TextAlign.center,
            style: AppTextStyles.h2,
          ),
          const SizedBox(height: 8),
          Text(
            '$goalTitle went a day without a completed task. That streak '
            'is gone — but a new one starts the moment you finish your '
            'next task today.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted.copyWith(height: 1.45),
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Start a new streak',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
