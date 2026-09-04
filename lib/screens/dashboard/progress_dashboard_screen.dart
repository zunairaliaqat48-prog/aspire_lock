import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/goal_model.dart';
import '../../models/task_model.dart';
import '../../models/task_snooze_model.dart';
import '../../database/db_helper.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/streak_chart.dart';
import '../../widgets/completion_heatmap.dart';
import '../../services/insights_service.dart';
import '../../services/streak_freeze_service.dart';
import '../../widgets/streak_freeze_sheet.dart';
import '../task/proof_photo_viewer_screen.dart';

class ProgressDashboardScreen extends StatefulWidget {
  final Goal goal;
   ProgressDashboardScreen({super.key, required this.goal});

  @override
  State<ProgressDashboardScreen> createState() => _ProgressDashboardScreenState();
}

class _ProgressDashboardScreenState extends State<ProgressDashboardScreen> {
  List<int> _weeklyCounts = List.filled(7, 0);
  int _streak = 0;
  int _longestStreak = 0;
  bool _loading = true;
  List<Task> _proofTasks = [];
  GoalOverallStats? _overallStats;
  Map<String, int> _dailyCounts = {};
  List<TaskSnoozeLog> _recentSnoozes = [];
  ProofComplianceStats? _proofComplianceStats;
  String? _bestHoursMessage;
  int _freezesRemaining = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));

    final counts = <int>[];
    for (int i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final count = await DBHelper.instance.countCompletedTasksBetween(
        widget.goal.id,
        day,
        day,
      );
      counts.add(count);
    }

    final streakStats = await DBHelper.instance.getStreakStats(widget.goal.id);

    final proofTasks =
        await DBHelper.instance.getRecentProofTasksForGoal(widget.goal.id);

    final overallStats =
        await DBHelper.instance.getOverallStats(widget.goal.id);
    final dailyCounts =
        await DBHelper.instance.getDailyCompletionCounts(widget.goal.id);
    final recentSnoozes = await DBHelper.instance
        .getRecentSnoozesForGoal(widget.goal.id, limit: 5);
    final proofComplianceStats =
        await DBHelper.instance.getProofComplianceStats(widget.goal.id);
    final bestHoursMessage =
        await InsightsService.instance.getBestHoursMessage(widget.goal.id);
    final freezesRemaining =
        await StreakFreezeService.instance.remainingThisMonth(widget.goal.id);

    if (!mounted) return;
    setState(() {
      _weeklyCounts = counts;
      _streak = streakStats.current;
      _longestStreak = streakStats.longest;
      _proofTasks = proofTasks;
      _overallStats = overallStats;
      _dailyCounts = dailyCounts;
      _recentSnoozes = recentSnoozes;
      _proofComplianceStats = proofComplianceStats;
      _bestHoursMessage = bestHoursMessage;
      _freezesRemaining = freezesRemaining;
      _loading = false;
    });
  }

  Future<void> _openStreakFreeze() async {
    final applied = await StreakFreezeSheet.show(context, widget.goal.id);
    if (applied) await _loadStats();
  }

  String _aiNote() {
    final totalThisWeek = _weeklyCounts.reduce((a, b) => a + b);
    if (totalThisWeek == 0) {
      return 'No tasks completed yet this week — try starting with just one '
          'small task tomorrow to rebuild momentum.';
    }
    if (_streak >= 5) {
      return 'Strong consistency this week! Consider slightly increasing your '
          'task difficulty or duration next week.';
    }
    if (totalThisWeek < 3) {
      return 'A few tasks were missed this week. Consider moving your alarm '
          'times earlier, or reducing task duration to make them easier to start.';
    }
    return 'Good progress — keep the same schedule next week and focus on '
        'not breaking your streak.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title:  Text('Your Progress')),
      body: _loading
          ?  Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding:  EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.goal.title, style: AppTextStyles.h2),
                       SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding:  EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child:  Icon(Icons.local_fire_department,
                                  color: AppColors.accent, size: 28),
                            ),
                             SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                   Text('Current Streak',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 13)),
                                   SizedBox(height: 4),
                                  Text.rich(
                                    TextSpan(
                                      style: AppTextStyles.mono(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      children: [
                                        TextSpan(text: '$_streak'),
                                        TextSpan(
                                          text: ' days',
                                          style: GoogleFonts.sora(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Only worth showing once the user has a
                            // best streak that's actually different
                            // from (i.e. longer in the past than)
                            // their current one — otherwise it's just
                            // showing the same number twice.
                            if (_longestStreak > _streak)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                   Text('Best',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 13)),
                                   SizedBox(height: 4),
                                  Text(
                                    '$_longestStreak',
                                    style: AppTextStyles.mono(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                       SizedBox(height: 20),
                      _buildStreakFreezeCard(),
                       SizedBox(height: 28),
                       Text('Overview', style: AppTextStyles.h3),
                       SizedBox(height: 14),
                      _buildOverviewGrid(),
                      if (_proofComplianceStats != null &&
                          _proofComplianceStats!.resolved > 0) ...[
                         SizedBox(height: 14),
                        _buildProofComplianceCard(),
                      ],
                       SizedBox(height: 28),
                       Text('This Week', style: AppTextStyles.h3),
                       SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding:  EdgeInsets.all(18),
                          child: StreakChart(
                            values: _weeklyCounts,
                            todayIndex: DateTime.now().weekday - 1,
                          ),
                        ),
                      ),
                       SizedBox(height: 24),
                      Container(
                        padding:  EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Icon(Icons.auto_awesome,
                                color: AppColors.accent, size: 20),
                             SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _aiNote(),
                                style: AppTextStyles.body.copyWith(height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_bestHoursMessage != null) ...[
                         SizedBox(height: 14),
                        Container(
                          padding:  EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               Icon(Icons.insights_rounded,
                                  color: AppColors.success, size: 20),
                               SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _bestHoursMessage!,
                                  style: AppTextStyles.body.copyWith(height: 1.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_proofTasks.isNotEmpty) ...[
                         SizedBox(height: 28),
                         Text('Proof Photos', style: AppTextStyles.h3),
                         SizedBox(height: 14),
                        _buildProofGallery(),
                      ],
                       SizedBox(height: 28),
                       Text('Last 30 Days', style: AppTextStyles.h3),
                       SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding:  EdgeInsets.all(18),
                          child: CompletionHeatmap(dailyCounts: _dailyCounts),
                        ),
                      ),
                      if (_recentSnoozes.isNotEmpty) ...[
                         SizedBox(height: 28),
                         Text('Recent Snoozes', style: AppTextStyles.h3),
                         SizedBox(height: 14),
                        _buildSnoozeList(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// Horizontal scroll of thumbnails from this goal's most recently
  /// completed proof-required tasks. Tapping one opens the full-size
  /// photo. Only shown when at least one exists.
  Widget _buildProofGallery() {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _proofTasks.length,
        separatorBuilder: (_, __) =>  SizedBox(width: 10),
        itemBuilder: (context, index) {
          final task = _proofTasks[index];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProofPhotoViewerScreen(task: task),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(task.proofImagePath!),
                width: 92,
                height: 92,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 92,
                  height: 92,
                  color: AppColors.divider,
                  child:  Icon(Icons.image_not_supported_outlined,
                      color: AppColors.textMuted),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Small card offering Streak Freeze — deliberately understated
  /// (not a big colorful banner) since this is meant for the
  /// occasional genuine miss, not something to reach for every day.
  Widget _buildStreakFreezeCard() {
    return Container(
      padding:  EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.ac_unit_rounded, color: AppColors.accent, size: 20),
           SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text('Streak Freeze', style: TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '$_freezesRemaining of ${StreakFreezeService.monthlyAllowance} left this month',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _openStreakFreeze,
            child: Text(
              'Use',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Row of all-time stat tiles — total completed/missed, and the
  /// resulting completion rate. Kept separate from the weekly
  /// StreakChart above, which is about *this week's* rhythm; this
  /// row is the all-time, harder-to-fake picture.
  Widget _buildOverviewGrid() {
    final stats = _overallStats;
    final completed = stats?.totalCompleted ?? 0;
    final missed = stats?.totalMissed ?? 0;
    final rate = stats == null ? 0 : (stats.completionRate * 100).round();
    final snoozes = stats?.snoozes ?? 0;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.success,
            value: '$completed',
            label: 'Completed',
          ),
        ),
         SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.highlight_off_rounded,
            iconColor: AppColors.danger,
            value: '$missed',
            label: 'Missed',
          ),
        ),
         SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.percent_rounded,
            iconColor: AppColors.accent,
            value: '$rate%',
            label: 'Completion',
          ),
        ),
         SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.snooze_rounded,
            iconColor: AppColors.warning,
            value: '$snoozes',
            label: 'Snoozes',
          ),
        ),
      ],
    );
  }

  /// Completion rate for JUST the tasks marked "requires photo proof"
  /// — a stricter, more honest number than the overall completion
  /// rate, since these are the tasks the user themselves said needed
  /// to be verified rather than taken on trust. Only shown once at
  /// least one such task has actually been resolved (completed or
  /// missed), so a goal that never uses photo proof doesn't get a
  /// misleading "0%" card for a feature it isn't using.
  Widget _buildProofComplianceCard() {
    final stats = _proofComplianceStats!;
    final rate = (stats.complianceRate * 100).round();
    final color = rate >= 80
        ? AppColors.success
        : rate >= 50
            ? AppColors.warning
            : AppColors.danger;

    return Container(
      width: double.infinity,
      padding:  EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, color: color, size: 22),
           SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Proof-Verified Tasks',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                 SizedBox(height: 2),
                Text(
                  '${stats.completed} of ${stats.resolved} tasks you '
                  'required a photo for were actually completed with one.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
           SizedBox(width: 8),
          Text(
            '$rate%',
            style: AppTextStyles.mono(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Recent snooze reasons for this goal — the direct payoff of
  /// logging them in the first place (see FullScreenAlarmScreen's
  /// SnoozeReasonSheet): the friction only works as accountability if
  /// the user can later see, in black and white, how often and why
  /// they've put a task off.
  Widget _buildSnoozeList() {
    return Column(
      children: _recentSnoozes.map((log) {
        return Container(
          margin:  EdgeInsets.only(bottom: 10),
          padding:  EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.snooze_rounded, color: AppColors.warning, size: 18),
               SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.reason, style: AppTextStyles.body),
                     SizedBox(height: 4),
                    Text(
                      _formatSnoozeDate(log.snoozedAt),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatSnoozeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return 'Today, ${_formatSnoozeTime(dt)}';
    if (diff == 1) return 'Yesterday, ${_formatSnoozeTime(dt)}';
    return '${dt.month}/${dt.day}, ${_formatSnoozeTime(dt)}';
  }

  String _formatSnoozeTime(DateTime dt) {
    final hour = dt.hour == 0
        ? 12
        : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

/// A single all-time stat tile used in the dashboard's Overview grid.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;  final String value;
  final String label;

   _StatTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:  EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
           SizedBox(height: 8),
          Text(
            value,
            style:  TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
           SizedBox(height: 2),
          Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
