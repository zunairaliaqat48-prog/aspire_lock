import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/selected_goal_controller.dart';
import 'progress_dashboard_screen.dart';

/// Bottom-nav "Dashboard" tab. Just follows whichever goal is
/// currently selected on the Home tab (via [SelectedGoalController])
/// and shows that goal's [ProgressDashboardScreen] — so switching the
/// goal chip on Home also updates what this tab shows, without this
/// tab needing to load goals itself.
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SelectedGoalController.instance,
      builder: (context, _) {
        final goal = SelectedGoalController.instance.goal;
        if (goal == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Dashboard')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded,
                        size: 40, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'Add a goal on the Home tab to see your progress here.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMuted,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        // key: goal.id forces a clean rebuild (fresh state/data load)
        // when the selected goal actually changes, instead of reusing
        // stale State from the previous goal's dashboard.
        return ProgressDashboardScreen(key: ValueKey(goal.id), goal: goal);
      },
    );
  }
}
