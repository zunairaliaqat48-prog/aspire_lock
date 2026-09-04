import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../models/task_model.dart';
import '../../database/db_helper.dart';
import '../../services/camera_proof_service.dart';
import '../../services/notification_service.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/primary_button.dart';
import 'task_celebration_screen.dart';

class TaskCompleteScreen extends StatefulWidget {
  final Task task;
   TaskCompleteScreen({super.key, required this.task});

  @override
  State<TaskCompleteScreen> createState() => _TaskCompleteScreenState();
}

class _TaskCompleteScreenState extends State<TaskCompleteScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializingCamera = false;
  bool _completing = false;
  String? _error;
  bool _cameraPermanentlyDenied = false;

  // True when availableCameras() came back empty — i.e. the device
  // genuinely has no camera hardware (iOS Simulator, some Android
  // emulators without a virtual camera configured). Distinct from a
  // permission problem: no amount of permission-granting fixes this.
  bool _noCameraHardware = false;

  // Set right after a photo is captured, while the user is reviewing
  // it (before it's actually saved as the task's proof). Null means
  // we're still showing the live camera preview / haven't captured yet.
  String? _capturedPath;
  bool _capturing = false;

  // The task can't actually be marked done until its full duration has
  // passed since the user tapped "Start Task" — see [Task.startedAt]
  // and DBHelper.markTaskStarted. Ticks down once a second; the
  // camera/complete UI stays hidden behind [_buildWaitingUI] the whole
  // time this is above zero, regardless of which completion path
  // (photo proof or plain "Mark as Done") the task uses.
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  late final DateTime _effectiveStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Normally this screen is only ever reached via
    // FullScreenAlarmScreen._startTask, which already set startedAt in
    // the DB before navigating here — so widget.task.startedAt should
    // already be non-null. The `?? DateTime.now()` fallback (and the
    // best-effort markTaskStarted call) only matters for some future
    // or debug path that reaches TaskCompleteScreen directly.
    _effectiveStart = widget.task.startedAt ?? DateTime.now();
    if (widget.task.startedAt == null) {
      DBHelper.instance.markTaskStarted(widget.task.id);
    }
    _startCountdown();

    if (widget.task.requiresPhotoProof) {
      _setupCamera();
    }
  }

  void _startCountdown() {
    // Deliberately NOT setState here — this runs synchronously from
    // initState, and calling setState during that phase (before the
    // first build has happened) throws a Flutter framework assertion.
    // Just assigning the field directly is enough — the first build
    // reads it normally.
    _remainingSeconds = _calculateRemaining();
    if (_remainingSeconds <= 0) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _calculateRemaining();
      if (!mounted) return;
      setState(() => _remainingSeconds = remaining);
      if (remaining <= 0) _countdownTimer?.cancel();
    });
  }

  int _calculateRemaining() {
    final totalSeconds = widget.task.durationMinutes * 60;
    final elapsed = DateTime.now().difference(_effectiveStart).inSeconds;
    final remaining = totalSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  String _formatRemaining(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    CameraProofService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the user just came back from the system Settings screen
    // (after we sent them there for a permanently-denied permission),
    // automatically retry instead of leaving them staring at the same
    // dead-end error.
    if (state == AppLifecycleState.resumed &&
        _controller == null &&
        widget.task.requiresPhotoProof) {
      _setupCamera();
    }
  }

  Future<void> _setupCamera() async {
    setState(() {
      _initializingCamera = true;
      _cameraPermanentlyDenied = false;
      _noCameraHardware = false;
    });

    // Check hardware presence first and separately from permission —
    // on a device/simulator with no camera at all, there's no point
    // even prompting for permission, and the error shown should say
    // "no camera" rather than the misleading "permission needed".
    final hasHardware = await CameraProofService.instance.hasCameraHardware();
    if (!hasHardware) {
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializingCamera = false;
        _noCameraHardware = true;
        _error = 'No camera was detected on this device. This is expected '
            'on the iOS Simulator (it has no camera hardware) — try again '
            'on a real iPhone.';
      });
      return;
    }

    final controller = await CameraProofService.instance.initializeCamera();
    if (!mounted) return;

    if (controller == null) {
      final permanentlyDenied =
          await CameraProofService.instance.isPermanentlyDenied();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializingCamera = false;
        _cameraPermanentlyDenied = permanentlyDenied;
        _error = permanentlyDenied
            ? 'Camera access is turned off for Aspire Lock. Enable it in '
                'Settings to confirm this task.'
            : 'Camera permission is needed to confirm this task.';
      });
      return;
    }

    setState(() {
      _controller = controller;
      _initializingCamera = false;
    });
  }

  Future<void> _completeWithoutProof() async {
    await _markComplete(null);
  }

  /// Takes the photo and switches to review mode — it is NOT saved as
  /// the task's proof yet. The user gets to look at it and either
  /// retake it or confirm it before [_confirmCapturedPhoto] actually
  /// marks the task complete with it.
  Future<void> _capturePhoto() async {
    setState(() => _capturing = true);
    final path = await CameraProofService.instance.captureProofPhoto(widget.task.id);
    if (!mounted) return;
    setState(() {
      _capturing = false;
      if (path == null) {
        _error = 'Could not capture photo. Please try again.';
      } else {
        _capturedPath = path;
      }
    });
  }

  /// Discards the just-captured photo and goes back to the live camera
  /// preview so the user can take another one.
  Future<void> _retakePhoto() async {
    final oldPath = _capturedPath;
    setState(() => _capturedPath = null);
    if (oldPath != null) {
      // Best-effort cleanup — don't leave rejected proof photos behind
      // on disk. Failure here doesn't matter to the user's flow.
      try {
        final file = File(oldPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _confirmCapturedPhoto() async {
    final path = _capturedPath;
    if (path == null) return;
    await _markComplete(path);
  }

  Future<void> _markComplete(String? proofPath) async {
    setState(() => _completing = true);

    await DBHelper.instance.updateTaskStatus(
      widget.task.id,
      status: TaskStatus.completed,
      proofImagePath: proofPath,
      completedAt: DateTime.now(),
    );

    await NotificationService.instance.cancelTaskAlarm(widget.task);

    // If that was the last unresolved task for today (across every
    // goal), the streak-risk reminder scheduled by HomeScreen._load
    // no longer has anything true left to warn about — cancel it now
    // rather than waiting for the user to reopen Home.
    final todayTasks = await DBHelper.instance.getTasksForDate(DateTime.now());
    final stillUnresolved = todayTasks.any((t) =>
        t.id != widget.task.id &&
        (t.status == TaskStatus.pending || t.status == TaskStatus.inProgress));
    if (!stillUnresolved) {
      await NotificationService.instance.cancelStreakRiskReminder();
    }

    await CameraProofService.instance.dispose();

    if (!mounted) return;

    // A brief celebration beat, then it auto-navigates itself back to
    // HomeScreen — see TaskCelebrationScreen for why.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => TaskCelebrationScreen(taskTitle: widget.task.title),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.task.title),
        ),
        body: SafeArea(
          child: Padding(
            padding:  EdgeInsets.all(24),
            child: _remainingSeconds > 0
                ? _buildWaitingUI()
                : widget.task.requiresPhotoProof
                    ? _buildProofUI()
                    : _buildSimpleCompleteUI(),
          ),
        ),
      ),
    );
  }

  /// Shown for the task's full [Task.durationMinutes] after it was
  /// started — this is what actually stops "Start Task" ->
  /// immediately submit a photo -> done from being possible. The
  /// camera (if this task needs proof) still initializes quietly in
  /// the background during this wait via [initState] calling
  /// [_setupCamera] unconditionally, so there's no extra delay once
  /// the countdown reaches zero.
  Widget _buildWaitingUI() {
    final totalSeconds = widget.task.durationMinutes * 60;
    final progress = totalSeconds == 0
        ? 1.0
        : (1 - (_remainingSeconds / totalSeconds)).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
              Text(
                _formatRemaining(_remainingSeconds),
                style: AppTextStyles.mono(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
         SizedBox(height: 28),
         Text(
          'Stay on task',
          textAlign: TextAlign.center,
          style: AppTextStyles.h3,
        ),
         SizedBox(height: 8),
        Text(
          'This task needs its full ${widget.task.durationMinutes} minutes '
          'before it can be marked done — that\'s the whole point.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMuted,
        ),
      ],
    );
  }

  Widget _buildSimpleCompleteUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child:  Icon(Icons.task_alt_rounded, size: 46, color: AppColors.success),
        ),
         SizedBox(height: 24),
         Text(
          'Great — did you complete this task?',
          textAlign: TextAlign.center,
          style: AppTextStyles.h3,
        ),
         SizedBox(height: 28),
        PrimaryButton(
          label: 'Mark as Done',
          isLoading: _completing,
          onPressed: _completeWithoutProof,
        ),
      ],
    );
  }

  Widget _buildProofUI() {
    if (_initializingCamera) {
      return  Center(child: CircularProgressIndicator());
    }

    // Review step: photo has been taken but not yet saved as the
    // task's proof — let the user confirm it or retake it.
    if (_capturedPath != null) {
      return _buildReviewUI(_capturedPath!);
    }

    if (_error != null || _controller == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           Icon(Icons.no_photography_outlined, size: 60, color: AppColors.textMuted),
           SizedBox(height: 16),
          Text(_error ?? 'Camera unavailable',
              textAlign: TextAlign.center, style: AppTextStyles.body),
           SizedBox(height: 20),
          PrimaryButton(
            label: _cameraPermanentlyDenied ? 'Open Settings' : 'Try Again',
            onPressed: _cameraPermanentlyDenied
                ? () => CameraProofService.instance.openSystemSettings()
                : _setupCamera,
          ),
          // DEBUG-ONLY escape hatch: kDebugMode is `false` in every
          // release/profile build, so this button (and the whole
          // branch) is compiled out of anything shipped to the App
          // Store — it exists purely so the rest of the app's flow can
          // be tested on the iOS Simulator, which has no camera
          // hardware and therefore can never satisfy this screen for
          // real. Real photo-proof behavior is untouched.
          if (kDebugMode && _noCameraHardware) ...[
             SizedBox(height: 12),
            TextButton(
              onPressed: _completing ? null : _completeWithoutProof,
              child:  Text(
                'Skip photo (debug/simulator only)',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      children: [
         Text(
          'Take a quick photo to confirm you completed this task.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
         SizedBox(height: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CameraPreview(_controller!),
          ),
        ),
         SizedBox(height: 20),
        PrimaryButton(
          label: 'Capture Photo',
          isLoading: _capturing,
          onPressed: _capturePhoto,
        ),
      ],
    );
  }

  Widget _buildReviewUI(String path) {
    return Column(
      children: [
         Text(
          'Looks good? Confirm to complete the task, or retake it.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
         SizedBox(height: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              File(path),
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
         SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Retake',
                outlined: true,
                isLoading: false,
                onPressed: _completing ? null : _retakePhoto,
              ),
            ),
             SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: 'Confirm & Complete',
                isLoading: _completing,
                onPressed: _confirmCapturedPhoto,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
