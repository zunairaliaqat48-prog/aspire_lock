/// A phase's lifecycle: only one phase per goal should be `active` at a
/// time. Phases before it are `completed`, phases after it are `upcoming`.
enum PhaseStatus {
  upcoming,
  active,
  completed,
}

extension PhaseStatusX on PhaseStatus {
  static PhaseStatus fromString(String value) {
    return PhaseStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PhaseStatus.upcoming,
    );
  }
}

/// A single user-defined stage within a larger goal.
///
/// Aspire Lock never invents phase content — the user names the phase
/// (e.g. "Learn Graphic Design", "Build Portfolio", "Pitch Clients")
/// and decides how long it runs. This model is just the container;
/// [ScheduleRule.phaseId] links each phase to the daily tasks the user
/// adds under it.
class GoalPhase {
  final String id;
  final String goalId;
  final String title;

  /// 1-based position among the goal's phases — determines the order
  /// phases activate in.
  final int orderIndex;

  /// How many days this phase should run once active, as set by the
  /// user. Null means an open-ended/ongoing phase with no fixed end
  /// (e.g. a final "Deliver & Grow" phase that just continues).
  final int? durationDays;

  final PhaseStatus status;
  final DateTime createdAt;

  /// When this phase became active — null until then. Used together
  /// with [durationDays] to know when a phase's time is up.
  final DateTime? startedAt;

  GoalPhase({
    required this.id,
    required this.goalId,
    required this.title,
    required this.orderIndex,
    this.durationDays,
    this.status = PhaseStatus.upcoming,
    DateTime? createdAt,
    this.startedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// True once [durationDays] have elapsed since [startedAt]. Always
  /// false for open-ended phases (no [durationDays]) or phases that
  /// haven't started yet.
  bool get isDurationElapsed {
    if (durationDays == null || startedAt == null) return false;
    final deadline = startedAt!.add(Duration(days: durationDays!));
    return DateTime.now().isAfter(deadline);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'goalId': goalId,
      'title': title,
      'orderIndex': orderIndex,
      'durationDays': durationDays,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'startedAt': startedAt?.toIso8601String(),
    };
  }

  factory GoalPhase.fromMap(Map<String, dynamic> map) {
    return GoalPhase(
      id: map['id'] as String,
      goalId: map['goalId'] as String,
      title: map['title'] as String,
      orderIndex: map['orderIndex'] as int,
      durationDays: map['durationDays'] as int?,
      status: PhaseStatusX.fromString(map['status'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
      startedAt: map['startedAt'] == null
          ? null
          : DateTime.parse(map['startedAt'] as String),
    );
  }

  GoalPhase copyWith({
    String? title,
    int? orderIndex,
    int? durationDays,
    PhaseStatus? status,
    DateTime? startedAt,
  }) {
    return GoalPhase(
      id: id,
      goalId: goalId,
      title: title ?? this.title,
      orderIndex: orderIndex ?? this.orderIndex,
      durationDays: durationDays ?? this.durationDays,
      status: status ?? this.status,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}
