import '../database/db_helper.dart';
import '../models/task_model.dart';
import 'ai_schedule_service.dart';

/// Turns each active goal's recurring [ScheduleRule]s into real,
/// concrete [Task] rows for whichever days don't have them yet.
///
/// Without this, a goal would only ever have tasks for whichever day
/// they were entered on — `ScheduleRuleEngine.generateTasksFromRules()`
/// existed but nothing ever called it again after that, so "day 2
/// onward" simply never got any tasks. This service is what makes a
/// goal's schedule actually recurring, and (via
/// `DBHelper.getGenerationRulesForGoal`) makes sure only the goal's
/// currently *active* phase generates tasks.
class TaskGenerationService {
  TaskGenerationService._internal();
  static final TaskGenerationService instance =
      TaskGenerationService._internal();

  final DBHelper _db = DBHelper.instance;
  final ScheduleRuleEngine _ruleEngine = ScheduleRuleEngine();

  /// Safety cap: if the app hasn't been opened (and no periodic sync
  /// has run) for a long time, don't try to backfill every missed day
  /// — that could flood the task list with weeks of stale, unactionable
  /// tasks. A week of backfill is enough to recover from a normal gap
  /// without overwhelming the user.
  static const int maxBackfillDays = 7;

  /// For every active goal, generates tasks for each day from the day
  /// after its most recent task through today (inclusive), using that
  /// goal's active schedule rules. Safe to call repeatedly — a goal
  /// with no schedule rules yet, or with tasks already covering today,
  /// is simply skipped.
  ///
  /// Returns the newly created tasks (e.g. so the caller can schedule
  /// alarms for them immediately).
  Future<List<Task>> generateMissingTasksForAllActiveGoals() async {
    final goals = await _db.getActiveGoals();
    final List<Task> allNewTasks = [];

    for (final goal in goals) {
      final rules = await _db.getGenerationRulesForGoal(goal.id);
      if (rules.isEmpty) continue;

      final today = _dateOnly(DateTime.now());
      final lastTaskDate = await _db.getLatestTaskDateForGoal(goal.id);

      final DateTime startDate;
      if (lastTaskDate == null) {
        // No tasks at all for this goal yet — just cover today rather
        // than guessing how far back it "should" have started.
        startDate = today;
      } else {
        final earliestAllowed =
            today.subtract(const Duration(days: maxBackfillDays));
        // Deliberately starts FROM the last task's own day (not the
        // day after) and re-checks it — see the per-day dedup below.
        // Otherwise, a rule added *today* after another rule had
        // already generated today's task would never get its own
        // task/alarm until tomorrow, since "a task already exists
        // today" used to be treated as "today is fully handled".
        final lastDay = _dateOnly(lastTaskDate);
        startDate = lastDay.isBefore(earliestAllowed) ? earliestAllowed : lastDay;
      }

      for (DateTime day = startDate;
          !day.isAfter(today);
          day = day.add(const Duration(days: 1))) {
        // What's already on this day for this goal, keyed by the
        // originating rule's own stable id — NOT time+title. Title or
        // time can change after the fact (EditTaskSheet edits a single
        // occurrence), and keying on those meant an edited task no
        // longer matched its own rule's dedup key, so the very next
        // generation pass thought the rule still needed a task today
        // and silently created a duplicate at the rule's original
        // time. A rule's id never changes, so this can't happen
        // anymore. Tasks created before this column existed have a
        // null sourceRuleId — fall back to the old time+title key for
        // just those, so historical data doesn't suddenly duplicate.
        final existing = await _db.getTasksForGoalAndDate(goal.id, day);
        final existingKeys = existing
            .map((t) => t.sourceRuleId ?? 'legacy|${t.scheduledTime}|${t.title}')
            .toSet();

        final candidates = _ruleEngine.generateTasksFromRules(
          goal.id,
          rules,
          day,
        );
        final newTasks = candidates
            .where((t) =>
                !existingKeys.contains(t.sourceRuleId) &&
                !existingKeys.contains('legacy|${t.scheduledTime}|${t.title}'))
            .toList();

        if (newTasks.isNotEmpty) {
          await _db.insertTasks(newTasks);
          allNewTasks.addAll(newTasks);
        }
      }
    }

    return allNewTasks;
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
}
