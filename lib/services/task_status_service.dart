import '../database/db_helper.dart';
import '../models/task_model.dart';

/// Detects tasks whose scheduled window has fully passed without being
/// completed, and flips them to [TaskStatus.missed].
///
/// `TaskStatus.missed` existed as an enum value from the start, and
/// `TaskTile` already knew how to display it (red, cancel icon) — but
/// nothing in the app ever actually *set* it. A task the user simply
/// ignored stayed `pending` forever, which quietly skewed anything
/// that reasons about task state (e.g. a future "day streak" or
/// "completion rate" feature would have no way to distinguish
/// "not done yet" from "failed to do").
class TaskStatusService {
  TaskStatusService._internal();
  static final TaskStatusService instance = TaskStatusService._internal();

  final DBHelper _db = DBHelper.instance;

  /// How much slack we give a task past its scheduled end time before
  /// giving up on it. Someone starting a task 20 minutes late should
  /// still get credit for it — this isn't a hard alarm-precision
  /// deadline, just a "has this clearly been abandoned" check.
  static const Duration gracePeriod = Duration(hours: 1);

  /// Scans every `pending`/`inProgress` task and marks any whose
  /// deadline (scheduled time + its own duration + [gracePeriod]) has
  /// passed as `missed`. Safe to call as often as needed (on app
  /// launch, and from the daily background sync) — already-resolved
  /// tasks are never touched.
  ///
  /// Returns the tasks that were just marked missed, so callers can
  /// react to it (e.g. cancel their alarm, release an active app lock
  /// if it was guarding one of them).
  Future<List<Task>> markOverdueTasksAsMissed() async {
    final candidates = await _db.getActionableTasks();
    final now = DateTime.now();
    final List<Task> justMissed = [];

    for (final task in candidates) {
      if (now.isAfter(_deadlineFor(task))) {
        await _db.updateTaskStatus(task.id, status: TaskStatus.missed);
        justMissed.add(task);
      }
    }

    return justMissed;
  }

  DateTime _deadlineFor(Task task) {
    final parts = task.scheduledTime.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final scheduledStart = DateTime(
      task.scheduledDate.year,
      task.scheduledDate.month,
      task.scheduledDate.day,
      hour,
      minute,
    );

    return scheduledStart
        .add(Duration(minutes: task.durationMinutes))
        .add(gracePeriod);
  }
}
