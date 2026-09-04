import '../database/db_helper.dart';
import '../utils/id_generator.dart';

/// Lets a missed day be excluded from streak-breaking, the way
/// Duolingo's "streak freeze" works — a limited, monthly resource,
/// not an unlimited escape hatch.
///
/// Deliberately kept simple: a freeze only ever affects
/// [DBHelper.getStreakStats]'s math (see there — a frozen day is
/// dropped from the completion map entirely, same treatment as a
/// natural rest day). It does NOT change the underlying task's own
/// `status` — a missed task stays visibly `missed` in the task list;
/// only the *streak count* forgives it. That distinction matters:
/// this is meant for "I was genuinely sick/traveling", not a way to
/// erase the historical record of what happened.
class StreakFreezeService {
  StreakFreezeService._internal();
  static final StreakFreezeService instance = StreakFreezeService._internal();

  final DBHelper _db = DBHelper.instance;

  /// How many freeze tokens each goal gets per calendar month. A
  /// fixed constant rather than a setting — keeping this un-configurable
  /// is what keeps it a meaningful limit instead of something the user
  /// just cranks up the first time they want to skip a day guilt-free.
  static const int monthlyAllowance = 2;

  Future<int> _usedThisMonth(String goalId) {
    return _db.countFreezesUsedInMonth(goalId, DateTime.now());
  }

  /// How many freeze tokens this goal has left this month (never
  /// negative, even if the allowance were ever lowered after some
  /// were already used).
  Future<int> remainingThisMonth(String goalId) async {
    final used = await _usedThisMonth(goalId);
    final remaining = monthlyAllowance - used;
    return remaining < 0 ? 0 : remaining;
  }

  /// Missed days (within the last two weeks, not already frozen) this
  /// goal could still apply a freeze to — what StreakFreezeSheet lists.
  Future<List<DateTime>> getFreezableMissedDates(String goalId) {
    return _db.getFreezableMissedDates(goalId);
  }

  /// Spends one freeze token on [date] for [goalId]. Callers should
  /// check [remainingThisMonth] > 0 first — this does not re-check the
  /// allowance itself, since StreakFreezeSheet already disables the
  /// action once the count hits zero and re-checking here would just
  /// duplicate that logic without adding safety (the DB's UNIQUE
  /// constraint on goalId+date is the actual backstop against
  /// accidentally double-spending on the same day).
  Future<void> freezeDay(String goalId, DateTime date) async {
    await _db.insertStreakFreeze(generateId(), goalId, date);
  }
}
