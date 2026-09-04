import 'package:flutter/foundation.dart';

import '../models/goal_model.dart';

/// Tiny shared source of truth for "which goal is currently selected"
/// in the Home tab's goal switcher — lets the bottom-nav Dashboard tab
/// show stats for the same goal the user has picked, without a full
/// state-management rewrite. HomeScreen remains the only thing that
/// actually loads goals from the database; this just mirrors its
/// current selection so other tabs can read it.
class SelectedGoalController extends ChangeNotifier {
  SelectedGoalController._internal();
  static final SelectedGoalController instance =
      SelectedGoalController._internal();

  Goal? _goal;
  Goal? get goal => _goal;

  void set(Goal? goal) {
    if (_goal?.id == goal?.id) return;
    _goal = goal;
    notifyListeners();
  }
}
