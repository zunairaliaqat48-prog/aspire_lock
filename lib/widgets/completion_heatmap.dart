import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// A GitHub-contributions-style grid of the last [days] days, one
/// square per day, shaded by how many tasks were completed that day.
///
/// Laid out column-by-column (each column = one week, Monday at the
/// top) so it reads left-to-right as "oldest -> today", matching the
/// convention people already recognize from GitHub/Duolingo-style
/// streak grids.
class CompletionHeatmap extends StatelessWidget {
  /// Keyed by `yyyy-MM-dd` -> completed count that day. Days missing
  /// from the map are treated as zero.
  final Map<String, int> dailyCounts;
  final int days;

  const CompletionHeatmap({
    super.key,
    required this.dailyCounts,
    this.days = 30,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    // Pad the front so the grid always starts on a Monday — makes the
    // week columns line up cleanly regardless of what weekday "today"
    // or the range start happens to fall on.
    final rangeStart = todayOnly.subtract(Duration(days: days - 1));
    final leadingPad = rangeStart.weekday - 1; // Monday = 1 -> 0 pad
    final gridStart = rangeStart.subtract(Duration(days: leadingPad));

    final totalCells =
        leadingPad + days + (7 - ((leadingPad + days) % 7)) % 7;
    final weeks = (totalCells / 7).ceil();

    List<Widget> columns = [];
    for (int w = 0; w < weeks; w++) {
      final List<Widget> cells = [];
      for (int d = 0; d < 7; d++) {
        final date = gridStart.add(Duration(days: w * 7 + d));
        final isInRange = !date.isBefore(rangeStart) && !date.isAfter(todayOnly);
        final key =
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final count = dailyCounts[key] ?? 0;
        cells.add(
          Padding(
            padding: const EdgeInsets.all(2),
            child: Tooltip(
              message: isInRange
                  ? '${date.month}/${date.day}: $count completed'
                  : '',
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: isInRange ? _colorFor(count) : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        );
      }
      columns.add(Column(children: cells));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // opens already scrolled to "today"
          child: Row(children: columns),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('Less', style: AppTextStyles.caption),
            const SizedBox(width: 6),
            ...List.generate(4, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _colorFor(i == 0 ? 0 : i),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
            const SizedBox(width: 6),
            Text('More', style: AppTextStyles.caption),
          ],
        ),
      ],
    );
  }

  Color _colorFor(int count) {
    if (count <= 0) return AppColors.divider;
    if (count == 1) return AppColors.accent.withValues(alpha: 0.35);
    if (count == 2) return AppColors.accent.withValues(alpha: 0.65);
    return AppColors.accent;
  }
}
