import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/goal_model.dart';
import '../models/task_model.dart';
import '../database/db_helper.dart';
import '../services/task_generation_service.dart';
import '../services/task_status_service.dart';
import '../services/notification_service.dart';
import '../services/selected_goal_controller.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../widgets/task_tile.dart';
import '../widgets/edit_task_sheet.dart';
import '../widgets/streak_lost_sheet.dart';
import 'onboarding/goal_category_screen.dart';
import 'alarm/full_screen_alarm_screen.dart';
import 'task/proof_photo_viewer_screen.dart';
import 'schedule/manage_schedule_screen.dart';
import 'schedule/phase_list_screen.dart';
import 'goal/goal_achieved_screen.dart';

class HomeScreen extends StatefulWidget {
  HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Goal> _goals = [];
  Goal? _selectedGoal;
  List<Task> _allTodayTasks = []; // every active goal's tasks for today
  bool _loading = true;
  int _streak = 0;

  /// Today's tasks belonging to whichever goal is currently selected
  /// in the goal switcher. Filtered client-side from [_allTodayTasks]
  /// so switching goals doesn't need another DB round trip.
  List<Task> get _todayTasks {
    final goalId = _selectedGoal?.id;
    if (goalId == null) return [];
    return _allTodayTasks.where((t) => t.goalId == goalId).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final goals = await DBHelper.instance.getActiveGoals();

    if (goals.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GoalCategoryScreen()),
      );
      return;
    }

    // Keep whichever goal was already selected (e.g. after an edit or
    // a pull-to-refresh) if it's still around; otherwise fall back to
    // the first active goal.
    final previousSelectedId = _selectedGoal?.id;
    final selected = goals.firstWhere(
      (g) => g.id == previousSelectedId,
      orElse: () => goals.first,
    );

    // Catch anything the user simply ignored past its deadline, before
    // we show today's list — otherwise a stale task would sit as
    // "pending" forever instead of honestly showing as missed.
    final justMissed = await TaskStatusService.instance.markOverdueTasksAsMissed();
    for (final missedTask in justMissed) {
      await NotificationService.instance.cancelTaskAlarm(missedTask);
    }

    // Covers the case where the app has stayed open across midnight
    // (or was opened before the daily background sync ran) — makes
    // sure today's recurring tasks exist before we display them. The
    // return value isn't needed here — see the pendingTasks reschedule
    // below instead of using just this call's newly-created tasks.
    await TaskGenerationService.instance.generateMissingTasksForAllActiveGoals();

    // Not filtered by goal here — covers every active goal's tasks for
    // today. _todayTasks (the getter) narrows it down to whichever
    // goal is selected in the switcher.
    final tasks = await DBHelper.instance.getTasksForDate(DateTime.now());

    // Reschedule every still-pending task's alarm here — not just
    // newTasks. A task created in an earlier session (e.g. before
    // notification permission was granted, or before this device's
    // notification setup was fixed) would otherwise never get a
    // second chance: newTasks is empty on every later load since the
    // task already exists, so its alarm would silently stay
    // unscheduled forever. scheduleTaskAlarm is safe to call again for
    // an already-scheduled task — it reuses the same notification id,
    // so this just re-confirms/overwrites rather than duplicating, and
    // it already skips anything whose time has passed.
    final pendingTasks =
        tasks.where((t) => t.status == TaskStatus.pending).toList();
    // ignore: avoid_print
    print('[AspireLockAlarms] Home _load(): ${tasks.length} task(s) today, '
        '${pendingTasks.length} pending — will reschedule alarms for '
        'the pending ones.');
    if (pendingTasks.isNotEmpty) {
      await NotificationService.instance.scheduleAllTasks(pendingTasks);
    }

    // Same "unresolved today" set the streak itself cares about —
    // pending (not yet started) AND inProgress (started but not
    // finished) both still leave the streak at risk; only completed
    // or missed are settled one way or the other.
    final unresolvedToday = tasks
        .where((t) =>
            t.status == TaskStatus.pending ||
            t.status == TaskStatus.inProgress)
        .isNotEmpty;
    if (unresolvedToday) {
      await NotificationService.instance.scheduleStreakRiskReminder();
    } else {
      await NotificationService.instance.cancelStreakRiskReminder();
    }

    if (!mounted) return;
    final streakStats = await DBHelper.instance.getStreakStats(selected.id);
    if (!mounted) return;
    setState(() {
      _goals = goals;
      _selectedGoal = selected;
      _allTodayTasks = tasks;
      _streak = streakStats.current;
      _loading = false;
    });
    SelectedGoalController.instance.set(selected);
    _checkForBrokenStreak(selected, streakStats.current);
  }

  /// Compares the streak HomeScreen is about to show against the value
  /// it last showed (persisted on the Goal itself — see
  /// Goal.lastSeenStreak). A drop means the streak broke since the app
  /// was last opened, which otherwise would have gone completely
  /// unnoticed — it'd just quietly render as a smaller number with no
  /// distinct moment marking the loss. Small dips (from 1 or less)
  /// aren't worth interrupting the user over — there's barely anything
  /// to mourn yet — so this only fires once a real streak (2+ days)
  /// existed and then dropped.
  Future<void> _checkForBrokenStreak(Goal goal, int currentStreak) async {
    final previous = goal.lastSeenStreak;
    final broke = previous >= 2 && currentStreak < previous;

    // Persist regardless of whether it broke, so next time this only
    // fires on a genuinely new drop rather than re-comparing against
    // a stale value forever.
    await DBHelper.instance.updateLastSeenStreak(goal.id, currentStreak);

    if (!broke || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      StreakLostSheet.show(context, goalTitle: goal.title, lostStreak: previous);
    });
  }

  /// Re-fetches just the streak count for whichever goal is now
  /// selected — used by [_selectGoal] so switching goals updates the
  /// header's streak badge without re-running the whole [_load] (which
  /// would also re-check overdue tasks and reschedule alarms, neither
  /// of which needs to happen just because the user tapped a different
  /// goal chip).
  Future<void> _refreshStreak(String goalId) async {
    final streakStats = await DBHelper.instance.getStreakStats(goalId);
    if (!mounted) return;
    setState(() => _streak = streakStats.current);
  }

  void _selectGoal(Goal goal) {
    if (goal.id == _selectedGoal?.id) return;
    setState(() => _selectedGoal = goal);
    SelectedGoalController.instance.set(goal);
    _refreshStreak(goal.id);
  }

  void _openTask(Task task) {
    if (task.status == TaskStatus.completed) {
      // Nothing to show without a saved proof photo — this task simply
      // didn't require one, so there's no history to view.
      if (task.proofImagePath == null || task.proofImagePath!.isEmpty) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProofPhotoViewerScreen(task: task)),
      );
      return;
    }
    if (task.status == TaskStatus.missed) return;

    // In the full build, this screen is normally reached by tapping the
    // fired alarm notification. For now (before native notification-tap
    // wiring), tapping a pending task simulates the alarm firing so the
    // flow can be tested end-to-end.
    Navigator.of(context)
        .push(
      MaterialPageRoute(builder: (_) => FullScreenAlarmScreen(task: task)),
    )
        .then((_) => _load());
  }

  int get _completedCount =>
      _todayTasks.where((t) => t.status == TaskStatus.completed).length;

  // ---------------- GOAL: EDIT / DELETE ----------------

  /// Routes a tap on any individual goal's own 3-dot menu (see
  /// [_buildGoalList]) to the right action for that *specific* goal —
  /// not necessarily whichever one happens to be selected right now.
  void _onGoalMenuAction(Goal goal, String action) {
    switch (action) {
      case 'edit':
        _editGoal(goal);
        break;
      case 'schedule':
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => ManageScheduleScreen(goal: goal),
              ),
            )
            .then((_) => _load());
        break;
      case 'phases':
        Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => PhaseListScreen(goal: goal)),
            )
            .then((_) => _load());
        break;
      case 'achieve':
        _markGoalAchieved(goal);
        break;
      case 'delete':
        _deleteGoal(goal);
        break;
    }
  }

  Future<void> _editGoal(Goal goal) async {
    final titleController = TextEditingController(text: goal.title);
    final targetController = TextEditingController(text: goal.targetInfo ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(labelText: 'Goal title'),
              autofocus: true,
            ),
            SizedBox(height: 12),
            TextField(
              controller: targetController,
              decoration:
                  InputDecoration(labelText: 'Target (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final newTitle = titleController.text.trim();
    if (newTitle.isEmpty) return;

    await DBHelper.instance.updateGoal(
      goal.copyWith(
        title: newTitle,
        targetInfo: targetController.text.trim().isEmpty
            ? null
            : targetController.text.trim(),
      ),
    );
    await _load();
  }

  Future<void> _deleteGoal(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete goal?'),
        content: Text(
          'This deletes "${goal.title}" and stops all its scheduled tasks. '
          'This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Cancel alarms for every not-yet-resolved task under this goal —
    // there's no point an alarm firing for a goal that no longer exists.
    final goalTasks = await DBHelper.instance.getTasksForGoal(goal.id);
    for (final task in goalTasks) {
      if (task.status == TaskStatus.pending ||
          task.status == TaskStatus.inProgress) {
        await NotificationService.instance.cancelTaskAlarm(task);
      }
    }

    await DBHelper.instance.deactivateGoal(goal.id);
    await _load();
  }

  /// Confirms with the user and cancels any pending alarms for this
  /// goal (same cleanup as _deleteGoal — an achieved goal shouldn't
  /// leave a notification that fires for a goal that's now finished),
  /// then records it via DBHelper.markGoalAchieved and shows
  /// GoalAchievedScreen.
  Future<void> _markGoalAchieved(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as achieved?'),
        content: Text(
          'This marks "${goal.title}" as complete and stops its scheduled '
          'tasks. It\'ll move to your Achievements instead of being deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            child: const Text('Mark Achieved'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final goalTasks = await DBHelper.instance.getTasksForGoal(goal.id);
    for (final task in goalTasks) {
      if (task.status == TaskStatus.pending ||
          task.status == TaskStatus.inProgress) {
        await NotificationService.instance.cancelTaskAlarm(task);
      }
    }

    await DBHelper.instance.markGoalAchieved(goal.id);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GoalAchievedScreen(goal: goal)),
    );
  }

  // ---------------- TASK: EDIT / DELETE ----------------

  Future<void> _editTask(Task task) async {
    final result = await EditTaskSheet.show(context, task);
    if (result == null) return;

    await DBHelper.instance.updateTaskDetails(
      task.id,
      title: result.title,
      scheduledTime: result.scheduledTime,
      durationMinutes: result.durationMinutes,
      requiresPhotoProof: result.requiresPhotoProof,
    );

    // Time (or title) may have changed, so the old alarm needs to be
    // replaced rather than left pointing at stale info.
    await NotificationService.instance.cancelTaskAlarm(task);
    final updatedTask = await DBHelper.instance.getTaskById(task.id);
    if (updatedTask != null) {
      await NotificationService.instance.scheduleTaskAlarm(updatedTask);
    }

    await _load();
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete task?'),
        content: Text('"${task.title}" will be removed for today.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await NotificationService.instance.cancelTaskAlarm(task);
    await DBHelper.instance.deleteTask(task.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final total = _todayTasks.length;
    final progress = total == 0 ? 0.0 : _completedCount / total;
    final dateLabel = DateFormat('EEEE, d MMM').format(DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: _buildHeader(dateLabel, progress, total),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
                sliver: _todayTasks.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final task = _todayTasks[index];
                            final isActionable =
                                task.status != TaskStatus.completed &&
                                    task.status != TaskStatus.missed;
                            return Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: TaskTile(
                                task: task,
                                onTap: () => _openTask(task),
                                trailing: isActionable
                                    ? PopupMenuButton<String>(
                                        icon: Icon(
                                          Icons.more_vert_rounded,
                                          color: AppColors.textMuted,
                                        ),
                                        onSelected: (value) {
                                          if (value == 'edit') _editTask(task);
                                          if (value == 'delete') {
                                            _deleteTask(task);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                              'Delete',
                                              style: TextStyle(
                                                  color: AppColors.danger),
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          },
                          childCount: _todayTasks.length,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String dateLabel, double progress, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Add Goal" now lives as the prominent centre-docked FAB on
        // MainNavScreen's bottom bar instead of a small icon here, so
        // it's reachable from every tab, not just Home.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateLabel, style: AppTextStyles.caption),
                  SizedBox(height: 2),
                  Text('Your Goals', style: AppTextStyles.h1),
                ],
              ),
            ),
            if (_selectedGoal != null) _buildStreakBadge(),
          ],
        ),
        SizedBox(height: 16),
        if (_goals.isNotEmpty) ...[
          _buildGoalList(),
          SizedBox(height: 16),
        ],
        if (total > 0) _buildProgressCard(progress),
      ],
    );
  }

  /// Shown on every single app open, not tucked away on a dashboard
  /// screen the user has to navigate to — the whole point of a streak
  /// as a loss-aversion device is that the cost of breaking it has to
  /// be visible *before* the user decides whether to skip today, not
  /// discovered afterwards. Colour escalates from neutral -> warm ->
  /// hot the longer the streak runs, so a long streak visibly has more
  /// to lose than a fresh one.
  Widget _buildStreakBadge() {
    final Color badgeColor = _streak == 0
        ? AppColors.textMuted
        : _streak < 7
            ? AppColors.accent
            : _streak < 30
                ? AppColors.warning
                : AppColors.danger;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, color: badgeColor, size: 20),
          SizedBox(width: 5),
          Text(
            '$_streak',
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }

  /// Every active goal as a compact selectable card inside one
  /// horizontally-scrollable section — previously each goal was its
  /// own full-width row stacked vertically, which grew the header
  /// taller with every goal and made them read as separate floating
  /// items rather than one "Goals" area. Each card still has its own
  /// 3-dot menu (Edit/Schedule/Phases/Achieve/Delete), so e.g. "Study"
  /// and "Weight Loss" each get their own actions, not just whichever
  /// goal happens to be selected.
  /// Every active goal as a compact, naturally-sized chip that wraps
  /// to a new line instead of stacking vertically or scrolling off
  /// the edge of the screen. Each chip still has its own 3-dot menu
  /// (Edit/Schedule/Phases/Achieve/Delete), so e.g. "Study" and
  /// "Weight Loss" each get their own actions, not just whichever
  /// goal happens to be selected.
  Widget _buildGoalList() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final goal in _goals) _buildGoalRow(goal)],
    );
  }

  Widget _buildGoalRow(Goal goal) {
    final isSelected = goal.id == _selectedGoal?.id;
    return Material(
      color: isSelected
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _selectGoal(goal),
        child: Container(
          constraints: BoxConstraints(maxWidth: 200),
          padding: EdgeInsets.only(left: 14, right: 4, top: 10, bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.divider,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  goal.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert_rounded,
                    color: AppColors.textMuted, size: 20),
                onSelected: (action) => _onGoalMenuAction(goal, action),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'schedule', child: Text('Schedule')),
                  PopupMenuItem(value: 'phases', child: Text('Phases')),
                  PopupMenuItem(value: 'achieve', child: Text('Mark Achieved')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressCard(double progress) {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s Progress',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '$_completedCount of ${_todayTasks.length} tasks done',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.local_fire_department,
                color: AppColors.accent, size: 26),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    // Reached once a goal already exists but simply has nothing
    // scheduled for today (e.g. a freshly-created goal with no phase
    // yet, or a phase with no daily tasks) — not the true "no goals
    // at all" case, which _load() already redirects straight to
    // GoalCategoryScreen for.
    final goal = _selectedGoal;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.event_available_outlined,
                size: 38, color: AppColors.accent),
          ),
          SizedBox(height: 20),
          Text('All clear for today', style: AppTextStyles.h2),
          SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              goal != null
                  ? 'Nothing scheduled right now for "${goal.title}" — add a phase or task to keep it moving.'
                  : 'Nothing scheduled right now — enjoy the free time, or add a goal to get moving.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
          ),
          SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () {
              if (goal != null) {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => PhaseListScreen(goal: goal),
                      ),
                    )
                    .then((_) => _load());
              } else {
                // Defensive fallback only — in practice _load() never
                // lets this screen render with zero goals at all.
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => GoalCategoryScreen()),
                );
              }
            },
            icon: Icon(Icons.add_rounded, size: 18),
            label: Text(goal != null ? 'Add Phase / Task' : 'Add a goal'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.divider),
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
