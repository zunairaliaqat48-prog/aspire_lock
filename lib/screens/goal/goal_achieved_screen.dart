import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../database/db_helper.dart';
import '../../models/goal_model.dart';
import '../../models/task_model.dart';
import '../main_nav_screen.dart';

/// The "finish line" moment for a goal — shown once, right after the
/// user marks a goal as achieved (see HomeScreen._markGoalAchieved).
///
/// Deliberately NOT auto-dismissing like TaskCelebrationScreen: a
/// single completed task is a small, frequent reward that should get
/// out of the way fast; finishing an entire goal — which for this app
/// might represent weeks of locked-app enforcement — deserves a
/// moment the user actually has to close themselves, with the final
/// numbers laid out plainly so it feels earned rather than glossed
/// over.
class GoalAchievedScreen extends StatefulWidget {
  final Goal goal;

  const GoalAchievedScreen({super.key, required this.goal});

  @override
  State<GoalAchievedScreen> createState() => _GoalAchievedScreenState();
}

class _GoalAchievedScreenState extends State<GoalAchievedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  GoalOverallStats? _stats;
  int _longestStreak = 0;
  int _daysActive = 0;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _controller.forward();

    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await DBHelper.instance.getOverallStats(widget.goal.id);
    final streakStats = await DBHelper.instance.getStreakStats(widget.goal.id);
    final days = DateTime.now().difference(widget.goal.createdAt).inDays;
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _longestStreak = streakStats.longest;
      _daysActive = days < 1 ? 1 : days;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  ScaleTransition(
                    scale: _scale,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.emoji_events_rounded,
                        size: 70,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text('Goal Achieved!', style: AppTextStyles.h1),
                  const SizedBox(height: 8),
                  Text(
                    widget.goal.title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 32),
                  if (_stats != null) _buildStatsRow(),
                  const Spacer(flex: 2),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _done,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = _stats!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statColumn('${stats.totalCompleted}', 'Tasks Done'),
        _statColumn('$_longestStreak', 'Best Streak'),
        _statColumn('$_daysActive', 'Days'),
      ],
    );
  }

  Widget _statColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}
