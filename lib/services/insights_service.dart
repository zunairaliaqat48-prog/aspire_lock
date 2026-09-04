import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../models/task_model.dart';

/// On-device statistical insights — the "smart" part of scheduling
/// without calling out to any external/third-party AI service.
///
/// Everything here is plain arithmetic over the goal's own local
/// `tasks` history (see [DBHelper.getHourlyCompletionStats]): which
/// hour of the day this goal's tasks tend to actually get completed
/// at, versus missed. No network call, no API key, no data ever
/// leaves the device — this is deliberate, not a placeholder for a
/// future API integration.
class InsightsService {
  InsightsService._internal();
  static final InsightsService instance = InsightsService._internal();

  final DBHelper _db = DBHelper.instance;

  /// Below this many resolved (completed or missed) tasks in an hour
  /// bucket, that hour's rate is too noisy to call a "best hour" —
  /// one lucky task at 3 AM shouldn't get suggested as a pattern.
  static const int _minSampleSize = 3;

  /// Returns up to [limit] hours (0–23) with the highest completion
  /// rate for this goal, each hour needing at least [_minSampleSize]
  /// resolved tasks to qualify. Empty list if there isn't enough
  /// history yet.
  Future<List<HourlyCompletionStat>> getBestHours(
    String goalId, {
    int limit = 2,
  }) async {
    final hourly = await _db.getHourlyCompletionStats(goalId);
    final qualifying =
        hourly.where((h) => h.total >= _minSampleSize).toList();
    qualifying.sort((a, b) => b.rate.compareTo(a.rate));
    return qualifying.take(limit).toList();
  }

  /// A single best hour, as a [TimeOfDay] — used to pre-fill the time
  /// picker when the user adds a new task, so the schedule they build
  /// nudges toward when they actually tend to follow through. Null if
  /// there isn't enough history yet (a brand-new goal, for instance).
  Future<TimeOfDay?> suggestedTimeOfDay(String goalId) async {
    final best = await getBestHours(goalId, limit: 1);
    if (best.isEmpty) return null;
    return TimeOfDay(hour: best.first.hour, minute: 0);
  }

  /// A ready-to-display sentence summarizing the goal's best hour(s),
  /// or null if there isn't enough resolved-task history yet to say
  /// anything meaningful. Used on the dashboard.
  Future<String?> getBestHoursMessage(String goalId) async {
    final best = await getBestHours(goalId, limit: 1);
    if (best.isEmpty) return null;
    final stat = best.first;
    final pct = (stat.rate * 100).round();
    return "You're most consistent around ${_formatHourRange(stat.hour)} "
        '($pct% completion across ${stat.total} tasks).';
  }

  String _formatHourRange(int hour) {
    String label(int h) {
      final period = h >= 12 ? 'PM' : 'AM';
      final display = h % 12 == 0 ? 12 : h % 12;
      return '$display $period';
    }

    return '${label(hour)} – ${label((hour + 1) % 24)}';
  }
}
