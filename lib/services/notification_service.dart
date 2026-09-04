import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../models/task_model.dart';
import '../database/db_helper.dart';
import '../utils/navigation_service.dart';
import '../utils/notification_id.dart';
import '../screens/alarm/full_screen_alarm_screen.dart';

/// Handles scheduling and firing of task alarms.
///
/// Uses full-screen intent notifications so the alarm behaves like a
/// real alarm clock (shows over lock screen, high priority, insistent).
///
/// Also wires up notification TAP handling so that tapping the fired
/// alarm — whether the app was in the background or fully closed —
/// opens the FullScreenAlarmScreen for that exact task.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Small native bridge exposed by MainActivity — just used to fetch
  // the device's real IANA timezone id (see MainActivity.kt
  // "getDeviceTimeZone").
  static const MethodChannel _platformChannel = MethodChannel(
    'com.aspirelock/native',
  );

  bool _initialized = false;

  /// Logs to both `print()` (always visible in `flutter run`'s plain
  /// terminal output — some setups don't surface `developer.log` there
  /// at all, only in DevTools' Logging view) and `developer.log`
  /// (visible in DevTools, filterable by name). Use this instead of
  /// calling `developer.log` directly for anything you actually need
  /// to SEE while debugging alarms.
  void _debugLog(String message) {
    // ignore: avoid_print
    print('[AspireLockAlarms] $message');
    developer.log(message, name: 'AspireLockAlarms');
  }

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    await _setDeviceLocalTimeZone();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Mirrors the Android philosophy below: don't let the plugin fire
    // the system permission prompt during init() (which runs on every
    // cold start via scheduleTaskAlarm/etc.) — request*Permission is
    // false here on purpose. The actual prompt is triggered explicitly
    // by requestAlarmPermissions() once the user has seen why, from
    // screens/onboarding/permissions_screen.dart.
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      // Called when the user taps the notification while the app is
      // already running (foreground or background, but process alive).
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // NOTE: deliberately NOT requesting the notification / exact-alarm
    // permissions here anymore. This used to fire the system
    // permission dialog the instant the app process started — often
    // before the user had even seen the Welcome screen, let alone any
    // explanation of why Aspire Lock needs it. A blind, unexplained
    // permission prompt gets denied far more often than one shown
    // with context. See [requestAlarmPermissions] and
    // `screens/onboarding/permissions_screen.dart`, which now owns
    // triggering this at the right point in onboarding.
    _initialized = true;
  }

  /// Points `tz.local` at the device's real timezone (e.g.
  /// "Asia/Karachi") instead of the `timezone` package's default of
  /// UTC. Without this, every alarm scheduled via
  /// `tz.TZDateTime(tz.local, ...)` was silently built in UTC while
  /// the picked hour/minute were the user's *local* wall-clock time —
  /// so for any timezone ahead of UTC (like PKT, UTC+5), the
  /// resulting instant was always in the past by the UTC offset, and
  /// `scheduleTaskAlarm`'s "already passed" check skipped it every
  /// single time. This is why alarms never fired at all, regardless
  /// of permissions or battery settings.
  Future<void> _setDeviceLocalTimeZone() async {
    try {
      final name =
          await _platformChannel.invokeMethod<String>('getDeviceTimeZone');
      if (name != null) {
        tz.setLocalLocation(tz.getLocation(name));
        _debugLog('[ALARM DEBUG] Device timezone set to "$name".');
      }
    } catch (e) {
      // Fall back to whatever tz.local already is (UTC) rather than
      // crashing startup over this — logged so it's visible if it
      // ever happens instead of silently mis-scheduling again.
      _debugLog(
        '[ALARM DEBUG] Could not read device timezone, alarms may be '
        'off — $e',
      );
    }
  }

  /// Whether Android's runtime notification permission is currently
  /// granted. Safe to call at any time (does not prompt).
  Future<bool> areNotificationsEnabled() async {
    if (Platform.isIOS) {
      final options = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.checkPermissions();
      return options?.isEnabled ?? false;
    }
    final enabled = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    return enabled ?? false;
  }

  /// Actually shows the system permission dialogs for notifications
  /// (Android 13+) and exact alarms (Android 12+). Call this from a
  /// screen that has already explained *why* — never blindly at app
  /// startup. Returns the resulting notifications-enabled state.
  Future<bool> requestAlarmPermissions() async {
    await init();

    if (Platform.isIOS) {
      // iOS has no "exact alarm" concept to request separately — a
      // single alert/badge/sound prompt covers everything local
      // notifications need here.
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return areNotificationsEnabled();
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();

    return areNotificationsEnabled();
  }

  /// Call this once, after the first frame is drawn (see main.dart),
  /// to handle the case where the app was fully closed and got
  /// launched by the user tapping the alarm notification.
  Future<void> handleColdStartLaunch() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return;

    final payload = details.notificationResponse?.payload;
    if (payload != null) {
      await _openAlarmScreenForTaskId(payload);
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    final taskId = response.payload;
    if (taskId != null) {
      _openAlarmScreenForTaskId(taskId);
    }
  }

  Future<void> _openAlarmScreenForTaskId(String taskId) async {
    final task = await DBHelper.instance.getTaskById(taskId);
    if (task == null) return;
    if (task.status == TaskStatus.completed) return;

    // Small delay ensures the navigator is mounted, especially on cold start.
    await Future.delayed(const Duration(milliseconds: 300));

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => FullScreenAlarmScreen(task: task)),
    );
  }

  NotificationDetails _alarmDetails() {
    const androidDetails = AndroidNotificationDetails(
      'task_alarm_channel',
      'Task Alarms',
      channelDescription: 'Strict alarms for scheduled goal tasks',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true, // shows full-screen even on lock screen
      category: AndroidNotificationCategory.alarm,
      ongoing: true, // cannot be swiped away easily
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    );
    // iOS has no fullScreenIntent/ongoing equivalent — the closest
    // available without Apple's special "critical alerts" entitlement
    // is timeSensitive, which is allowed to break through Focus modes
    // and shows even when the phone is locked.
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // presentAlert alone is a legacy iOS <14 flag that modern iOS
      // versions (14+) ignore — Apple replaced it with separate
      // banner/list controls. Without these two, a foreground alarm
      // was being scheduled successfully (confirmed via
      // pendingNotificationRequests) but iOS silently showed nothing
      // at all when it fired, since presentBanner defaults differ by
      // plugin version and can't be relied on unset.
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  /// Schedules a one-time alarm notification for a given Task.
  /// The task's [Task.id] is attached as the notification payload so
  /// tapping it can look the exact task back up.
  Future<void> scheduleTaskAlarm(Task task) async {
    await init();

    _debugLog(
      '[ALARM DEBUG] scheduleTaskAlarm called for "${task.title}" '
      '(scheduledTime: ${task.scheduledTime}, date: ${task.scheduledDate}, '
      'status: ${task.status}).',
    );

    final timeParts = task.scheduledTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);

    final scheduledDate = tz.TZDateTime(
      tz.local,
      task.scheduledDate.year,
      task.scheduledDate.month,
      task.scheduledDate.day,
      hour,
      minute,
    );

    // Skip scheduling if the time has already passed for today.
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
      _debugLog(
        '[ALARM DEBUG] SKIPPED "${task.title}" — scheduled time '
        '$scheduledDate is already in the past (now: '
        '${tz.TZDateTime.now(tz.local)}, tz.local: ${tz.local.name}).',
      );
      return;
    }

    try {
      await _plugin.zonedSchedule(
        notificationIdForTaskId(task.id),
        'Time for: ${task.title}',
        'Tap to start — complete this task to unlock your apps.',
        scheduledDate,
        _alarmDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
        payload: task.id,
      );
      _debugLog(
        '[ALARM DEBUG] SCHEDULED OK — "${task.title}" '
        '(id ${notificationIdForTaskId(task.id)}) for $scheduledDate '
        '(tz.local: ${tz.local.name}).',
      );
    } catch (e, st) {
      _debugLog(
        '[ALARM DEBUG] FAILED to schedule "${task.title}" for '
        '$scheduledDate — $e\n$st',
      );
      // Re-throw is deliberately NOT done here — a scheduling failure
      // for one task should not abort the rest of the batch (see
      // scheduleAllTasks) or crash the caller. The log line above is
      // the only way to see this happened; check the "AspireLockAlarms"
      // tag in Logcat / the Android Studio Run console.
    }
  }

  /// Reschedules a task's alarm to fire again [minutes] from now,
  /// using the exact same notification id as the original (derived
  /// from the task id), so it naturally replaces/supersedes it rather
  /// than stacking a second alarm for the same task.
  Future<void> snoozeTaskAlarm(Task task, {int minutes = 5}) async {
    await init();

    final snoozedTime =
        tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));

    await _plugin.zonedSchedule(
      notificationIdForTaskId(task.id),
      'Time for: ${task.title}',
      'Snoozed — tap to start — complete this task to unlock your apps.',
      snoozedTime,
      _alarmDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
      payload: task.id,
    );
  }

  /// Schedules alarms for a full list of tasks (e.g. a day's schedule).
  Future<void> scheduleAllTasks(List<Task> tasks) async {
    _debugLog(
      '[ALARM DEBUG] scheduleAllTasks called with ${tasks.length} task(s).',
    );
    for (final task in tasks) {
      await scheduleTaskAlarm(task);
    }
    await logDiagnostics();
  }

  /// TEMPORARY DEBUG HELPER — prints (via `developer.log`, tag
  /// "AspireLockAlarms") exactly what Android currently has
  /// registered, plus the two permissions alarms depend on. This is
  /// the ground truth: if a task you expect to see isn't in this
  /// list, the alarm was never actually scheduled with the OS (and
  /// the reason should already be in an earlier "[ALARM DEBUG]" log
  /// line above it, or in this same block below). If it IS in this
  /// list but still never fires, the cause is outside the app (OEM
  /// battery/autostart restrictions killing the alarm before it can
  /// deliver — common on Vivo/Xiaomi/Oppo).
  ///
  /// Safe to leave in during development; remove once alarms are
  /// confirmed reliable, since polling pendingNotificationRequests()
  /// has a small cost.
  Future<void> logDiagnostics() async {
    final notificationsEnabled = await areNotificationsEnabled();
    final pending = await _plugin.pendingNotificationRequests();

    final buffer = StringBuffer()
      ..writeln('[ALARM DEBUG] ---- diagnostics ----')
      ..writeln('[ALARM DEBUG] Notifications permission enabled: '
          '$notificationsEnabled')
      ..writeln('[ALARM DEBUG] Pending alarms registered with Android: '
          '${pending.length}');
    for (final p in pending) {
      buffer.writeln('[ALARM DEBUG]   - id=${p.id} title="${p.title}" '
          'payload=${p.payload}');
    }
    buffer.write('[ALARM DEBUG] ---- end diagnostics ----');

    // Line-by-line so it isn't collapsed/truncated by the terminal.
    for (final line in buffer.toString().split('\n')) {
      // ignore: avoid_print
      print('[AspireLockAlarms] $line');
    }
    developer.log(buffer.toString(), name: 'AspireLockAlarms');
  }

  /// Cancels the alarm for a specific task (e.g. once completed).
  Future<void> cancelTaskAlarm(Task task) async {
    await _plugin.cancel(notificationIdForTaskId(task.id));
  }

  /// Cancels every scheduled alarm.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ---------------- STREAK-AT-RISK REMINDER ----------------

  // A fixed id, well outside the range notificationIdForTaskId's FNV
  // hash can ever produce for a real task (that's masked to 31 bits
  // starting from a completely different seed), so this can never
  // collide with — or be silently overwritten/cancelled by — a task
  // alarm.
  static const int _streakRiskNotificationId = 999999001;

  /// Schedules a single evening reminder warning the user their streak
  /// is still at risk, IF they haven't finished today's tasks by then.
  /// Deliberately app-wide rather than naming which goal/task is
  /// unfinished — flutter_local_notifications can't re-check the
  /// database at the moment it actually fires, so the message has to
  /// be written to be true regardless of *which* task ends up being
  /// the reason. [cancelStreakRiskReminder] is what actually prevents
  /// this from firing once nothing is unfinished anymore — see
  /// callers in TaskCompleteScreen / TaskStatusService.
  ///
  /// [hour]/[minute] default to 9:00 PM local time — deliberately late
  /// enough that most people have had their whole day to act, but
  /// early enough to still be able to do something about it.
  Future<void> scheduleStreakRiskReminder({int hour = 21, int minute = 0}) async {
    await init();

    final now = tz.TZDateTime.now(tz.local);
    var fireTime =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    // If it's already past the reminder hour today, there's no "this
    // evening" left to warn about — skip rather than firing it
    // instantly or tomorrow, either of which would be misleading.
    if (fireTime.isBefore(now)) return;

    await _plugin.zonedSchedule(
      _streakRiskNotificationId,
      '🔥 Your streak is still at risk',
      'You still have unfinished tasks today — a few minutes now keeps '
          'your streak alive.',
      fireTime,
      _alarmDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }

  /// Cancels today's streak-risk reminder — call this the moment every
  /// task for today ends up resolved (completed or missed), so the
  /// user isn't warned about a streak that's no longer in danger of
  /// breaking for a reason that's already settled one way or the
  /// other.
  Future<void> cancelStreakRiskReminder() async {
    await _plugin.cancel(_streakRiskNotificationId);
  }
}
