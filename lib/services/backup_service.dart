import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../database/db_helper.dart';

/// Local, on-device backup/restore for Aspire Lock's entire database.
///
/// Deliberately zero new dependencies: `path_provider` was already a
/// direct dependency (db_helper.dart and settings_screen.dart both
/// already use it) for finding the app's own documents directory. No
/// network call, no cloud, no external service of any kind — a
/// backup is just a JSON file written to this app's own local storage
/// via [DBHelper.exportAllData].
///
/// Known limitation, stated plainly rather than glossed over: because
/// this writes into the app's private documents directory (not a
/// shared/public folder), the backup file is deleted along with the
/// app if the user *uninstalls* Aspire Lock — Android sandboxes an
/// app's private storage the same way it sandboxes its database. What
/// this DOES protect against: accidentally tapping "Reset All Data",
/// an app update or bug that corrupts a table, or wanting to roll
/// back to an earlier point in time. Protecting against a full
/// uninstall would need the user to manually move the exported file
/// out of the app's storage (e.g. via a connected PC), or a native
/// Storage-Access-Framework picker — a genuinely bigger, separate
/// piece of work than this.
class BackupService {
  BackupService._internal();
  static final BackupService instance = BackupService._internal();

  static const int _formatVersion = 1;

  Future<Directory> _backupsDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes a new timestamped backup file and returns it.
  Future<File> createBackup() async {
    final data = await DBHelper.instance.exportAllData();
    final payload = {
      'formatVersion': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': data,
    };

    final dir = await _backupsDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/backup_$timestamp.json');
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  /// All existing backup files, newest first.
  Future<List<File>> listBackups() async {
    final dir = await _backupsDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  /// Reads [file] and replaces the entire current database with its
  /// contents via [DBHelper.importAllData]. This does NOT touch
  /// anything alarm/lock-related — the caller (see BackupsScreen) is
  /// responsible for cancelling current notifications/locks first and
  /// rescheduling fresh ones after, since a restored set of tasks may
  /// have completely different IDs and times than whatever was
  /// running a moment ago.
  Future<void> restoreBackup(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>;
    await DBHelper.instance.importAllData(data);
  }

  Future<void> deleteBackup(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
