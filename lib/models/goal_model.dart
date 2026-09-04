enum GoalCategory {
  weightLoss,
  study,
  business,
  health,
  future,
  custom,
}

extension GoalCategoryX on GoalCategory {
  String get label {
    switch (this) {
      case GoalCategory.weightLoss:
        return 'Weight Loss';
      case GoalCategory.study:
        return 'Study';
      case GoalCategory.business:
        return 'Business';
      case GoalCategory.health:
        return 'Health Care';
      case GoalCategory.future:
        return 'Future Planning';
      case GoalCategory.custom:
        return 'Custom Goal';
    }
  }

  static GoalCategory fromString(String value) {
    return GoalCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GoalCategory.custom,
    );
  }
}

class Goal {
  final String id;
  final String title;
  final GoalCategory category;
  final String? targetInfo; // e.g. "Lose 5kg", "Finish thesis by Dec"
  final DateTime createdAt;
  final bool isActive;

  /// Non-null once the user has marked this goal as achieved (see
  /// DBHelper.markGoalAchieved) — distinct from just being deleted.
  /// A deleted goal has isActive=0 and achievedAt=null; an achieved
  /// goal has isActive=0 and achievedAt set, so it can still be found
  /// again in the Achievements list instead of disappearing forever.
  final DateTime? achievedAt;

  /// The current streak value HomeScreen last showed the user for
  /// this goal, persisted so a drop can actually be *noticed* — see
  /// DBHelper.updateLastSeenStreak and HomeScreen._checkForBrokenStreak.
  /// Without this, a streak silently resetting to 0 overnight would
  /// just quietly show "0" next time the app opens; comparing against
  /// this is what turns that into a felt "you lost your streak" moment
  /// instead.
  final int lastSeenStreak;

  Goal({
    required this.id,
    required this.title,
    required this.category,
    this.targetInfo,
    DateTime? createdAt,
    this.isActive = true,
    this.achievedAt,
    this.lastSeenStreak = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category.name,
      'targetInfo': targetInfo,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive ? 1 : 0,
      'achievedAt': achievedAt?.toIso8601String(),
      'lastSeenStreak': lastSeenStreak,
    };
  }

  factory Goal.fromMap(Map<String, dynamic> map) {
    return Goal(
      id: map['id'] as String,
      title: map['title'] as String,
      category: GoalCategoryX.fromString(map['category'] as String),
      targetInfo: map['targetInfo'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      isActive: (map['isActive'] as int) == 1,
      achievedAt: map['achievedAt'] != null
          ? DateTime.parse(map['achievedAt'] as String)
          : null,
      // Older rows created before this column existed come back as
      // null from sqflite rather than throwing — default to 0 exactly
      // like a brand new goal would, rather than crashing on old data.
      lastSeenStreak: (map['lastSeenStreak'] as int?) ?? 0,
    );
  }

  Goal copyWith({
    String? title,
    GoalCategory? category,
    String? targetInfo,
    bool? isActive,
    DateTime? achievedAt,
    int? lastSeenStreak,
  }) {
    return Goal(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      targetInfo: targetInfo ?? this.targetInfo,
      createdAt: createdAt,
      isActive: isActive ?? this.isActive,
      achievedAt: achievedAt ?? this.achievedAt,
      lastSeenStreak: lastSeenStreak ?? this.lastSeenStreak,
    );
  }
}
