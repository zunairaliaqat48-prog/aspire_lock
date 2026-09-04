import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'home_screen.dart';
import 'dashboard/dashboard_tab.dart';
import 'goal/achievements_screen.dart';
import 'settings/settings_screen.dart';
import 'onboarding/goal_category_screen.dart';

/// The app's actual root screen once onboarding is done. Previously
/// Home, Dashboard, Achievements, and Settings were four separate
/// full-screen pushes stacked behind a row of small icon buttons —
/// this instead makes them proper tabs behind a bottom navigation
/// bar, which is what those four icons were really standing in for.
///
/// Every place in the app that used to navigate to [HomeScreen] as
/// "go back to the main screen" now goes to [MainNavScreen] instead,
/// so the bottom nav bar is always present once the user is past
/// onboarding.
///
/// "Add Goal" used to live as a small icon inside Home's own header.
/// It's now a prominent, centrally-docked FAB notched into this bar
/// instead — visible (and reachable in one tap) from every tab, not
/// just Home. No refresh plumbing is needed after it returns: the
/// goal-creation flow always ends by calling `pushAndRemoveUntil` back
/// to a brand new [MainNavScreen] (see PhaseListScreen._continue), so
/// Home reloads fresh on its own; a plain `push`/pop (user backs out
/// without finishing) leaves nothing to refresh in the first place.
class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _index = 0;

  // IndexedStack keeps all four tabs alive at once (rather than
  // rebuilding from scratch on every tap), so e.g. Home's loaded task
  // list or Dashboard's scroll position survive switching tabs and
  // coming back.
  static final List<Widget> _tabs = [
    HomeScreen(),
    const DashboardTab(),
    const AchievementsScreen(),
    SettingsScreen(),
  ];

  void _addGoal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GoalCategoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButton: FloatingActionButton(
        onPressed: _addGoal,
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 3,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Home',
              index: 0,
            ),
            _navItem(
              icon: Icons.bar_chart_outlined,
              selectedIcon: Icons.bar_chart_rounded,
              label: 'Dashboard',
              index: 1,
            ),
            // Empty gap the FAB notch sits in — keeps the two left
            // items and two right items evenly spaced around it.
            const SizedBox(width: 56),
            _navItem(
              icon: Icons.emoji_events_outlined,
              selectedIcon: Icons.emoji_events_rounded,
              label: 'Achievements',
              index: 2,
            ),
            _navItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Settings',
              index: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
  }) {
    final selected = _index == index;
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
