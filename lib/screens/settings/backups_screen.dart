import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../database/db_helper.dart';
import '../../services/notification_service.dart';
import '../../services/backup_service.dart';
import '../main_nav_screen.dart';

/// Create / restore / delete local JSON backups (see BackupService).
/// Purely local file I/O — no new package, no external service.
class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  List<File> _backups = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final backups = await BackupService.instance.listBackups();
    if (!mounted) return;
    setState(() {
      _backups = backups;
      _loading = false;
    });
  }

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    await BackupService.instance.createBackup();
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup created')),
    );
  }

  Future<void> _confirmRestore(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: const Text(
          'This replaces everything currently in the app — all goals, '
          'tasks, and history — with what\'s in this backup. This can\'t '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _restore(file);
  }

  Future<void> _restore(File file) async {
    setState(() => _busy = true);

    // Whatever alarms are active belong to the *current* data, which
    // is about to be replaced wholesale — leaving them running would
    // fire an alarm for a task that (after restore) may no longer
    // even exist.
    await NotificationService.instance.cancelAll();

    await BackupService.instance.restoreBackup(file);

    // Re-arm alarms for whatever the restored data says is pending —
    // mirrors exactly what BootSyncService does after a device
    // reboot, since a restore is functionally the same situation
    // (task IDs the OS's AlarmManager knew about are now gone).
    final pending = await DBHelper.instance.getPendingUpcomingTasks();
    await NotificationService.instance.scheduleAllTasks(pending);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmDelete(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this backup?'),
        content: const Text('This only removes the backup file itself — '
            'your current app data is untouched.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await BackupService.instance.deleteBackup(file);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Backups are saved on this device only — nothing is '
                        'ever uploaded anywhere. Note: they\'re removed if '
                        'you uninstall the app, so they protect against '
                        'mistakes and bugs, not a lost or wiped phone.',
                        style: AppTextStyles.caption,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _createBackup,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('Create Backup Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Saved Backups', style: AppTextStyles.h3),
                    const SizedBox(height: 12),
                    if (_backups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No backups yet',
                            style: AppTextStyles.bodyMuted,
                          ),
                        ),
                      )
                    else
                      ..._backups.map(_buildBackupTile),
                  ],
                ),
          if (_busy)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildBackupTile(File file) {
    final modified = file.statSync().modified;
    final sizeKb = (file.lengthSync() / 1024).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        leading: Icon(Icons.description_outlined, color: AppColors.textPrimary),
        title: Text(
          DateFormat('MMM d, yyyy — h:mm a').format(modified),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('$sizeKb KB', style: AppTextStyles.caption),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'restore') _confirmRestore(file);
            if (value == 'delete') _confirmDelete(file);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'restore', child: Text('Restore')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      ),
    );
  }
}
