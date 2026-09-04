import '../models/schedule_model.dart';

/// Shared logic for detecting when two recurring [ScheduleRule]s would
/// overlap — same weekday(s) and overlapping time windows — so the
/// user is never able to schedule two tasks that would need to be
/// "active" (and lock the phone) at the same moment.
///
/// A conflict only matters if the two rules share at least one active
/// weekday AND their [time, time + durationMinutes) windows intersect.
class ScheduleConflict {
  ScheduleConflict._();

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static bool _weekdaysOverlap(List<int> a, List<int> b) {
    return a.any((d) => b.contains(d));
  }

  static bool _timesOverlap(
    String timeA,
    int durationA,
    String timeB,
    int durationB,
  ) {
    final startA = _toMinutes(timeA);
    final endA = startA + durationA;
    final startB = _toMinutes(timeB);
    final endB = startB + durationB;
    return startA < endB && startB < endA;
  }

  /// Returns the first rule in [existingRules] that would overlap with
  /// a rule described by [time]/[durationMinutes]/[weekdays], or null
  /// if there's no conflict. Pass [excludeRuleId] when editing an
  /// existing rule so it doesn't "conflict" with itself.
  static ScheduleRule? findConflict({
    required String time,
    required int durationMinutes,
    required List<int> weekdays,
    required List<ScheduleRule> existingRules,
    String? excludeRuleId,
  }) {
    for (final rule in existingRules) {
      if (excludeRuleId != null && rule.id == excludeRuleId) continue;
      if (!rule.isActive) continue;
      if (!_weekdaysOverlap(rule.activeWeekdays, weekdays)) continue;
      if (_timesOverlap(
        rule.time,
        rule.durationMinutes,
        time,
        durationMinutes,
      )) {
        return rule;
      }
    }
    return null;
  }
}
