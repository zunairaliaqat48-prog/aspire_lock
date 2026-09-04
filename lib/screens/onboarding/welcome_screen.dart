import 'package:flutter/material.dart';

import '../../database/db_helper.dart';
import '../../constants/app_colors.dart';
import '../../widgets/primary_button.dart';
import 'permissions_screen.dart';

/// Shown exactly once, the very first time the app is opened — before
/// the user ever picks a goal category. Explains what the app does and
/// what permissions it will ask for (and why), so the camera/
/// notification prompts that follow don't come as a surprise.
/// [DBHelper.markOnboarded] is called once the user taps
/// through, so this screen never shows again on this device.
class WelcomeScreen extends StatefulWidget {
   WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  bool _continuing = false;

  // Drives the one-time staggered entrance: icon, title, subtitle, each
  // point, and the button all fade/slide in on a slight delay from one
  // another instead of popping in all at once.
  late final AnimationController _entranceController;

  // Separate, continuously-looping controller for the subtle "breathing"
  // pulse on the header icon — runs independently of (and keeps going
  // after) the one-shot entrance animation above.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration:  Duration(milliseconds: 900),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration:  Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// A fade + gentle upward slide for the element at [start]..[end] of
  /// the overall entrance timeline (0.0 to 1.0), so different elements
  /// visibly stagger in one after another rather than all at once.
  Widget _staggered({
    required double start,
    required double end,
    required Widget child,
  }) {
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin:  Offset(0, 0.12),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Future<void> _getStarted() async {
    setState(() => _continuing = true);
    await DBHelper.instance.markOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) =>  PermissionsScreen()),
    );
  }

  static const List<(IconData, String, String)> _points = [
    (
      Icons.track_changes,
      'Set a goal',
      'Pick a category — weight loss, study, business, or your own '
          'custom goal — and we\'ll draft a daily task schedule for it.',
    ),
    (
      Icons.lock_clock_outlined,
      'Stay accountable',
      'When a task\'s alarm fires, distracting apps you\'ve chosen get '
          'locked until you mark the task done — this needs the '
          'Accessibility permission to actually work.',
    ),
    (
      Icons.camera_alt_outlined,
      'Optional photo proof',
      'For tasks you mark as needing it, you\'ll take a quick photo to '
          'confirm you did it — this needs Camera access.',
    ),
    (
      Icons.notifications_active_outlined,
      'Timely alarms',
      'You\'ll get a full-screen alarm at each task\'s scheduled time — '
          'this needs Notification access to reach you reliably.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:  BoxDecoration(
          // Diagonal charcoal-to-warm-amber gradient for a more
          // energetic feel than the previous flat AppColors.primary.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              Color(0xFF241A0B), // warm amber-tinted charcoal
              AppColors.primary,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding:  EdgeInsets.fromLTRB(28, 20, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _staggered(
                  start: 0.0,
                  end: 0.4,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Soft glow behind the icon for extra energy.
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.accent.withValues(alpha: 0.25),
                              AppColors.accent.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                      ScaleTransition(
                        scale: _pulseScale,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child:  Icon(Icons.lock_clock_rounded,
                              color: AppColors.accent, size: 28),
                        ),
                      ),
                    ],
                  ),
                ),
                 SizedBox(height: 24),
                _staggered(
                  start: 0.1,
                  end: 0.5,
                  child:  Text(
                    'Welcome to Aspire Lock',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                 SizedBox(height: 10),
                _staggered(
                  start: 0.15,
                  end: 0.55,
                  child:  Text(
                    'A daily accountability system: set a goal, and we lock '
                    'the apps that distract you until you\'ve done the work.',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 15, height: 1.4),
                  ),
                ),
                 SizedBox(height: 32),
                Expanded(
                  child: ListView.separated(
                    itemCount: _points.length,
                    separatorBuilder: (_, __) =>  SizedBox(height: 22),
                    itemBuilder: (context, index) {
                      final point = _points[index];
                      // Each point starts slightly later than the one
                      // before it, so they visibly cascade in.
                      final start = 0.25 + (index * 0.12);
                      final end = (start + 0.35).clamp(0.0, 1.0);
                      return _staggered(
                        start: start.clamp(0.0, 1.0),
                        end: end,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(point.$1,
                                  color: AppColors.accent, size: 20),
                            ),
                             SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    point.$2,
                                    style:  TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                   SizedBox(height: 4),
                                  Text(
                                    point.$3,
                                    style:  TextStyle(
                                      color: Colors.white60,
                                      fontSize: 13.5,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                 SizedBox(height: 12),
                _staggered(
                  start: 0.75,
                  end: 1.0,
                  child: PrimaryButton(
                    label: 'Get Started',
                    isLoading: _continuing,
                    color: AppColors.accent,
                    onPressed: _getStarted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
