// The old default test here referenced a `MyApp` class that doesn't
// exist in this project (the app's root widget is `AspireLockApp`),
// so `flutter test` failed immediately without exercising any real
// app code.
//
// A full widget test of AspireLockApp isn't a good fit here yet
// either — its initState kicks off platform-channel calls (alarms,
// notifications, native app-lock bridge) that aren't mocked in a
// plain `flutter test` environment. Until those are wrapped behind
// fakes/mocks, this focuses on real, deterministic business logic
// that has zero platform dependency: ScheduleRuleEngine, which turns
// a goal's recurring ScheduleRules into concrete Task rows for a
// given day.

import 'package:flutter_test/flutter_test.dart';
import 'package:aspire_lock/models/schedule_model.dart';
import 'package:aspire_lock/services/ai_schedule_service.dart';

void main() {
  group('ScheduleRuleEngine.generateTasksFromRules', () {
    final engine = ScheduleRuleEngine();

    ScheduleRule buildRule({
      List<int> activeWeekdays = const [1, 2, 3, 4, 5, 6, 7],
      bool isActive = true,
    }) {
      return ScheduleRule(
        id: 'rule-1',
        goalId: 'goal-1',
        taskTitle: 'Morning run',
        time: '07:00',
        durationMinutes: 30,
        activeWeekdays: activeWeekdays,
        isActive: isActive,
      );
    }

    test('generates a task when the weekday matches', () {
      // 2024-01-01 was a Monday (weekday == 1).
      final monday = DateTime(2024, 1, 1);
      final tasks = engine.generateTasksFromRules(
        'goal-1',
        [buildRule(activeWeekdays: const [1])],
        monday,
      );

      expect(tasks, hasLength(1));
      expect(tasks.first.goalId, 'goal-1');
      expect(tasks.first.title, 'Morning run');
      expect(tasks.first.scheduledTime, '07:00');
    });

    test('skips a rule whose active weekdays exclude the date', () {
      // 2024-01-02 was a Tuesday (weekday == 2).
      final tuesday = DateTime(2024, 1, 2);
      final tasks = engine.generateTasksFromRules(
        'goal-1',
        [buildRule(activeWeekdays: const [1])], // Monday only
        tuesday,
      );

      expect(tasks, isEmpty);
    });

    test('skips an inactive rule even on a matching weekday', () {
      final monday = DateTime(2024, 1, 1);
      final tasks = engine.generateTasksFromRules(
        'goal-1',
        [buildRule(activeWeekdays: const [1], isActive: false)],
        monday,
      );

      expect(tasks, isEmpty);
    });
  });
}
