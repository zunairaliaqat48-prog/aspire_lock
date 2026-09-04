import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../services/camera_proof_service.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/primary_button.dart';
import 'goal_category_screen.dart';

/// Shown once, right after [WelcomeScreen] and before goal setup —
/// asks for every permission Aspire Lock needs, each with its own
/// plain-language reason, instead of the app silently triggering
/// system dialogs at random points later on.
///
/// This replaces the old behavior where the notification/exact-alarm
/// permission dialog fired the instant the app process started (see
/// `NotificationService.init`), often before the user had even
/// finished reading the Welcome screen — a blind, unexplained prompt
/// that gets denied far more than one shown with context.
///
/// None of these are hard-blocking: the user can tap "Continue"
/// without granting anything and set up a goal anyway.
class PermissionsScreen extends StatefulWidget {
   PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _notificationsGranted = false;
  bool _cameraGranted = false;

  bool _requestingNotifications = false;
  bool _requestingCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the user coming back from the system Settings screen
    // (e.g. after a permanently-denied camera permission), so the
    // card updates without a manual refresh.
    if (state == AppLifecycleState.resumed) {
      _refreshStatuses();
    }
  }

  Future<void> _refreshStatuses() async {
    final notifications = await NotificationService.instance
        .areNotificationsEnabled();
    final camera = await CameraProofService.instance.hasPermission();
    if (!mounted) return;
    setState(() {
      _notificationsGranted = notifications;
      _cameraGranted = camera;
    });
  }

  Future<void> _requestNotifications() async {
    setState(() => _requestingNotifications = true);
    final granted =
        await NotificationService.instance.requestAlarmPermissions();
    if (!mounted) return;
    setState(() {
      _notificationsGranted = granted;
      _requestingNotifications = false;
    });
  }

  Future<void> _requestCamera() async {
    setState(() => _requestingCamera = true);
    final granted = await CameraProofService.instance.requestPermission();
    if (!mounted) return;
    setState(() {
      _cameraGranted = granted;
      _requestingCamera = false;
    });
  }

  void _continue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) =>  GoalCategoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding:  EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child:  Icon(Icons.shield_outlined,
                    color: AppColors.accent, size: 22),
              ),
               SizedBox(height: 20),
               Text('A few permissions', style: AppTextStyles.h1),
               SizedBox(height: 6),
               Text(
                'Aspire Lock only works if it can actually reach you and '
                'enforce your app locks. You can grant these now, or later '
                'from Settings — but nothing below is required to continue.',
                style: AppTextStyles.bodyMuted,
              ),
               SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _PermissionCard(
                      icon: Icons.notifications_active_outlined,
                      title: 'Alarms & Notifications',
                      description:
                          'Needed for the full-screen alarm to fire at each '
                          'task\'s scheduled time — without it, tasks '
                          'silently never remind you.',
                      granted: _notificationsGranted,
                      loading: _requestingNotifications,
                      onEnable: _requestNotifications,
                    ),
                     SizedBox(height: 14),
                    _PermissionCard(
                      icon: Icons.camera_alt_outlined,
                      title: 'Camera',
                      description:
                          'Only used if you mark a task as needing photo '
                          'proof. You can skip this and grant it later, '
                          'right when a task actually needs it.',
                      granted: _cameraGranted,
                      loading: _requestingCamera,
                      onEnable: _requestCamera,
                    ),
                  ],
                ),
              ),
               SizedBox(height: 8),
              PrimaryButton(
                label: 'Continue',
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool loading;
  final VoidCallback onEnable;
  final String enableLabel;
  final bool important;

   _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.loading,
    required this.onEnable,
    this.enableLabel = 'Enable',
    this.important = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:  EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted
              ? AppColors.success.withValues(alpha: 0.4)
              : (important
                  ? AppColors.warning.withValues(alpha: 0.4)
                  : AppColors.divider),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
           SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: AppTextStyles.h3),
                    ),
                    if (granted)
                       Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 20),
                  ],
                ),
                 SizedBox(height: 4),
                Text(description, style: AppTextStyles.bodyMuted),
                if (!granted) ...[
                   SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: loading ? null : onEnable,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: important
                              ? AppColors.warning
                              : AppColors.divider,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding:
                             EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: loading
                          ?  SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              enableLabel,
                              style:  TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
