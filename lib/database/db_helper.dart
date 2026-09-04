import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/goal_model.dart';
import '../models/task_model.dart';
import '../models/schedule_model.dart';
import '../models/profile_model.dart';
import '../models/goal_phase_model.dart';
import '../models/task_snooze_model.dart';

/// Central database helper — handles all local SQLite storage for
/// Goals, Tasks, and Schedule Rules.
class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'aspire_lock.db');

    return openDatabase(
      path,
      version: 12,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  /// Runs when an existing install's DB version is behind the app's
  /// current version. Each `if` is additive-only (never drops/alters
  /// existing tables) so upgrading never loses a user's existing
  /// goals/tasks/history.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profile (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          name TEXT,
          photoPath TEXT
        )
      ''');
    }
    if (oldVersion < 3) {
      // Existing installs (upgrading from v1/v2) already have real
      // goals/history, so they should NOT see the welcome screen —
      // only a fresh install (created at v3+ via _createTables, which
      // defaults this to 0) should. Backfill existing rows as 1.
      await db.execute('''
        ALTER TABLE profile ADD COLUMN hasOnboarded INTEGER NOT NULL DEFAULT 1
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE tasks ADD COLUMN snoozeCount INTEGER NOT NULL DEFAULT 0
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS goal_phases (
          id TEXT PRIMARY KEY,
          goalId TEXT NOT NULL,
          title TEXT NOT NULL,
          orderIndex INTEGER NOT NULL,
          durationDays INTEGER,
          status TEXT NOT NULL DEFAULT 'upcoming',
          createdAt TEXT NOT NULL,
          startedAt TEXT,
          FOREIGN KEY (goalId) REFERENCES goals (id) ON DELETE CASCADE
        )
      ''');
      // Nullable — existing schedule_rules simply have no phase (null),
      // and keep generating tasks exactly as they did before.
      await db.execute('''
        ALTER TABLE schedule_rules ADD COLUMN phaseId TEXT
      ''');
    }
    if (oldVersion < 6) {
      // Stores the user's Light/Dark/System preference (see
      // ThemeController). Null/missing = "system", same as a fresh
      // install's default, so existing users get no visible change
      // until they explicitly pick something in Settings.
      await db.execute('''
        ALTER TABLE profile ADD COLUMN themeMode TEXT
      ''');
    }
    if (oldVersion < 7) {
      // Historical: previously logged every time the user broke an
      // active app lock early via an "Emergency Unlock" flow (since
      // removed along with app-locking). Table kept only so upgrading
      // installs that already created it don't error; nothing reads
      // or writes to it anymore.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS emergency_unlocks (
          id TEXT PRIMARY KEY,
          taskId TEXT NOT NULL,
          goalId TEXT NOT NULL,
          reason TEXT NOT NULL,
          requestedAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 8) {
      // Lets a goal be marked "achieved" as distinct from just being
      // deleted — see Goal.achievedAt and markGoalAchieved. Both
      // states set isActive=0 (so neither clutters the active goal
      // switcher), but only an achieved goal has this set, which is
      // what lets it still show up in the Achievements list.
      await db.execute('''
        ALTER TABLE goals ADD COLUMN achievedAt TEXT
      ''');
    }
    if (oldVersion < 9) {
      // A specific calendar day, for a specific goal, that the user
      // has spent a monthly "freeze" token on (see StreakFreezeService)
      // so a missed day there doesn't break their streak. UNIQUE
      // guards against double-freezing the same day twice by accident.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS streak_freezes (
          id TEXT PRIMARY KEY,
          goalId TEXT NOT NULL,
          date TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          UNIQUE(goalId, date)
        )
      ''');
    }
    if (oldVersion < 10) {
      // Logs the reason typed in every time the user snoozes an alarm
      // (see FullScreenAlarmScreen / SnoozeReasonSheet) — the
      // replacement for the old "Emergency Unlock" log now that
      // app-locking itself is gone. Same accountability idea: the
      // friction of having to type *why* only works if the user can
      // later see, in black and white, how often and why they put a
      // task off.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS task_snoozes (
          id TEXT PRIMARY KEY,
          taskId TEXT NOT NULL,
          goalId TEXT NOT NULL,
          reason TEXT NOT NULL,
          snoozedAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 11) {
      // Lets HomeScreen notice when a streak actually broke (dropped
      // since it was last shown) instead of it just silently becoming
      // "0" next time the app opens — see Goal.lastSeenStreak and
      // HomeScreen._checkForBrokenStreak. Existing goal rows get 0
      // here, same as a brand new goal, so nobody sees a false "streak
      // lost" the very first time this column exists.
      await db.execute(
        'ALTER TABLE goals ADD COLUMN lastSeenStreak INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 12) {
      // sourceRuleId: lets TaskGenerationService recognise "this rule
      // already has a task today" by the rule's own stable id instead
      // of by title+time — editing either of those on an existing task
      // (EditTaskSheet) was making the very next generation pass think
      // the day still needed a task and silently create a duplicate.
      // Existing rows get NULL, which TaskGenerationService's dedup
      // falls back to matching by title+time for, same as before this
      // column existed.
      await db.execute('ALTER TABLE tasks ADD COLUMN sourceRuleId TEXT');
      // startedAt: when the user actually tapped "Start Task" on this
      // occurrence — lets TaskCompleteScreen enforce that a task can't
      // be marked done before its full duration has actually passed.
      await db.execute('ALTER TABLE tasks ADD COLUMN startedAt TEXT');
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE goals (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        targetInfo TEXT,
        createdAt TEXT NOT NULL,
        isActive INTEGER NOT NULL,
        achievedAt TEXT,
        lastSeenStreak INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        goalId TEXT NOT NULL,
        title TEXT NOT NULL,
        scheduledDate TEXT NOT NULL,
        scheduledTime TEXT NOT NULL,
        durationMinutes INTEGER NOT NULL,
        requiresPhotoProof INTEGER NOT NULL,
        status TEXT NOT NULL,
        proofImagePath TEXT,
        completedAt TEXT,
        snoozeCount INTEGER NOT NULL DEFAULT 0,
        sourceRuleId TEXT,
        startedAt TEXT,
        FOREIGN KEY (goalId) REFERENCES goals (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE schedule_rules (
        id TEXT PRIMARY KEY,
        goalId TEXT NOT NULL,
        phaseId TEXT,
        taskTitle TEXT NOT NULL,
        time TEXT NOT NULL,
        durationMinutes INTEGER NOT NULL,
        activeWeekdays TEXT NOT NULL,
        requiresPhotoProof INTEGER NOT NULL,
        isActive INTEGER NOT NULL,
        FOREIGN KEY (goalId) REFERENCES goals (id) ON DELETE CASCADE
      )
    ''');

    // Single-row table (id is always 1) holding the local, on-device
    // profile — just a display name + optional photo path, plus a
    // hasOnboarded flag so the welcome screen only shows once. There's
    // no login/account system in this app, so this is purely local.
    await db.execute('''
      CREATE TABLE profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT,
        photoPath TEXT,
        hasOnboarded INTEGER NOT NULL DEFAULT 0,
        themeMode TEXT
      )
    ''');

    // User-defined stages within a goal (e.g. "Learn the Skill" ->
    // "Build Portfolio" -> "Pitch Clients"). Entirely user-authored —
    // see GoalPhase model docs. Optional: goals that don't use phases
    // simply never get rows here.
    await db.execute('''
      CREATE TABLE goal_phases (
        id TEXT PRIMARY KEY,
        goalId TEXT NOT NULL,
        title TEXT NOT NULL,
        orderIndex INTEGER NOT NULL,
        durationDays INTEGER,
        status TEXT NOT NULL DEFAULT 'upcoming',
        createdAt TEXT NOT NULL,
        startedAt TEXT,
        FOREIGN KEY (goalId) REFERENCES goals (id) ON DELETE CASCADE
      )
    ''');

    // See _onUpgrade oldVersion < 9 — kept in sync here for fresh
    // installs.
    await db.execute('''
      CREATE TABLE streak_freezes (
        id TEXT PRIMARY KEY,
        goalId TEXT NOT NULL,
        date TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        UNIQUE(goalId, date)
      )
    ''');

    // See _onUpgrade oldVersion < 10 — kept in sync here for fresh
    // installs.
    await db.execute('''
      CREATE TABLE task_snoozes (
        id TEXT PRIMARY KEY,
        taskId TEXT NOT NULL,
        goalId TEXT NOT NULL,
        reason TEXT NOT NULL,
        snoozedAt TEXT NOT NULL
      )
    ''');
  }

  // ---------------- GOALS ----------------

  Future<void> insertGoal(Goal goal) async {
    final db = await database;
    await db.insert(
      'goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Goal>> getActiveGoals() async {
    final db = await database;
    final maps = await db.query('goals', where: 'isActive = 1');
    return maps.map((m) => Goal.fromMap(m)).toList();
  }

  /// Returns the user's existing active goal in [category], if any.
  /// Used to stop a second goal being created in the same category —
  /// the user should add phases/tasks to the existing one instead.
  /// [GoalCategory.custom] is exempt since each custom goal is a
  /// distinct user-typed idea, not a shared bucket.
  Future<Goal?> getActiveGoalByCategory(GoalCategory category) async {
    final db = await database;
    final maps = await db.query(
      'goals',
      where: 'category = ? AND isActive = 1',
      whereArgs: [category.name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Goal.fromMap(maps.first);
  }

  Future<void> deactivateGoal(String goalId) async {
    final db = await database;
    await db.update(
      'goals',
      {'isActive': 0},
      where: 'id = ?',
      whereArgs: [goalId],
    );
  }

  /// Marks a goal as successfully achieved — distinct from deleting
  /// it (see Goal.achievedAt). The goal drops out of the active list
  /// same as a deleted one, but stays queryable via [getAchievedGoals]
  /// for the Achievements screen instead of vanishing.
  Future<void> markGoalAchieved(String goalId) async {
    final db = await database;
    await db.update(
      'goals',
      {'isActive': 0, 'achievedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [goalId],
    );
  }

  /// Every goal the user has ever marked achieved, most recent first.
  Future<List<Goal>> getAchievedGoals() async {
    final db = await database;
    final maps = await db.query(
      'goals',
      where: 'achievedAt IS NOT NULL',
      orderBy: 'achievedAt DESC',
    );
    return maps.map((m) => Goal.fromMap(m)).toList();
  }

  /// Updates a goal's editable fields (title/category/targetInfo).
  /// [id], [createdAt] and [isActive] are left untouched — use
  /// [deactivateGoal] to delete/deactivate instead.
  Future<void> updateGoal(Goal goal) async {
    final db = await database;
    await db.update(
      'goals',
      {
        'title': goal.title,
        'category': goal.category.name,
        'targetInfo': goal.targetInfo,
      },
      where: 'id = ?',
      whereArgs: [goal.id],
    );
  }

  // ---------------- TASKS ----------------

  Future<void> insertTask(Task task) async {
    final db = await database;
    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertTasks(List<Task> tasks) async {
    final db = await database;
    final batch = db.batch();
    for (final task in tasks) {
      batch.insert(
        'tasks',
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Task>> getTasksForDate(DateTime date) async {
    final db = await database;
    final dateStr = DateTime(date.year, date.month, date.day).toIso8601String();
    final maps = await db.query(
      'tasks',
      where: "date(scheduledDate) = date(?)",
      whereArgs: [dateStr],
      orderBy: 'scheduledTime ASC',
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  /// Like [getTasksForDate] but scoped to a single goal — used by
  /// [TaskGenerationService] to check which tasks already exist for a
  /// day before generating more, so a rule added *after* other tasks
  /// already exist for today isn't silently skipped until tomorrow.
  Future<List<Task>> getTasksForGoalAndDate(String goalId, DateTime date) async {
    final db = await database;
    final dateStr = DateTime(date.year, date.month, date.day).toIso8601String();
    final maps = await db.query(
      'tasks',
      where: 'goalId = ? AND date(scheduledDate) = date(?)',
      whereArgs: [goalId, dateStr],
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<Task?> getTaskById(String id) async {
    final db = await database;
    final maps = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Task.fromMap(maps.first);
  }

  Future<List<Task>> getTasksForGoal(String goalId) async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'goalId = ?',
      whereArgs: [goalId],
      orderBy: 'scheduledDate ASC, scheduledTime ASC',
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<void> updateTaskStatus(
    String taskId, {
    required TaskStatus status,
    String? proofImagePath,
    DateTime? completedAt,
  }) async {
    final db = await database;
    await db.update(
      'tasks',
      {
        'status': status.name,
        if (proofImagePath != null) 'proofImagePath': proofImagePath,
        if (completedAt != null) 'completedAt': completedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  /// Marks a task as actively started right now — see [Task.startedAt]
  /// and TaskCompleteScreen's completion countdown, which is what
  /// actually uses this timestamp to stop the task being marked done
  /// before its full duration has passed. Deliberately a no-op if the
  /// task already has a startedAt (e.g. the user backed out and came
  /// back in) — restarting the clock every re-entry would let someone
  /// dodge the wait entirely just by leaving and reopening the task.
  Future<void> markTaskStarted(String taskId) async {
    final db = await database;
    final task = await getTaskById(taskId);
    if (task == null || task.startedAt != null) return;

    await db.update(
      'tasks',
      {
        'status': TaskStatus.inProgress.name,
        'startedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  /// Increments a task's snooze counter by one and returns the new
  /// count — used by [FullScreenAlarmScreen] both to persist the
  /// snooze (so the limit survives an app restart) and to know how
  /// many snoozes remain.
  Future<int> incrementSnoozeCount(String taskId) async {
    final db = await database;
    final task = await getTaskById(taskId);
    final newCount = (task?.snoozeCount ?? 0) + 1;
    await db.update(
      'tasks',
      {'snoozeCount': newCount},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    return newCount;
  }

  // ---------------- TASK SNOOZES ----------------

  Future<void> insertTaskSnooze(TaskSnoozeLog log) async {
    final db = await database;
    await db.insert(
      'task_snoozes',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Most recent snooze reasons for a goal, newest first — surfaced on
  /// the dashboard so the friction of typing a reason actually pays
  /// off later: the user can see, in black and white, how often (and
  /// why) they've put a task off.
  Future<List<TaskSnoozeLog>> getRecentSnoozesForGoal(
    String goalId, {
    int limit = 10,
  }) async {
    final db = await database;
    final maps = await db.query(
      'task_snoozes',
      where: 'goalId = ?',
      whereArgs: [goalId],
      orderBy: 'snoozedAt DESC',
      limit: limit,
    );
    return maps.map((m) => TaskSnoozeLog.fromMap(m)).toList();
  }

  /// Total snoozes ever logged for a goal — feeds
  /// [GoalOverallStats.snoozes].
  Future<int> countSnoozesForGoal(String goalId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM task_snoozes WHERE goalId = ?',
      [goalId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Updates a single task's editable schedule fields (title/time/
  /// duration/photo-proof requirement). Only meant for tasks that are
  /// still `pending`/`inProgress` — the UI is responsible for not
  /// offering this on completed/missed tasks.
  Future<void> updateTaskDetails(
    String taskId, {
    required String title,
    required String scheduledTime,
    required int durationMinutes,
    required bool requiresPhotoProof,
  }) async {
    final db = await database;
    await db.update(
      'tasks',
      {
        'title': title,
        'scheduledTime': scheduledTime,
        'durationMinutes': durationMinutes,
        'requiresPhotoProof': requiresPhotoProof ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  /// Permanently removes a single task row (e.g. user deletes one
  /// occurrence). Caller is responsible for cancelling its alarm and
  /// releasing an active app-lock if it was guarding this task.
  Future<void> deleteTask(String taskId) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
  }

  // ---------------- SCHEDULE RULES ----------------

  Future<void> insertScheduleRule(ScheduleRule rule) async {
    final db = await database;
    await db.insert(
      'schedule_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ScheduleRule>> getActiveRulesForGoal(String goalId) async {
    final db = await database;
    final maps = await db.query(
      'schedule_rules',
      where: 'goalId = ? AND isActive = 1',
      whereArgs: [goalId],
    );
    return maps.map((m) => ScheduleRule.fromMap(m)).toList();
  }

  /// Updates an existing recurring rule's editable fields. Future task
  /// generation ([TaskGenerationService]) will pick up the new time/
  /// duration/weekdays the next time it runs; already-generated task
  /// rows are untouched (edit those individually via [updateTaskDetails]).
  Future<void> updateScheduleRule(ScheduleRule rule) async {
    final db = await database;
    await db.update(
      'schedule_rules',
      {
        'taskTitle': rule.taskTitle,
        'time': rule.time,
        'durationMinutes': rule.durationMinutes,
        'activeWeekdays': rule.activeWeekdays.join(','),
        'requiresPhotoProof': rule.requiresPhotoProof ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  /// Soft-deletes a recurring rule (mirrors [deactivateGoal]) so it
  /// stops generating new daily tasks, without touching tasks already
  /// created from it.
  Future<void> deactivateScheduleRule(String ruleId) async {
    final db = await database;
    await db.update(
      'schedule_rules',
      {'isActive': 0},
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  /// Like [getActiveRulesForGoal] but phase-aware — used by
  /// [TaskGenerationService] instead of [getActiveRulesForGoal] so
  /// upcoming/future phases' tasks don't start generating before their
  /// turn.
  ///
  /// If [goalId] has any [GoalPhase]s defined, only rules belonging to
  /// the currently *active* phase are returned (empty list if no phase
  /// is active yet). Goals with no phases at all — created before
  /// phases existed, or that simply don't use them — fall back to
  /// every active rule, exactly as before.
  Future<List<ScheduleRule>> getGenerationRulesForGoal(String goalId) async {
    final phases = await getPhasesForGoal(goalId);
    if (phases.isEmpty) {
      return getActiveRulesForGoal(goalId);
    }

    final activePhase = await getActivePhaseForGoal(goalId);
    if (activePhase == null) return [];

    final db = await database;
    final maps = await db.query(
      'schedule_rules',
      where: 'goalId = ? AND isActive = 1 AND phaseId = ?',
      whereArgs: [goalId, activePhase.id],
    );
    return maps.map((m) => ScheduleRule.fromMap(m)).toList();
  }

  /// Every rule that is *currently* capable of generating a daily task
  /// — i.e. [getGenerationRulesForGoal] across every active goal. Used
  /// to check for time conflicts when adding/editing a task: two rules
  /// in phases that are never active at the same time (e.g. two
  /// different upcoming phases of the same goal) aren't a real-world
  /// conflict, so this only looks at rules that would actually fire.
  /// Pass [excludeGoalId] to skip a goal entirely (not needed for the
  /// normal case since [ScheduleConflict.findConflict] already ignores
  /// the rule being edited by id).
  Future<List<ScheduleRule>> getAllActiveGenerationRules({
    String? excludeGoalId,
  }) async {
    final goals = await getActiveGoals();
    final List<ScheduleRule> all = [];
    for (final goal in goals) {
      if (goal.id == excludeGoalId) continue;
      all.addAll(await getGenerationRulesForGoal(goal.id));
    }
    return all;
  }

  // ---------------- GOAL PHASES ----------------

  Future<void> insertPhase(GoalPhase phase) async {
    final db = await database;
    await db.insert(
      'goal_phases',
      phase.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// All phases for a goal, in the order the user defined them.
  Future<List<GoalPhase>> getPhasesForGoal(String goalId) async {
    final db = await database;
    final maps = await db.query(
      'goal_phases',
      where: 'goalId = ?',
      whereArgs: [goalId],
      orderBy: 'orderIndex ASC',
    );
    return maps.map((m) => GoalPhase.fromMap(m)).toList();
  }

  /// The single phase currently active for a goal, or null if the
  /// goal has no phases yet (e.g. was created before phases existed,
  /// or the user hasn't set any up) or none has been activated yet.
  Future<GoalPhase?> getActivePhaseForGoal(String goalId) async {
    final db = await database;
    final maps = await db.query(
      'goal_phases',
      where: 'goalId = ? AND status = ?',
      whereArgs: [goalId, PhaseStatus.active.name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return GoalPhase.fromMap(maps.first);
  }

  Future<void> updatePhase(GoalPhase phase) async {
    final db = await database;
    await db.update(
      'goal_phases',
      {
        'title': phase.title,
        'orderIndex': phase.orderIndex,
        'durationDays': phase.durationDays,
      },
      where: 'id = ?',
      whereArgs: [phase.id],
    );
  }

  /// Marks [phaseId] as completed and, if a next phase exists (the one
  /// with the next [GoalPhase.orderIndex] for the same goal), marks it
  /// active with `startedAt` set to now. Returns the newly-activated
  /// phase, or null if [phaseId] was the last phase.
  Future<GoalPhase?> completePhaseAndActivateNext(GoalPhase phase) async {
    final db = await database;
    await db.update(
      'goal_phases',
      {'status': PhaseStatus.completed.name},
      where: 'id = ?',
      whereArgs: [phase.id],
    );

    final nextMaps = await db.query(
      'goal_phases',
      where: 'goalId = ? AND orderIndex = ?',
      whereArgs: [phase.goalId, phase.orderIndex + 1],
      limit: 1,
    );
    if (nextMaps.isEmpty) return null;

    final next = GoalPhase.fromMap(nextMaps.first);
    final startedNext = next.copyWith(
      status: PhaseStatus.active,
      startedAt: DateTime.now(),
    );
    await db.update(
      'goal_phases',
      {
        'status': PhaseStatus.active.name,
        'startedAt': startedNext.startedAt!.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [next.id],
    );
    return startedNext;
  }

  /// Activates the very first phase (orderIndex 1) of a freshly
  /// created phase plan — call this right after the user finishes
  /// building their phases, so daily task generation has an active
  /// phase to work from immediately.
  Future<void> activateFirstPhase(String goalId) async {
    final db = await database;
    final maps = await db.query(
      'goal_phases',
      where: 'goalId = ? AND orderIndex = 1',
      whereArgs: [goalId],
      limit: 1,
    );
    if (maps.isEmpty) return;
    await db.update(
      'goal_phases',
      {
        'status': PhaseStatus.active.name,
        'startedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [maps.first['id']],
    );
  }

  Future<void> deletePhase(String phaseId) async {
    final db = await database;
    await db.delete('goal_phases', where: 'id = ?', whereArgs: [phaseId]);
  }

  /// Tasks that are still awaiting user action — used by
  /// [TaskStatusService] to check which ones have run past their
  /// deadline and should flip to `missed`.
  Future<List<Task>> getActionableTasks() async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'status = ? OR status = ?',
      whereArgs: [TaskStatus.pending.name, TaskStatus.inProgress.name],
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  /// Every task that still needs an alarm: not yet completed, not
  /// already given up on as missed, and scheduled today or later.
  /// Used by [BootSyncService] to re-schedule real alarms after a
  /// device reboot (Android clears AlarmManager entries scheduled by
  /// flutter_local_notifications when the device restarts, so they
  /// must be recreated from the DB rather than relying on the OS to
  /// remember them).
  Future<List<Task>> getPendingUpcomingTasks() async {
    final db = await database;
    final todayStr = DateTime.now().toIso8601String();
    final maps = await db.query(
      'tasks',
      where: "status != ? AND status != ? AND date(scheduledDate) >= date(?)",
      whereArgs: [
        TaskStatus.completed.name,
        TaskStatus.missed.name,
        todayStr,
      ],
      orderBy: 'scheduledDate ASC, scheduledTime ASC',
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  /// The most recent [Task.scheduledDate] that exists for this goal,
  /// or null if the goal has no tasks yet. Used by
  /// [TaskGenerationService] to figure out which days still need
  /// tasks generated from the goal's recurring schedule rules.
  Future<DateTime?> getLatestTaskDateForGoal(String goalId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT MAX(date(scheduledDate)) as latest FROM tasks WHERE goalId = ?
    ''', [goalId]);
    final latest = result.first['latest'] as String?;
    if (latest == null) return null;
    return DateTime.parse(latest);
  }

  /// Most recent completed tasks for [goalId] that have a saved proof
  /// photo, newest first — used to populate the dashboard's proof
  /// photo gallery. [limit] caps how many rows come back.
  Future<List<Task>> getRecentProofTasksForGoal(
    String goalId, {
    int limit = 12,
  }) async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: "goalId = ? AND status = ? AND proofImagePath IS NOT NULL "
          "AND proofImagePath != ''",
      whereArgs: [goalId, TaskStatus.completed.name],
      orderBy: 'completedAt DESC',
      limit: limit,
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  // ---------------- PROGRESS HELPERS ----------------

  Future<int> countCompletedTasksBetween(
      String goalId, DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM tasks
      WHERE goalId = ?
        AND status = 'completed'
        AND date(scheduledDate) BETWEEN date(?) AND date(?)
    ''', [goalId, start.toIso8601String(), end.toIso8601String()]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// All-time totals for a goal, for the dashboard's stat tiles (see
  /// [GoalOverallStats]). A single grouped query rather than three
  /// separate COUNT queries.
  Future<GoalOverallStats> getOverallStats(String goalId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) as count FROM tasks
      WHERE goalId = ? GROUP BY status
    ''', [goalId]);

    int completed = 0;
    int missed = 0;
    for (final row in rows) {
      final status = row['status'] as String;
      final count = row['count'] as int;
      if (status == TaskStatus.completed.name) completed = count;
      if (status == TaskStatus.missed.name) missed = count;
    }

    final snoozeCount = await countSnoozesForGoal(goalId);

    return GoalOverallStats(
      totalCompleted: completed,
      totalMissed: missed,
      snoozes: snoozeCount,
    );
  }

  /// Completion rate restricted to just the tasks the user explicitly
  /// marked as needing photo proof — the tasks they themselves said
  /// mattered enough to verify. Deliberately separate from
  /// [getOverallStats]'s all-tasks rate: someone can look consistent
  /// overall while quietly under-performing on exactly the tasks they
  /// asked to be held accountable for, and that gap is only visible if
  /// it's measured on its own (see ProofComplianceStats /
  /// ProgressDashboardScreen's "Proof-Required Tasks" card).
  Future<ProofComplianceStats> getProofComplianceStats(String goalId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) as count FROM tasks
      WHERE goalId = ? AND requiresPhotoProof = 1
        AND status IN (?, ?)
      GROUP BY status
    ''', [goalId, TaskStatus.completed.name, TaskStatus.missed.name]);

    int completed = 0;
    int missed = 0;
    for (final row in rows) {
      final status = row['status'] as String;
      final count = row['count'] as int;
      if (status == TaskStatus.completed.name) completed = count;
      if (status == TaskStatus.missed.name) missed = count;
    }

    return ProofComplianceStats(completed: completed, missed: missed);
  }

  /// Per-day completed-task counts for the last [days] days (today
  /// inclusive), keyed by `yyyy-MM-dd`. Days with no entry in the map
  /// simply had zero completed tasks — used by the dashboard's
  /// GitHub-style completion heatmap ([CompletionHeatmap]).
  Future<Map<String, int>> getDailyCompletionCounts(
    String goalId, {
    int days = 30,
  }) async {
    final db = await database;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));

    final rows = await db.rawQuery('''
      SELECT date(scheduledDate) as day, COUNT(*) as count FROM tasks
      WHERE goalId = ? AND status = 'completed' AND date(scheduledDate) >= date(?)
      GROUP BY date(scheduledDate)
    ''', [goalId, start.toIso8601String()]);

    final Map<String, int> result = {};
    for (final row in rows) {
      result[row['day'] as String] = row['count'] as int;
    }
    return result;
  }

  /// Computes both the current and longest streak for [goalId] in a
  /// single pass, fetching every task row for the goal just once
  /// instead of querying day-by-day (the old dashboard code ran up to
  /// 30 separate queries on every screen open).
  ///
  /// A "day" only counts toward the streak if it actually had at
  /// least one task scheduled — days with no tasks at all (e.g. a
  /// schedule rule that only runs Mon/Wed/Fri) are rest days and are
  /// skipped rather than treated as a missed day that breaks the
  /// streak. A day only breaks the streak if it had a task that
  /// wasn't completed.
  ///
  /// Today gets a grace period: if today's tasks aren't finished yet
  /// (or don't exist yet), that alone won't break an existing streak —
  /// we simply don't count today, and keep looking backward from
  /// yesterday. The streak only truly breaks on the first *past* day
  /// that had an incomplete/missed task.
  Future<StreakStats> getStreakStats(String goalId) async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'goalId = ?',
      whereArgs: [goalId],
      columns: ['scheduledDate', 'status'],
    );

    // Collapse to one entry per calendar day: true only if *every*
    // task scheduled that day was completed.
    final Map<String, bool> dayCompletion = {};
    for (final m in maps) {
      final dateKey = (m['scheduledDate'] as String).substring(0, 10);
      final completed = m['status'] == TaskStatus.completed.name;
      dayCompletion[dateKey] = (dayCompletion[dateKey] ?? true) && completed;
    }

    // A day the user spent a Streak Freeze token on (see
    // StreakFreezeService) should behave exactly like a natural rest
    // day — dropping it from the map entirely means the loops below
    // need no special-casing at all, they just never see it.
    final frozenKeys = await getFrozenDateKeys(goalId);
    for (final key in frozenKeys) {
      dayCompletion.remove(key);
    }

    if (dayCompletion.isEmpty) {
      return const StreakStats(current: 0, longest: 0);
    }

    final sortedDayKeys = dayCompletion.keys.toList()..sort();

    // Longest streak: longest run of consecutive *entries* in the
    // sorted (rest-day-free) list that are all completed.
    int longest = 0;
    int run = 0;
    for (final key in sortedDayKeys) {
      if (dayCompletion[key]!) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }

    // Current streak: walk backward day-by-day from today.
    String dateKey(DateTime d) =>
        DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);

    final earliestKey = sortedDayKeys.first;
    final today = DateTime.now();
    DateTime cursor = DateTime(today.year, today.month, today.day);
    final todayKey = dateKey(cursor);

    int current = 0;
    bool isFirstDayChecked = true;
    while (dateKey(cursor).compareTo(earliestKey) >= 0) {
      final key = dateKey(cursor);
      final hasEntry = dayCompletion.containsKey(key);

      if (!hasEntry) {
        // Rest day (or today, before any task exists yet) — doesn't
        // break the streak, just isn't counted either.
        cursor = cursor.subtract(const Duration(days: 1));
        isFirstDayChecked = false;
        continue;
      }

      if (dayCompletion[key]!) {
        current++;
        cursor = cursor.subtract(const Duration(days: 1));
        isFirstDayChecked = false;
        continue;
      }

      // Incomplete/missed day. If it's today and still in progress,
      // give it a pass — the day isn't over yet.
      if (isFirstDayChecked && key == todayKey) {
        cursor = cursor.subtract(const Duration(days: 1));
        isFirstDayChecked = false;
        continue;
      }

      break;
    }

    return StreakStats(current: current, longest: longest);
  }

  /// Persists the streak value HomeScreen just showed the user for
  /// this goal — see Goal.lastSeenStreak and
  /// HomeScreen._checkForBrokenStreak, which is what actually compares
  /// the old value to the new one to decide whether a streak just
  /// broke.
  Future<void> updateLastSeenStreak(String goalId, int streak) async {
    final db = await database;
    await db.update(
      'goals',
      {'lastSeenStreak': streak},
      where: 'id = ?',
      whereArgs: [goalId],
    );
  }

  // ---------------- STREAK FREEZES ----------------

  Future<void> insertStreakFreeze(String id, String goalId, DateTime date) async {
    final db = await database;
    final dateKey = DateTime(date.year, date.month, date.day).toIso8601String();
    await db.insert(
      'streak_freezes',
      {
        'id': id,
        'goalId': goalId,
        'date': dateKey,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// All frozen dates for a goal, as `yyyy-MM-dd` keys — passed
  /// straight into [getStreakStats] so a frozen day is excluded from
  /// the completion map entirely, the same way a natural rest day
  /// (no task scheduled) already is.
  Future<Set<String>> getFrozenDateKeys(String goalId) async {
    final db = await database;
    final rows = await db.query(
      'streak_freezes',
      columns: ['date'],
      where: 'goalId = ?',
      whereArgs: [goalId],
    );
    return rows.map((r) => (r['date'] as String).substring(0, 10)).toSet();
  }

  /// How many freeze tokens this goal has already used in the given
  /// month — see StreakFreezeService for the monthly allowance this
  /// is checked against.
  Future<int> countFreezesUsedInMonth(String goalId, DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1).toIso8601String();
    final end = DateTime(month.year, month.month + 1, 1).toIso8601String();
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM streak_freezes
      WHERE goalId = ? AND date >= ? AND date < ?
    ''', [goalId, start, end]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Recent missed calendar days for this goal that haven't already
  /// been frozen — what [StreakFreezeSheet] lets the user pick from.
  /// Capped to the last [withinDays] so a goal with months of history
  /// doesn't dredge up something ancient.
  Future<List<DateTime>> getFreezableMissedDates(
    String goalId, {
    int withinDays = 14,
    int limit = 10,
  }) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: withinDays));
    final rows = await db.rawQuery('''
      SELECT DISTINCT date(scheduledDate) as day FROM tasks
      WHERE goalId = ? AND status = 'missed' AND date(scheduledDate) >= date(?)
      ORDER BY day DESC
    ''', [goalId, since.toIso8601String()]);

    final frozen = await getFrozenDateKeys(goalId);
    final dates = <DateTime>[];
    for (final row in rows) {
      final dayStr = row['day'] as String;
      if (frozen.contains(dayStr)) continue;
      dates.add(DateTime.parse(dayStr));
      if (dates.length >= limit) break;
    }
    return dates;
  }

  // ---------------- PROFILE (local, no login system) ----------------

  Future<UserProfile?> getProfile() async {
    final db = await database;
    final maps = await db.query('profile', where: 'id = 1', limit: 1);
    if (maps.isEmpty) return null;
    return UserProfile.fromMap(maps.first);
  }

  Future<void> saveProfile(UserProfile profile) async {
    final db = await database;
    await db.insert(
      'profile',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marks the welcome/onboarding screen as seen, without touching
  /// whatever name/photo may already be saved. Safe to call even
  /// before any profile row exists.
  Future<void> markOnboarded() async {
    final existing = await getProfile();
    await saveProfile(
      (existing ?? const UserProfile()).copyWith(hasOnboarded: true),
    );
  }

  /// Reads the raw saved theme preference ('light' / 'dark' / null for
  /// "system"). Deliberately kept separate from [UserProfile] — it's a
  /// display setting, not profile data, and reading/writing it directly
  /// avoids needing to touch [UserProfile] (and every place that
  /// constructs one) just to add one field.
  Future<String?> getThemeModeName() async {
    final db = await database;
    final maps = await db.query(
      'profile',
      columns: ['themeMode'],
      where: 'id = 1',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['themeMode'] as String?;
  }

  /// Saves the theme preference. Uses `INSERT OR IGNORE` + `UPDATE`
  /// rather than [saveProfile]'s full-row replace, so this never
  /// clobbers a name/photo that might not have been loaded into memory
  /// by whatever called this (e.g. the very first run, before any
  /// profile row exists at all).
  Future<void> saveThemeModeName(String modeName) async {
    final db = await database;
    await db.insert(
      'profile',
      {'id': 1, 'hasOnboarded': 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      'profile',
      {'themeMode': modeName},
      where: 'id = 1',
    );
  }

  /// Per-hour-of-day (0–23) breakdown of every *resolved* task
  /// (completed or missed) ever scheduled for this goal — the raw
  /// data behind [InsightsService.getBestHours]. Purely a GROUP BY
  /// over the goal's own local `tasks` rows; nothing external.
  Future<List<HourlyCompletionStat>> getHourlyCompletionStats(
    String goalId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT substr(scheduledTime, 1, 2) as hourStr, status, COUNT(*) as cnt
      FROM tasks
      WHERE goalId = ? AND status IN ('completed', 'missed')
      GROUP BY hourStr, status
    ''', [goalId]);

    final Map<int, HourlyCompletionStat> byHour = {};
    for (final row in rows) {
      final hour = int.tryParse(row['hourStr'] as String) ?? 0;
      final status = row['status'] as String;
      final count = row['cnt'] as int;
      final existing = byHour[hour] ??
          HourlyCompletionStat(hour: hour, completed: 0, missed: 0);
      byHour[hour] = HourlyCompletionStat(
        hour: hour,
        completed: existing.completed +
            (status == TaskStatus.completed.name ? count : 0),
        missed:
            existing.missed + (status == TaskStatus.missed.name ? count : 0),
      );
    }

    final list = byHour.values.toList()..sort((a, b) => a.hour.compareTo(b.hour));
    return list;
  }

  // ---------------- BACKUP / RESTORE ----------------

  /// Every table that makes up a goal's "life" — used by both
  /// [exportAllData]/[importAllData] and, in reverse, to decide
  /// delete order on restore. `profile` is included too (name/photo)
  /// so a restored backup feels like getting the whole app back, not
  /// just the goals.
  static const List<String> _backupTables = [
    'goals',
    'goal_phases',
    'schedule_rules',
    'tasks',
    'streak_freezes',
    'task_snoozes',
    'profile',
  ];

  /// Dumps every row of every table above into a plain Map — see
  /// BackupService, which wraps this with a format version + the
  /// export date and writes it to a local JSON file. No table is
  /// filtered or transformed; this is a full local snapshot of the
  /// database, not the redacted view [resetAllData] leaves behind.
  Future<Map<String, dynamic>> exportAllData() async {
    final db = await database;
    final Map<String, dynamic> data = {};
    for (final table in _backupTables) {
      data[table] = await db.query(table);
    }
    return data;
  }

  /// Wipes every table above and replaces it with the rows from
  /// [data] (as produced by [exportAllData]), all inside one
  /// transaction so a failure partway through can't leave the
  /// database half-restored. Deletes in reverse dependency order and
  /// re-inserts in forward order (goals before the phases/tasks that
  /// reference them) even though sqflite doesn't enforce foreign keys
  /// by default here — no reason to rely on that not mattering.
  Future<void> importAllData(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in _backupTables.reversed) {
        await txn.delete(table);
      }
      for (final table in _backupTables) {
        final rows = (data[table] as List?)
                ?.map((r) => Map<String, dynamic>.from(r as Map))
                .toList() ??
            [];
        for (final row in rows) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  // ---------------- RESET ----------------

  /// Wipes every goal, task, and schedule rule — used by the "Reset
  /// All Data" option in Settings. Deliberately does NOT touch the
  /// `profile` table, since a name/photo isn't "app data" in the
  /// sense the user means when they ask for a fresh start.
  Future<void> resetAllData() async {
    final db = await database;
    await db.delete('tasks');
    await db.delete('schedule_rules');
    await db.delete('goal_phases');
    await db.delete('goals');
  }
}
