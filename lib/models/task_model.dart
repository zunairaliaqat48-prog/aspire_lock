enum TaskStatus {
  pending,
  inProgress,
  completed,
  missed,
}

/// Result of [DBHelper.getStreakStats] — how many consecutive
/// scheduled days (rest days excluded) a goal has currently completed
/// in full, and the longest such run the goal has ever had.
class StreakStats {
  final int current;
  final int longest;

  const StreakStats({required this.current, required this.longest});
}

/// Result of [DBHelper.getOverallStats] — a goal's all-time totals,
/// for the dashboard's stat tiles. [completionRate] is 0.0–1.0 and
/// only counts tasks that are actually resolved one way or the other
/// (completed or missed) — a task still pending today isn't a "loss"
/// yet, so it's excluded rather than silently dragging the rate down.
class GoalOverallStats {
  final int totalCompleted;
  final int totalMissed;
  final int snoozes;

  const GoalOverallStats({
    required this.totalCompleted,
    required this.totalMissed,
    required this.snoozes,
  });

  double get completionRate {
    final resolved = totalCompleted + totalMissed;
    if (resolved == 0) return 0;
    return totalCompleted / resolved;
  }
}

/// Completion rate restricted to only the tasks the user marked as
/// needing photo proof — see [DBHelper.getProofComplianceStats]. Kept
/// as its own small class rather than folded into [GoalOverallStats]
/// so a goal that doesn't use photo proof at all (resolved == 0) can
/// cleanly hide the whole card instead of showing a misleading 0%.
class ProofComplianceStats {
  final int completed;
  final int missed;

  const ProofComplianceStats({required this.completed, required this.missed});

  int get resolved => completed + missed;

  double get complianceRate {
    if (resolved == 0) return 0;
    return completed / resolved;
  }
}

/// One hour-of-day bucket (0–23) of a goal's resolved (completed or
/// missed) task history — the raw material for
/// [InsightsService.getBestHours]. Purely a local aggregation of the
/// goal's own `tasks` rows; no external service involved.
class HourlyCompletionStat {
  final int hour; // 0–23
  final int completed;
  final int missed;

  const HourlyCompletionStat({
    required this.hour,
    required this.completed,
    required this.missed,
  });

  int get total => completed + missed;

  double get rate => total == 0 ? 0 : completed / total;
}

extension TaskStatusX on TaskStatus {
  static TaskStatus fromString(String value) {
    return TaskStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskStatus.pending,
    );
  }
}

class Task {
  final String id;
  final String goalId; // links back to Goal
  final String title; // e.g. "30 min Cardio"
  final DateTime scheduledDate; // the day this task belongs to
  final String scheduledTime; // stored as "HH:mm", e.g. "14:00"
  final int durationMinutes; // how long the task should take
  final bool requiresPhotoProof;
  final TaskStatus status;
  final String? proofImagePath; // local path to captured photo proof
  final DateTime? completedAt;
  final int snoozeCount; // how many times this task's alarm was snoozed

  /// Id of the [ScheduleRule] this task was generated from, if any —
  /// manually-added one-off tasks (if the app ever gains those again)
  /// would leave this null. This is the ONLY thing
  /// TaskGenerationService uses to decide "does this rule already have
  /// a task for this day" — see its dedup logic. Deliberately NOT
  /// title+time, since editing either of those (EditTaskSheet) used to
  /// make the very next generation pass think the day still needed a
  /// task and silently create a duplicate.
  final String? sourceRuleId;

  /// When the user actually tapped "Start Task" on this specific
  /// occurrence — used to enforce that a task can't be marked complete
  /// before its full [durationMinutes] has actually elapsed. Null
  /// until started.
  final DateTime? startedAt;

  Task({
    required this.id,
    required this.goalId,
    required this.title,
    required this.scheduledDate,
    required this.scheduledTime,
    this.durationMinutes = 30,
    this.requiresPhotoProof = false,
    this.status = TaskStatus.pending,
    this.proofImagePath,
    this.completedAt,
    this.snoozeCount = 0,
    this.sourceRuleId,
    this.startedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'goalId': goalId,
      'title': title,
      'scheduledDate': scheduledDate.toIso8601String(),
      'scheduledTime': scheduledTime,
      'durationMinutes': durationMinutes,
      'requiresPhotoProof': requiresPhotoProof ? 1 : 0,
      'status': status.name,
      'proofImagePath': proofImagePath,
      'completedAt': completedAt?.toIso8601String(),
      'snoozeCount': snoozeCount,
      'sourceRuleId': sourceRuleId,
      'startedAt': startedAt?.toIso8601String(),
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      goalId: map['goalId'] as String,
      title: map['title'] as String,
      scheduledDate: DateTime.parse(map['scheduledDate'] as String),
      scheduledTime: map['scheduledTime'] as String,
      durationMinutes: map['durationMinutes'] as int,
      requiresPhotoProof: (map['requiresPhotoProof'] as int) == 1,
      status: TaskStatusX.fromString(map['status'] as String),
      proofImagePath: map['proofImagePath'] as String?,
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      snoozeCount: (map['snoozeCount'] as int?) ?? 0,
      sourceRuleId: map['sourceRuleId'] as String?,
      startedAt: map['startedAt'] != null
          ? DateTime.parse(map['startedAt'] as String)
          : null,
    );
  }

  Task copyWith({
    TaskStatus? status,
    String? proofImagePath,
    DateTime? completedAt,
    int? snoozeCount,
    DateTime? startedAt,
  }) {
    return Task(
      id: id,
      goalId: goalId,
      title: title,
      scheduledDate: scheduledDate,
      scheduledTime: scheduledTime,
      durationMinutes: durationMinutes,
      requiresPhotoProof: requiresPhotoProof,
      status: status ?? this.status,
      proofImagePath: proofImagePath ?? this.proofImagePath,
      completedAt: completedAt ?? this.completedAt,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      sourceRuleId: sourceRuleId,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}
