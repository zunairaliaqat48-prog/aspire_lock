import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Dependency-free bar chart showing tasks completed per day over the
/// last 7 days. [values] should have 7 entries (Mon..Sun), each = the
/// number of tasks completed that day. Set [todayIndex] (0 = Monday)
/// to highlight which bar is "today", if known.
///
/// Bars grow in with a short entrance animation on first build instead
/// of appearing instantly — a small touch, but a static bar chart on a
/// progress screen reads as "just a report"; a chart that visibly
/// fills in reads as "your progress, happening".
class StreakChart extends StatelessWidget {
  final List<int> values;
  final List<String> labels;
  final int? todayIndex;

  const StreakChart({
    super.key,
    required this.values,
    this.labels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    this.todayIndex,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = values.isEmpty
        ? 1
        : values.reduce((a, b) => a > b ? a : b).clamp(1, 999);

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(values.length, (i) {
          final heightFraction = (values[i] / maxVal).clamp(0.05, 1.0);
          final isToday = todayIndex == i;
          final hasValue = values[i] > 0;

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${values[i]}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isToday ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: heightFraction),
                duration: Duration(milliseconds: 500 + (i * 60)),
                curve: Curves.easeOutCubic,
                builder: (context, animatedFraction, _) {
                  return Container(
                    width: 24,
                    height: 96 * animatedFraction,
                    decoration: BoxDecoration(
                      gradient: hasValue
                          ? LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                AppColors.accent,
                                AppColors.accentLight,
                              ],
                            )
                          : null,
                      color: hasValue ? null : AppColors.divider,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: hasValue && isToday
                          ? [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Container(
                width: 22,
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: isToday
                    ? BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      )
                    : null,
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isToday ? AppColors.accent : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
