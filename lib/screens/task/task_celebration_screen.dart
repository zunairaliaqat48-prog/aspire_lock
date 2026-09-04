import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../main_nav_screen.dart';

/// Brief, self-dismissing celebration shown right after a task is
/// marked complete — a scale/fade-in checkmark plus a short haptic
/// buzz, then it auto-navigates back to [HomeScreen].
///
/// This exists purely for the "reward" moment: completing a task used
/// to drop the user straight back onto the home list with zero
/// acknowledgement, which is a flat, unrewarding feeling for an app
/// whose entire point is building a habit. A couple hundred
/// milliseconds of positive feedback here costs nothing and matters
/// a lot for how "done" actually feels.
class TaskCelebrationScreen extends StatefulWidget {
  final String taskTitle;

  const TaskCelebrationScreen({super.key, required this.taskTitle});

  @override
  State<TaskCelebrationScreen> createState() => _TaskCelebrationScreenState();
}

class _TaskCelebrationScreenState extends State<TaskCelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  static const Duration _totalVisibleDuration = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();

    HapticFeedback.mediumImpact();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _controller.forward();

    Future.delayed(_totalVisibleDuration, () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 58,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text('Task Complete', style: AppTextStyles.h2),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.taskTitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMuted,
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
