import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../database/db_helper.dart';
import '../../models/goal_model.dart';
import '../../models/task_model.dart';

/// Read-only history of every goal the user has marked as achieved
/// (see DBHelper.markGoalAchieved) — the payoff for building
/// GoalAchievedScreen in the first place. Without this screen, an
/// achieved goal would flash its celebration once and then be
/// functionally indistinguishable from a deleted one, which defeats
/// the point of tracking the difference at all.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  bool _loading = true;
  List<_AchievedGoalEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final goals = await DBHelper.instance.getAchievedGoals();
    final entries = <_AchievedGoalEntry>[];
    for (final goal in goals) {
      final stats = await DBHelper.instance.getOverallStats(goal.id);
      final streakStats = await DBHelper.instance.getStreakStats(goal.id);
      entries.add(_AchievedGoalEntry(
        goal: goal,
        stats: stats,
        longestStreak: streakStats.longest,
      ));
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Achievements')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) => _buildCard(_entries[i]),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No goals achieved yet',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'When you finish a goal, mark it as achieved from its menu '
              'and it\'ll show up here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(_AchievedGoalEntry entry) {
    final goal = entry.goal;
    final stats = entry.stats;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.emoji_events_rounded,
                    color: AppColors.warning, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.title, style: AppTextStyles.h3),
                    if (goal.achievedAt != null)
                      Text(
                        'Achieved ${_formatDate(goal.achievedAt!)}',
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('${stats.totalCompleted}', 'Tasks'),
              _stat('${entry.longestStreak}', 'Best Streak'),
              _stat('${(stats.completionRate * 100).round()}%', 'Completion'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _AchievedGoalEntry {
  final Goal goal;
  final GoalOverallStats stats;
  final int longestStreak;

  const _AchievedGoalEntry({
    required this.goal,
    required this.stats,
    required this.longestStreak,
  });
}
