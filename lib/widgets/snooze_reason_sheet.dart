import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import 'primary_button.dart';

/// A handful of common excuses, offered as one-tap starting points —
/// picking one still requires reading it and tapping Confirm, which is
/// enough friction to make snoozing a deliberate choice rather than a
/// reflex, without forcing everyone to type from scratch every time.
const List<String> _kQuickReasons = [
  'Still in another meeting',
  'Not feeling well',
  'Need 5 more minutes',
  'Something urgent came up',
];

/// Shown right before a snooze is committed. Returns the typed reason
/// (a non-empty, trimmed string) if the user confirms, or null if they
/// back out — callers should treat null as "don't snooze".
///
/// This is the direct replacement for the old Emergency Unlock sheet:
/// same idea (a short, mandatory pause for reflection before the user
/// gets to duck out of a task), just attached to snoozing an alarm
/// instead of breaking an app lock, since app-locking itself has been
/// removed.
class SnoozeReasonSheet extends StatefulWidget {
  final int snoozesLeft;

  const SnoozeReasonSheet({super.key, required this.snoozesLeft});

  static Future<String?> show(BuildContext context, {required int snoozesLeft}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SnoozeReasonSheet(snoozesLeft: snoozesLeft),
    );
  }

  @override
  State<SnoozeReasonSheet> createState() => _SnoozeReasonSheetState();
}

class _SnoozeReasonSheetState extends State<SnoozeReasonSheet> {
  final _controller = TextEditingController();

  bool get _canConfirm => _controller.text.trim().length >= 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pickQuickReason(String reason) {
    setState(() {
      _controller.text = reason;
      _controller.selection = TextSelection.collapsed(offset: reason.length);
    });
  }

  void _confirm() {
    final reason = _controller.text.trim();
    if (reason.length < 3) return;
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Why are you snoozing?', style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text(
              '${widget.snoozesLeft} snooze${widget.snoozesLeft == 1 ? '' : 's'} '
              'left for this task. This gets saved so you can see your own '
              'patterns later.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kQuickReasons.map((reason) {
                final selected = _controller.text == reason;
                return ChoiceChip(
                  label: Text(reason),
                  selected: selected,
                  onSelected: (_) => _pickQuickReason(reason),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLength: 120,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Or type your own reason...',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: 'Confirm & Snooze',
              onPressed: _canConfirm ? _confirm : null,
            ),
          ],
        ),
      ),
    );
  }
}
