import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/project_node.dart';
import '../models/phase_tag.dart';
import '../models/task_log_entry.dart';
import '../models/scheduled_block.dart';
import '../models/music_track.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mab_focus_v3.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String dbPath;
    if (Platform.isWindows || Platform.isLinux) {
      final appSupportDir = await getApplicationSupportDirectory();
      final appDir = Directory(p.join(appSupportDir.path, 'MabFocus'));
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      dbPath = p.join(appDir.path, filePath);
    } else {
      final databasesPath = await getDatabasesPath();
      dbPath = p.join(databasesPath, filePath);
    }

    return await openDatabase(
      dbPath,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        color TEXT NOT NULL DEFAULT '#3B82F6',
        count_short_breaks_as_work INTEGER NOT NULL DEFAULT 0,
        count_long_breaks_as_work INTEGER NOT NULL DEFAULT 0,
        daily_quota_minutes INTEGER NOT NULL DEFAULT 0,
        weekly_quota_minutes INTEGER NOT NULL DEFAULT 0,
        monthly_quota_minutes INTEGER NOT NULL DEFAULT 0,
        hourly_rate REAL NOT NULL DEFAULT 0.0,
        google_calendar_id TEXT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS phase_tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'phase',
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_logs (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        entry_type TEXT NOT NULL DEFAULT 'work',
        title TEXT NOT NULL DEFAULT 'تسک بدون عنوان',
        is_untitled_draft INTEGER NOT NULL DEFAULT 1,
        is_completed INTEGER NOT NULL DEFAULT 0,
        macro_project_id TEXT NULL,
        sub_project_id TEXT NULL,
        tag_ids_json TEXT NOT NULL DEFAULT '[]',
        start_time TEXT NOT NULL,
        end_time TEXT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        overtime_seconds INTEGER NOT NULL DEFAULT 0,
        pomodoro_set_index INTEGER NOT NULL DEFAULT 1,
        is_edited INTEGER NOT NULL DEFAULT 0,
        original_start_time TEXT NULL,
        original_end_time TEXT NULL,
        original_duration_seconds INTEGER NULL,
        edited_at TEXT NULL,
        edit_note TEXT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        calendar_event_id TEXT NULL,
        target_calendar_id TEXT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_blocks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        project_id TEXT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        is_recurring_weekly INTEGER NOT NULL DEFAULT 0,
        weekday INTEGER NULL,
        source TEXT NOT NULL DEFAULT 'local',
        external_event_id TEXT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS music_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        folder_path TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _seedDefaultPhaseTags(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await _createDB(db, newVersion);
    }
  }

  Future<void> _seedDefaultPhaseTags(Database db) async {
    final defaultTags = [
      {
        'id': 'phase_planning',
        'name': 'برنامه‌ریزی اولیه',
        'category': 'phase',
        'archived': 0
      },
      {
        'id': 'phase_execution',
        'name': 'اجرا و توسعه',
        'category': 'phase',
        'archived': 0
      },
      {
        'id': 'phase_debugging',
        'name': 'نظارت و دیباگ',
        'category': 'phase',
        'archived': 0
      },
      {
        'id': 'phase_wrapup',
        'name': 'اختتامیه و مستندسازی',
        'category': 'phase',
        'archived': 0
      },
    ];

    for (final tag in defaultTags) {
      await db.insert('phase_tags', tag,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ==================== مدیریت پروژه‌ها (Projects) ====================

  Future<void> insertProject(ProjectNode project) async {
    final db = await database;
    await db.insert('projects', project.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProject(ProjectNode project) async {
    final db = await database;
    await db.update('projects', project.toMap(),
        where: 'id = ?', whereArgs: [project.id]);
  }

  Future<void> deleteProject(String id) async {
    final db = await database;
    await db.delete('projects',
        where: 'id = ? OR parent_id = ?', whereArgs: [id, id]);
  }

  Future<List<ProjectNode>> getProjects({bool includeArchived = false}) async {
    final db = await database;
    final maps = await db.query(
      'projects',
      where: includeArchived ? null : "status != 'archived'",
    );
    return maps.map((e) => ProjectNode.fromMap(e)).toList();
  }

  Future<ProjectNode?> getProjectById(String id) async {
    final db = await database;
    final maps =
        await db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isNotEmpty) {
      return ProjectNode.fromMap(maps.first);
    }
    return null;
  }

  // ==================== مدیریت تگ‌ها (Phase Tags) ====================

  Future<void> insertPhaseTag(PhaseTag tag) async {
    final db = await database;
    await db.insert('phase_tags', tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePhaseTag(PhaseTag tag) async {
    final db = await database;
    await db.update('phase_tags', tag.toMap(),
        where: 'id = ?', whereArgs: [tag.id]);
  }

  Future<void> deletePhaseTag(String id) async {
    final db = await database;
    await db.delete('phase_tags', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PhaseTag>> getPhaseTags({bool includeArchived = false}) async {
    final db = await database;
    final maps = await db.query(
      'phase_tags',
      where: includeArchived ? null : 'archived = 0',
    );
    return maps.map((e) => PhaseTag.fromMap(e)).toList();
  }

  // ==================== مدیریت لاگ کارکرد (Task Logs) ====================

  Future<void> insertTaskLog(TaskLogEntry entry) async {
    final db = await database;
    await db.insert('task_logs', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateTaskLog(TaskLogEntry entry) async {
    final db = await database;
    await db.update('task_logs', entry.toMap(),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<void> deleteTaskLog(String id) async {
    final db = await database;
    await db.delete('task_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<TaskLogEntry?> getTaskLogById(String id) async {
    final db = await database;
    final maps =
        await db.query('task_logs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isNotEmpty) {
      return TaskLogEntry.fromMap(maps.first);
    }
    return null;
  }

  Future<List<TaskLogEntry>> getAllTaskLogs() async {
    final db = await database;
    final maps = await db.query('task_logs', orderBy: 'start_time DESC');
    return maps.map((e) => TaskLogEntry.fromMap(e)).toList();
  }

  Future<List<TaskLogEntry>> getIncompleteTasks() async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      where:
          "is_completed = 0 AND entry_type = 'work' AND is_untitled_draft = 0",
      orderBy: 'start_time DESC',
    );
    return maps.map((e) => TaskLogEntry.fromMap(e)).toList();
  }

  Future<List<TaskLogEntry>> getUntitledDraftLogs() async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      where: 'is_untitled_draft = 1',
      orderBy: 'start_time DESC',
    );
    return maps.map((e) => TaskLogEntry.fromMap(e)).toList();
  }

  Future<List<TaskLogEntry>> getLogsByDateRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      where: 'start_time >= ? AND start_time <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'start_time ASC',
    );
    return maps.map((e) => TaskLogEntry.fromMap(e)).toList();
  }

  Future<TaskLogEntry> updateTaskLogWithAudit({
    required String id,
    required String newTitle,
    String? newMacroProjectId,
    String? newSubProjectId,
    required List<String> newTagIds,
    required DateTime newStartTime,
    required DateTime newEndTime,
    required int newDurationSeconds,
    bool? isCompleted,
    String? editNote,
  }) async {
    final oldRecord = await getTaskLogById(id);
    if (oldRecord == null) {
      throw Exception('Record not found with id: $id');
    }

    final bool startChanged =
        oldRecord.startTime.difference(newStartTime).inSeconds.abs() > 1;
    final bool endChanged = oldRecord.endTime != null &&
        oldRecord.endTime!.difference(newEndTime).inSeconds.abs() > 1;
    final bool durationChanged =
        (oldRecord.durationSeconds - newDurationSeconds).abs() > 1;
    final bool timeWasModified = startChanged || endChanged || durationChanged;

    bool isEdited = oldRecord.isEdited;
    DateTime? origStart = oldRecord.originalStartTime;
    DateTime? origEnd = oldRecord.originalEndTime;
    int? origDuration = oldRecord.originalDurationSeconds;
    DateTime? editedAt = oldRecord.editedAt;

    if (timeWasModified) {
      isEdited = true;
      editedAt = DateTime.now();
      if (!oldRecord.isEdited) {
        origStart = oldRecord.startTime;
        origEnd = oldRecord.endTime;
        origDuration = oldRecord.durationSeconds;
      }
    }

    final String cleanTitle =
        newTitle.trim().isEmpty ? 'تسک بدون عنوان' : newTitle.trim();
    final bool isStillUntitled = cleanTitle == 'تسک بدون عنوان';

    final updated = oldRecord.copyWith(
      title: cleanTitle,
      isUntitledDraft: isStillUntitled,
      isCompleted: isCompleted ?? oldRecord.isCompleted,
      macroProjectId: newMacroProjectId,
      subProjectId: newSubProjectId,
      tagIds: newTagIds,
      startTime: newStartTime,
      endTime: newEndTime,
      durationSeconds: newDurationSeconds,
      isEdited: isEdited,
      originalStartTime: origStart,
      originalEndTime: origEnd,
      originalDurationSeconds: origDuration,
      editedAt: editedAt,
      editNote: timeWasModified
          ? (editNote ?? oldRecord.editNote)
          : oldRecord.editNote,
      syncStatus: 'pending',
    );

    final db = await database;
    await db
        .update('task_logs', updated.toMap(), where: 'id = ?', whereArgs: [id]);
    return updated;
  }

  // ==================== مدیریت بلوک‌های برنامه‌ریزی‌شده (Scheduled Blocks) ====================

  Future<void> insertScheduledBlock(ScheduledBlock block) async {
    final db = await database;
    await db.insert('scheduled_blocks', block.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateScheduledBlock(ScheduledBlock block) async {
    final db = await database;
    await db.update('scheduled_blocks', block.toMap(),
        where: 'id = ?', whereArgs: [block.id]);
  }

  Future<void> deleteScheduledBlock(String id) async {
    final db = await database;
    await db.delete('scheduled_blocks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ScheduledBlock>> getScheduledBlocksInRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'scheduled_blocks',
      where: 'start_time >= ? AND start_time <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'start_time ASC',
    );
    return maps.map((e) => ScheduledBlock.fromMap(e)).toList();
  }

  // ==================== مدیریت پلی‌لیست‌های موسیقی (Music Playlists) ====================

  Future<void> insertMusicPlaylist(MusicPlaylist playlist) async {
    final db = await database;
    await db.insert('music_playlists', playlist.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MusicPlaylist>> getAllMusicPlaylists() async {
    final db = await database;
    final maps = await db.query('music_playlists', orderBy: 'name ASC');
    return maps.map((e) => MusicPlaylist.fromMap(e)).toList();
  }

  Future<void> deleteMusicPlaylist(String id) async {
    final db = await database;
    await db.delete('music_playlists', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== تنظیمات برنامه (App Settings) ====================

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key, {String? defaultValue}) async {
    final db = await database;
    final maps = await db.query('app_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return defaultValue;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
