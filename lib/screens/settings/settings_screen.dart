import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../database/db_helper.dart';
import '../../models/profile_model.dart';
import '../../services/notification_service.dart';
import '../../services/theme_controller.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import 'backups_screen.dart';
import '../onboarding/goal_category_screen.dart';

class SettingsScreen extends StatefulWidget {
   SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  UserProfile? _profile;
  bool _loading = true;

  bool _notificationsEnabled = false;

  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when coming back from system Settings.
    if (state == AppLifecycleState.resumed) {
      _loadPermissionStatuses();
    }
  }

  Future<void> _loadAll() async {
    final profile = await DBHelper.instance.getProfile();
    final info = await PackageInfo.fromPlatform();

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _versionLabel = '${info.version} (build ${info.buildNumber})';
      _loading = false;
    });

    await _loadPermissionStatuses();
  }

  Future<void> _loadPermissionStatuses() async {
    final notifStatus = await Permission.notification.status;

    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notifStatus.isGranted;
    });
  }

  // ---------------- PROFILE ----------------

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${dir.path}/profile');
    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }

    // Fixed filename (not timestamped) — a new photo should replace
    // the old one on disk, not pile up unused files forever.
    final savedPath = '${profileDir.path}/avatar.jpg';
    await File(picked.path).copy(savedPath);

    final updated = UserProfile(name: _profile?.name, photoPath: savedPath);
    await DBHelper.instance.saveProfile(updated);

    if (!mounted) return;
    setState(() => _profile = updated);
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _profile?.name ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration:  InputDecoration(hintText: 'Enter your name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:  Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:  Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final newName = controller.text.trim();

    final updated = UserProfile(
      name: newName.isEmpty ? null : newName,
      photoPath: _profile?.photoPath,
    );
    await DBHelper.instance.saveProfile(updated);

    if (!mounted) return;
    setState(() => _profile = updated);
  }

  // ---------------- DATA RESET ----------------

  Future<void> _confirmResetData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text('Reset all data?'),
        content:  Text(
          'This permanently deletes every goal, task, schedule, and '
          'locked-app setting. Your name/photo stay. This can\'t be undone. '
          'Consider creating a backup first from Backup & Restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:  Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child:  Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await NotificationService.instance.cancelAll();
    await DBHelper.instance.resetAllData();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) =>  GoalCategoryScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return  Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title:  Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding:  EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _buildProfileCard(),
             SizedBox(height: 24),
            _sectionLabel('Appearance'),
            _buildThemeTile(),
             SizedBox(height: 24),
            _sectionLabel('Notifications'),
            _buildPermissionTile(
              icon: Icons.notifications_none_rounded,
              title: 'Task Alarm Notifications',
              granted: _notificationsEnabled,
              subtitle: _notificationsEnabled
                  ? 'Enabled'
                  : 'Off — you won\'t be alerted when tasks start',
              onTap: () async {
                if (!_notificationsEnabled) {
                  final status = await Permission.notification.request();
                  if (status.isPermanentlyDenied) {
                    await openAppSettings();
                  }
                } else {
                  await openAppSettings();
                }
                _loadPermissionStatuses();
              },
            ),
             SizedBox(height: 24),
            _sectionLabel('Data'),
            _buildTile(
              icon: Icons.save_alt_rounded,
              title: 'Backup & Restore',
              subtitle: 'Save or restore your goals and history locally',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupsScreen()),
              ),
            ),
            _buildTile(
              icon: Icons.delete_outline_rounded,
              title: 'Reset All Data',
              subtitle: 'Delete every goal, task, and schedule',
              titleColor: AppColors.danger,
              onTap: _confirmResetData,
            ),
             SizedBox(height: 24),
            _sectionLabel('About'),
            _buildTile(
              icon: Icons.info_outline_rounded,
              title: 'Aspire Lock',
              subtitle: 'Version $_versionLabel',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final photoPath = _profile?.photoPath;
    final name = _profile?.name;

    return Container(
      padding:  EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _pickPhoto,
            borderRadius: BorderRadius.circular(36),
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.background,
                  backgroundImage: (photoPath != null &&
                          File(photoPath).existsSync())
                      ? FileImage(File(photoPath))
                      : null,
                  child: (photoPath == null || !File(photoPath).existsSync())
                      ?  Icon(Icons.person_outline_rounded,
                          size: 32, color: AppColors.textMuted)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding:  EdgeInsets.all(4),
                    decoration:  BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child:  Icon(Icons.camera_alt_rounded,
                        size: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
           SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (name == null || name.isEmpty) ? 'Add your name' : name,
                  style: AppTextStyles.h3,
                  overflow: TextOverflow.ellipsis,
                ),
                 SizedBox(height: 2),
                 Text('Tap to edit your local profile',
                    style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
          IconButton(
            onPressed: _editName,
            icon:  Icon(Icons.edit_outlined, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding:  EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        label.toUpperCase(),
        style:  TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    return Card(
      margin:  EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: titleColor ?? AppColors.textPrimary),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: titleColor),
        ),
        subtitle: Text(subtitle, style: AppTextStyles.bodyMuted),
        trailing: onTap != null
            ?  Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted)
            : null,
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
  }) {
    return Card(
      margin:  EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.textPrimary),
        title: Text(title, style:  TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: AppTextStyles.bodyMuted),
        trailing: Icon(
          granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: granted ? Colors.green : AppColors.warning,
        ),
      ),
    );
  }

  /// Segmented Light / Dark / System control. Uses AnimatedBuilder so
  /// it repaints immediately when the user taps a segment, without
  /// needing this whole screen's setState — ThemeController.instance
  /// already triggers the app-wide rebuild.
  Widget _buildThemeTile() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dark_mode_outlined, color: AppColors.textPrimary),
                const SizedBox(width: 12),
                Text('Theme', style: AppTextStyles.h3),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how Aspire Lock looks.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: ThemeController.instance,
              builder: (context, _) {
                return Row(
                  children: [
                    _themeSegment('Light', Icons.light_mode_outlined, ThemeMode.light),
                    const SizedBox(width: 8),
                    _themeSegment('Dark', Icons.dark_mode_outlined, ThemeMode.dark),
                    const SizedBox(width: 8),
                    _themeSegment('System', Icons.settings_suggest_outlined, ThemeMode.system),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeSegment(String label, IconData icon, ThemeMode mode) {
    final selected = ThemeController.instance.mode == mode;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ThemeController.instance.setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.onPrimary : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.onPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
