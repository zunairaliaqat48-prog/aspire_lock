import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../services/streak_freeze_service.dart';
import 'primary_button.dart';

/// Lets the user spend one of this month's Streak Freeze tokens on a
/// specific recently-missed day, so it stops counting against their
/// streak (see StreakFreezeService — the task itself stays `missed`,
/// only the streak math forgives it).
///
/// Returns `true` via [Navigator.pop] if a freeze was actually
/// applied, so the caller (ProgressDashboardScreen) knows to reload
/// its streak numbers.
class StreakFreezeSheet extends StatefulWidget {
  final String goalId;
  const StreakFreezeSheet({super.key, required this.goalId});

  static Future<bool> show(BuildContext context, String goalId) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StreakFreezeSheet(goalId: goalId),
    );
    return result ?? false;
  }

  @override
  State<StreakFreezeSheet> createState() => _StreakFreezeSheetState();
}

class _StreakFreezeSheetState extends State<StreakFreezeSheet> {
  bool _loading = true;
  int _remaining = 0;
  List<DateTime> _dates = [];
  DateTime? _selected;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final remaining =
        await StreakFreezeService.instance.remainingThisMonth(widget.goalId);
    final dates =
        await StreakFreezeService.instance.getFreezableMissedDates(widget.goalId);
    if (!mounted) return;
    setState(() {
      _remaining = remaining;
      _dates = dates;
      _loading = false;
    });
  }

  Future<void> _apply() async {
    final date = _selected;
    if (date == null || _remaining <= 0 || _applying) return;
    setState(() => _applying = true);
    await StreakFreezeService.instance.freezeDay(widget.goalId, date);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String _formatDate(DateTime d) {
    const weekdays = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(Icons.ac_unit_rounded, color: AppColors.accent, size: 22),
                      const SizedBox(width: 8),
                      Text('Streak Freeze', style: AppTextStyles.h3),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a missed day to protect — it won\'t count against '
                    'your streak. The task itself stays marked as missed.',
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_remaining > 0
                              ? AppColors.success
                              : AppColors.danger)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_remaining of ${StreakFreezeService.monthlyAllowance} freezes left this month',
                      style: TextStyle(
                        color: _remaining > 0
                            ? AppColors.success
                            : AppColors.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_dates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No recently missed days to freeze.',
                        style: AppTextStyles.bodyMuted,
                      ),
                    )
                  else
                    ..._dates.map((date) {
                      final isSelected = _selected == date;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _remaining > 0
                              ? () => setState(() => _selected = date)
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.accent.withValues(alpha: 0.12)
                                  : AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.divider,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 18,
                                  color: isSelected
                                      ? AppColors.accent
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 10),
                                Text(_formatDate(date), style: AppTextStyles.body),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Use Freeze',
                    isLoading: _applying,
                    onPressed: (_selected != null && _remaining > 0)
                        ? _apply
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed:
                          _applying ? null : () => Navigator.of(context).pop(false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
