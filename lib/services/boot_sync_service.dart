import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../database/db_helper.dart';
import 'notification_service.dart';
import 'task_generation_service.dart';
import 'task_status_service.dart';

/// Runs the app's daily housekeeping in a background isolate,
/// including right after a device reboot:
///   1. Flags any overdue task as `missed` (see [TaskStatusService]).
///   2. Generates any missing daily tasks for active goals (see
///      [TaskGenerationService]).
///   3. Re-creates alarms for everything still pending.
///
/// Why alarm resync exists: `flutter_local_notifications` schedules
/// alarms via Android's AlarmManager, but Android WIPES all
/// AlarmManager entries on device reboot — the OS does not remember
/// them for you. So without this, a task alarm scheduled for
/// "tomorrow 7am" silently never fires if the phone restarts overnight.
///
/// The fix is to run this as the callback of an
/// `android_alarm_manager_plus` periodic alarm with
/// `rescheduleOnReboot: true`. That plugin's own native receiver
/// listens for BOOT_COMPLETED and reschedules *its* alarm automatically
/// — and when that alarm fires (right after boot, and then daily), it
/// runs this callback. This makes missed-task detection, "day 2
/// onward" task generation, and task alarms all durable across
/// reboots without needing any custom native code.
class BootSyncService {
  /// Entry point for the background isolate spawned by
  /// android_alarm_manager_plus. Must stay a static/top-level function
  /// and keep the `vm:entry-point` pragma, or it gets tree-shaken out
  /// of release builds and silently does nothing after reboot.
  @pragma('vm:entry-point')
  static Future<void> resyncPendingAlarms() async {
    // A background isolate has no existing Flutter binding of its own.
    WidgetsFlutterBinding.ensureInitialized();

    developer.log('[ALARM DEBUG] resyncPendingAlarms() started',
        name: 'AspireLockAlarms');
    try {
      // Mark overdue tasks missed first, so we don't waste effort
      // scheduling an alarm for something already given up on.
      final justMissed =
          await TaskStatusService.instance.markOverdueTasksAsMissed();
      for (final task in justMissed) {
        await NotificationService.instance.cancelTaskAlarm(task);
      }

      // Generate today's (and any missed) tasks, so the alarm pass
      // right after picks them up too.
      await TaskGenerationService.instance
          .generateMissingTasksForAllActiveGoals();

      final pendingTasks = await DBHelper.instance.getPendingUpcomingTasks();
      developer.log(
          '[ALARM DEBUG] resync found ${pendingTasks.length} pending '
          'task(s) to (re)schedule',
          name: 'AspireLockAlarms');
      for (final task in pendingTasks) {
        // scheduleTaskAlarm() already re-uses task.id.hashCode as the
        // notification id, so calling it again just overwrites the
        // previous (now-cleared) alarm rather than creating a duplicate.
        await NotificationService.instance.scheduleTaskAlarm(task);
      }
      await NotificationService.instance.logDiagnostics();
    } catch (e, st) {
      // Best-effort: a failure here shouldn't crash the background
      // isolate. The next periodic run (tomorrow, or next reboot)
      // will simply try again. Logged (rather than fully silent) so
      // this is visible instead of an invisible dead end.
      developer.log('[ALARM DEBUG] resyncPendingAlarms() FAILED — $e',
          name: 'AspireLockAlarms', error: e, stackTrace: st);
    }
  }
}
