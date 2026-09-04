/// A single logged reason for snoozing a task's alarm — the
/// replacement for the old "Emergency Unlock" log now that
/// app-locking has been removed. See [DBHelper]'s task_snoozes table
/// and SnoozeReasonSheet, which is what actually collects [reason]
/// from the user before the alarm is pushed back.
class TaskSnoozeLog {
  final String id;
  final String taskId;
  final String goalId;
  final String reason;
  final DateTime snoozedAt;

  const TaskSnoozeLog({
    required this.id,
    required this.taskId,
    required this.goalId,
    required this.reason,
    required this.snoozedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'taskId': taskId,
        'goalId': goalId,
        'reason': reason,
        'snoozedAt': snoozedAt.toIso8601String(),
      };

  factory TaskSnoozeLog.fromMap(Map<String, dynamic> map) => TaskSnoozeLog(
        id: map['id'] as String,
        taskId: map['taskId'] as String,
        goalId: map['goalId'] as String,
        reason: map['reason'] as String,
        snoozedAt: DateTime.parse(map['snoozedAt'] as String),
      );
}
