# Aspire Lock — Goal & Habit Accountability App

Aspire Lock is a **cross-platform (Flutter) personal goal-tracking and habit-accountability app**. Users define long-term **Goals** (e.g. Weight Loss, Study, Business, Health), break them into **Phases**, and the app auto-generates **daily scheduled Tasks** for each phase. Task completion is verified with **camera photo proof**, and the app tracks **streaks** (with a "streak freeze" safety net) to keep users motivated. It works fully **offline**, with all data stored locally on-device — there is no login/account system.

---

## 1. Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Local Database | SQLite (via `sqflite`) |
| Notifications & Alarms | `flutter_local_notifications`, `android_alarm_manager_plus`, `timezone` |
| Camera / Photo Proof | `camera`, `image_picker`, `permission_handler` |
| Fonts / Theming | `google_fonts` |
| Utilities | `path_provider`, `path`, `intl`, `package_info_plus` |
| Platforms | Android, iOS, Web, Windows, macOS, Linux (via Flutter's multi-platform support) |

---

## 2. Project Structure

```
aspire_lock/
├── lib/
│   ├── main.dart                  # App entry point, theme init, Android boot-resync alarm setup
│   ├── constants/                 # App colors, text styles
│   ├── models/                    # GoalModel, GoalPhaseModel, ScheduleModel, TaskModel,
│   │                               # TaskSnoozeModel, ProfileModel
│   ├── database/
│   │   └── db_helper.dart         # All SQLite table definitions & queries (single data-access layer)
│   ├── services/                  # AI schedule service, backup service, boot sync service,
│   │                               # camera proof service, insights service, notification service,
│   │                               # streak freeze service, task generation/status services, theme controller
│   ├── screens/
│   │   ├── onboarding/            # Welcome, goal category selection, permissions, app entry
│   │   ├── dashboard/             # Dashboard tab, progress dashboard
│   │   ├── goal/                  # Achievements, goal achieved screen
│   │   ├── schedule/              # Create phase, manage schedule, phase list
│   │   ├── task/                  # Task complete, celebration, proof photo viewer
│   │   ├── alarm/                 # Full-screen alarm screen
│   │   ├── settings/              # Settings, backups
│   │   ├── home_screen.dart
│   │   └── main_nav_screen.dart   # Bottom navigation shell
│   ├── widgets/                   # Reusable UI: goal card, task tile, streak chart,
│   │                               # completion heatmap, streak freeze/lost sheets, primary button, etc.
│   └── utils/                     # ID generator, navigation service, notification ID, schedule conflict checks
├── android/, ios/, web/, windows/, macos/, linux/   # Platform-specific Flutter projects
├── test/                          # Unit/widget tests
└── pubspec.yaml                   # Dependencies & app metadata
```

---

## 3. Features

### Onboarding
- Welcome screen → goal category selection (Weight Loss, Study, Business, Health, Future, Custom) → permissions screen (camera, notifications, alarms) → app entry.

### Goals & Phases
- Users create a **Goal** under a category, then break it into **Phases** (e.g. "Week 1: Build the habit", "Week 2: Increase intensity"). Only one phase per goal is `active` at a time — earlier phases are `completed`, later ones `upcoming`.

### Scheduling & Tasks
- Each phase has **Schedule Rules** (e.g. "Exercise at 2:00 PM every day") that automatically generate daily **Tasks**.
- An **AI schedule service** assists with generating/suggesting a task schedule.
- Tasks have statuses: `pending`, `inProgress`, `completed`, `missed`.
- **Conflict checking** (`schedule_conflict.dart`) prevents overlapping scheduled tasks.

### Alarms & Notifications
- Tasks trigger **local notifications** and a **full-screen alarm** at their scheduled time (similar to an alarm-clock experience), reminding the user to do the task.
- **Boot Sync Service**: because Android can clear scheduled alarms on device restart, a recurring background alarm (`android_alarm_manager_plus`) automatically re-registers all pending task alarms after every reboot.
- Users can **snooze** an alarm — snoozing requires logging a reason (`TaskSnoozeLog`), which replaced an earlier "Emergency Unlock"/app-locking mechanism that has since been removed from the app.

### Proof of Completion
- To mark a task complete, the user takes a **photo as proof** via the **Camera Proof Service**. Photos can be reviewed later in the **Proof Photo Viewer**.
- Completing a task shows a **Task Celebration** screen for positive reinforcement.

### Streaks & Motivation
- The app tracks **current streak** and **longest streak** per goal (`StreakStats`), visualized via a **streak chart** and a **completion heatmap**.
- A **Streak Freeze** feature lets users protect their streak on an off day (with a dedicated sheet UI), and a **Streak Lost** sheet informs them if a streak breaks.
- An **Achievements** screen and a **Goal Achieved** screen celebrate milestones and completed goals.

### Dashboard & Insights
- A **Progress Dashboard** and **Insights Service** give the user an overview of their progress across goals/tasks over time.

### Settings & Data
- **Settings screen**: theme (light/dark/system) via `ThemeController`, app info (`package_info_plus`), etc.
- **Backup Service** + **Backups screen**: back up and restore local app data.
- **Local-only profile**: no login system — just an optional display name + photo stored in SQLite, used purely for personalization.

---

## 4. Architecture Notes

- **No backend/login** — the entire app is **local-first**: all goals, phases, tasks, streaks, snooze logs, and the user profile are stored in a single **SQLite database** managed by `DBHelper`, which centralizes every table definition and query used across the app.
- **Service layer**: business logic is separated into dedicated services (`task_generation_service`, `task_status_service`, `streak_freeze_service`, `notification_service`, `camera_proof_service`, `boot_sync_service`, `backup_service`, `insights_service`, `ai_schedule_service`) rather than being embedded directly in the UI screens.
- **State/navigation helpers**: `selected_goal_controller.dart` and `navigation_service.dart` manage cross-screen state (which goal is currently selected) and centralized navigation.
- **Platform-aware code**: platform-specific logic (like `android_alarm_manager_plus`, which has no iOS implementation) is guarded with `Platform.isAndroid` checks so the app runs safely across platforms.
- **Environment variables**: the project includes an `env_file_rename_to_dot_env.rtf` note — a `GEMINI_API_KEY` placeholder exists from an earlier AI-scheduling feature, but per the project's own note, it is currently **unused** since that feature was removed.

---

## 5. Setup & Installation

> **Prerequisites:** Flutter SDK installed (Dart SDK `^3.13.1`), and a configured Android/iOS toolchain (Android Studio / Xcode) depending on your target platform.

1. **Clone/Extract the project.**
2. **Install dependencies:**
   ```bash
   flutter pub get
   ```
3. **(Optional) Environment file:** if you plan to reintroduce the AI-scheduling feature, rename `env_file_rename_to_dot_env.rtf` to `.env` and add a `GEMINI_API_KEY`. Not required for normal use, since that feature is currently inactive.
4. **Run the app:**
   ```bash
   flutter run
   ```
   Select a connected device/emulator (Android, iOS, or desktop/web target) when prompted.
5. **Permissions:** on first launch, grant camera, notification, and alarm/exact-alarm permissions when asked (needed for photo-proof and task alarms).

---

## 6. Summary

Aspire Lock is a fully offline, single-user Flutter app that helps people commit to long-term goals by breaking them into phases and daily tasks, enforcing accountability through scheduled alarms and camera-verified proof of completion, and reinforcing consistency through streaks, streak-freezes, and achievement celebrations — all backed by a local SQLite database with no server or account required.

