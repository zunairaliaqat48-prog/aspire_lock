import '../models/task_model.dart';
import '../models/schedule_model.dart';
import '../utils/id_generator.dart';

/// Turns a goal's recurring [ScheduleRule]s into concrete [Task] rows
/// for a specific day.
///
/// Aspire Lock never invents a plan for the user — there is no
/// template library and no auto-generated schedule anymore. Every
/// [ScheduleRule] this class works from was authored by the user
/// themselves (see `create_phase_screen.dart` / `phase_list_screen.dart`).
/// This engine's only job is the mechanical, repeatable part: "it's
/// Tuesday, which of this goal's rules are due today, and what do
/// today's task rows look like".
class ScheduleRuleEngine {
  /// Generates concrete Tasks for a specific [date] from a goal's
  /// active ScheduleRules. Called daily (e.g. at midnight, or when the
  /// app catches up after being closed) to populate that day's task
  /// list. [rules] should already be filtered to whichever rules are
  /// allowed to generate right now — see
  /// `DBHelper.getGenerationRulesForGoal`, which excludes rules
  /// belonging to a phase that isn't active yet.
  List<Task> generateTasksFromRules(
    String goalId,
    List<ScheduleRule> rules,
    DateTime date,
  ) {
    final weekday = date.weekday; // 1 = Monday ... 7 = Sunday
    return rules
        .where((r) => r.isActive && r.activeWeekdays.contains(weekday))
        .map((r) => Task(
              id: generateId(),
              goalId: goalId,
              title: r.taskTitle,
              scheduledDate: date,
              scheduledTime: r.time,
              durationMinutes: r.durationMinutes,
              requiresPhotoProof: r.requiresPhotoProof,
              sourceRuleId: r.id,
            ))
        .toList();
  }
}
