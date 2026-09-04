import 'package:flutter/material.dart';

import '../../models/goal_model.dart';
import '../../database/db_helper.dart';
import '../../utils/id_generator.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/goal_card.dart';
import '../../widgets/primary_button.dart';
import '../schedule/phase_list_screen.dart';

class GoalCategoryScreen extends StatefulWidget {
   GoalCategoryScreen({super.key});

  @override
  State<GoalCategoryScreen> createState() => _GoalCategoryScreenState();
}

class _GoalCategoryScreenState extends State<GoalCategoryScreen> {
  GoalCategory? _selected;
  final TextEditingController _customController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  bool _saving = false;

  static const List<(GoalCategory, IconData)> _categories = [
    (GoalCategory.weightLoss, Icons.monitor_weight_outlined),
    (GoalCategory.study, Icons.menu_book_outlined),
    (GoalCategory.business, Icons.trending_up),
    (GoalCategory.health, Icons.favorite_outline),
    (GoalCategory.future, Icons.rocket_launch_outlined),
    (GoalCategory.custom, Icons.edit_outlined),
  ];

  Future<void> _continue() async {
    if (_selected == null) return;

    final isCustom = _selected == GoalCategory.custom;
    if (isCustom && _customController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Please describe your goal')),
      );
      return;
    }

    // Only one active goal per predefined category at a time — custom
    // goals are exempt since each one is its own distinct idea, not a
    // shared bucket. If one already exists, send the user there to add
    // a phase/task instead of creating a duplicate.
    if (!isCustom) {
      final existing =
          await DBHelper.instance.getActiveGoalByCategory(_selected!);
      if (existing != null) {
        if (!mounted) return;
        final goToExisting = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('You already have a ${_selected!.label} goal'),
            content: Text(
              '"${existing.title}" is already active in this category. '
              'Add a new phase or task to it instead of starting another '
              '${_selected!.label} goal.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Go to Goal'),
              ),
            ],
          ),
        );
        if (goToExisting == true) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => PhaseListScreen(goal: existing),
            ),
          );
        }
        return;
      }
    }

    setState(() => _saving = true);

    final goal = Goal(
      id: generateId(),
      title: isCustom ? _customController.text.trim() : _selected!.label,
      category: _selected!,
      targetInfo:
          _targetController.text.trim().isEmpty ? null : _targetController.text.trim(),
    );

    await DBHelper.instance.insertGoal(goal);

    if (!mounted) return;
    setState(() => _saving = false);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PhaseListScreen(goal: goal, isOnboarding: true),
      ),
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
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.track_changes,
                        color: AppColors.accent, size: 22),
                  ),
                  const Spacer(),
                  // Only reached without a way back during first-run
                  // onboarding (Welcome -> here via pushReplacement).
                  // When opened mid-app via the "Add Goal" button,
                  // Navigator.canPop is true and the user should be
                  // able to back out of adding a second goal.
                  if (Navigator.canPop(context))
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.divider),
                        ),
                      ),
                    ),
                ],
              ),
               SizedBox(height: 20),
               Text('What\'s your goal?', style: AppTextStyles.h1),
               SizedBox(height: 6),
               Text(
                'Pick a category that matches what you want to achieve — '
                'next you\'ll build your own step-by-step plan for it.',
                style: AppTextStyles.bodyMuted,
              ),
               SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GridView.count(
                        shrinkWrap: true,
                        physics:  NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.25,
                        children: _categories.map((c) {
                          return GoalCard(
                            category: c.$1,
                            icon: c.$2,
                            selected: _selected == c.$1,
                            onTap: () => setState(() => _selected = c.$1),
                          );
                        }).toList(),
                      ),
                      if (_selected == GoalCategory.custom) ...[
                         SizedBox(height: 20),
                        Text('Describe your goal', style: AppTextStyles.h3),
                         SizedBox(height: 8),
                        TextField(
                          controller: _customController,
                          style: AppTextStyles.body,
                          decoration:  InputDecoration(
                            hintText: 'e.g. Learn guitar, Finish my thesis',
                          ),
                        ),
                      ],
                      if (_selected != null) ...[
                         SizedBox(height: 20),
                        Text('Target (optional)', style: AppTextStyles.h3),
                         SizedBox(height: 8),
                        TextField(
                          controller: _targetController,
                          style: AppTextStyles.body,
                          decoration:  InputDecoration(
                            hintText: 'e.g. Lose 5kg in 2 months',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
               SizedBox(height: 8),
              PrimaryButton(
                label: 'Continue',
                isLoading: _saving,
                onPressed: _selected == null ? null : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
