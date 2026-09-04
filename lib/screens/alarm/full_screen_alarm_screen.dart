import 'package:flutter/material.dart';

import '../../models/task_model.dart';
import '../../models/task_snooze_model.dart';
import '../../services/notification_service.dart';
import '../../database/db_helper.dart';
import '../../utils/id_generator.dart';
import '../../constants/app_colors.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/snooze_reason_sheet.dart';
import '../task/task_complete_screen.dart';

/// This screen simulates the "alarm firing" moment: it takes over the
/// full screen and cannot be dismissed with the back button, matching
/// the strict/insistent alarm behaviour described in the app flow.
class FullScreenAlarmScreen extends StatefulWidget {
  final Task task;
   FullScreenAlarmScreen({super.key, required this.task});

  @override
  State<FullScreenAlarmScreen> createState() => _FullScreenAlarmScreenState();
}

class _FullScreenAlarmScreenState extends State<FullScreenAlarmScreen> {
  static const int _maxSnoozes = 3;
  static const int _snoozeMinutes = 5;

  bool _snoozing = false;
  late int _snoozeCount;

  @override
  void initState() {
    super.initState();
    _snoozeCount = widget.task.snoozeCount;
  }

  /// Marks the task as started (setting [Task.startedAt] the FIRST
  /// time only — see [DBHelper.markTaskStarted]) before handing off to
  /// TaskCompleteScreen, which is what actually enforces the
  /// completion countdown against that timestamp. Re-fetches the task
  /// afterward rather than passing widget.task straight through, since
  /// widget.task was built before startedAt existed and TaskComplete
  /// Screen needs the real value to compute the countdown correctly.
  Future<void> _startTask() async {
    await DBHelper.instance.markTaskStarted(widget.task.id);
    final freshTask =
        await DBHelper.instance.getTaskById(widget.task.id) ?? widget.task;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TaskCompleteScreen(task: freshTask)),
    );
  }

  bool get _canSnooze => _snoozeCount < _maxSnoozes;

  /// Requires a typed reason (via [SnoozeReasonSheet]) before pushing
  /// the alarm back by [_snoozeMinutes]: reschedules the notification,
  /// logs the reason, and leaves this screen — it'll reopen
  /// automatically when the snoozed alarm fires.
  Future<void> _snooze() async {
    if (!_canSnooze || _snoozing) return;

    final snoozesLeft = _maxSnoozes - _snoozeCount;
    final reason = await SnoozeReasonSheet.show(context, snoozesLeft: snoozesLeft);
    if (reason == null || !mounted) return;

    setState(() => _snoozing = true);

    final newCount =
        await DBHelper.instance.incrementSnoozeCount(widget.task.id);
    await DBHelper.instance.insertTaskSnooze(TaskSnoozeLog(
      id: generateId(),
      taskId: widget.task.id,
      goalId: widget.task.goalId,
      reason: reason,
      snoozedAt: DateTime.now(),
    ));
    await NotificationService.instance
        .snoozeTaskAlarm(widget.task, minutes: _snoozeMinutes);

    if (!mounted) return;
    setState(() {
      _snoozeCount = newCount;
      _snoozing = false;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final snoozesLeft = _maxSnoozes - _snoozeCount;

    return PopScope(
      // Blocks the Android back button/gesture — the alarm cannot be
      // dismissed without starting the task.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Padding(
            padding:  EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child:  Icon(Icons.alarm_rounded,
                      color: AppColors.accent, size: 54),
                ),
                 SizedBox(height: 28),
                 Text(
                  'TIME TO FOCUS',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                 SizedBox(height: 10),
                Text(
                  widget.task.title,
                  textAlign: TextAlign.center,
                  style:  TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                 SizedBox(height: 12),
                Text(
                  '${widget.task.scheduledTime} · ${widget.task.durationMinutes} min',
                  style:  TextStyle(color: Colors.white54, fontSize: 15),
                ),
                 SizedBox(height: 36),
                Text(
                  widget.task.requiresPhotoProof
                      ? 'You\'ll need to confirm with a quick photo once done.'
                      : 'Mark this done once you\'ve completed it.',
                  textAlign: TextAlign.center,
                  style:  TextStyle(color: Colors.white54, height: 1.4),
                ),
                 SizedBox(height: 30),
                PrimaryButton(
                  label: 'Start Task',
                  onPressed: _startTask,
                  color: AppColors.accent,
                ),
                 SizedBox(height: 14),
                if (_canSnooze)
                  TextButton.icon(
                    onPressed: _snoozing ? null : _snooze,
                    icon: _snoozing
                        ?  SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          )
                        :  Icon(Icons.snooze_rounded,
                            color: Colors.white54, size: 20),
                    label: Text(
                      'Snooze $_snoozeMinutes min '
                      '($snoozesLeft left)',
                      style:  TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                   Text(
                    'No more snoozes left for this task',
                    style: TextStyle(color: Colors.white30, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
