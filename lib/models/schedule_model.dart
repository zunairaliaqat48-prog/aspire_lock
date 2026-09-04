/// Represents recurring schedule rules for a goal,
/// e.g. "Exercise at 2:00 PM every day" — used to
/// regenerate tasks day after day automatically.
class ScheduleRule {
  final String id;
  final String goalId;

  /// Which user-defined [GoalPhase] this rule belongs to, if the goal
  /// uses phases. Null for goals created before phases existed, or
  /// goals that don't use phases — those keep working exactly as
  /// before.
  final String? phaseId;
  final String taskTitle;
  final String time; // "HH:mm"
  final int durationMinutes;
  final List<int> activeWeekdays; // 1 = Monday ... 7 = Sunday
  final bool requiresPhotoProof;
  final bool isActive;

  ScheduleRule({
    required this.id,
    required this.goalId,
    this.phaseId,
    required this.taskTitle,
    required this.time,
    this.durationMinutes = 30,
    this.activeWeekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.requiresPhotoProof = false,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'goalId': goalId,
      'phaseId': phaseId,
      'taskTitle': taskTitle,
      'time': time,
      'durationMinutes': durationMinutes,
      'activeWeekdays': activeWeekdays.join(','),
      'requiresPhotoProof': requiresPhotoProof ? 1 : 0,
      'isActive': isActive ? 1 : 0,
    };
  }

  factory ScheduleRule.fromMap(Map<String, dynamic> map) {
    return ScheduleRule(
      id: map['id'] as String,
      goalId: map['goalId'] as String,
      phaseId: map['phaseId'] as String?,
      taskTitle: map['taskTitle'] as String,
      time: map['time'] as String,
      durationMinutes: map['durationMinutes'] as int,
      activeWeekdays: (map['activeWeekdays'] as String)
          .split(',')
          .where((e) => e.isNotEmpty)
          .map(int.parse)
          .toList(),
      requiresPhotoProof: (map['requiresPhotoProof'] as int) == 1,
      isActive: (map['isActive'] as int) == 1,
    );
  }
}
