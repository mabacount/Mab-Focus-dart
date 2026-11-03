import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/project_node.dart';
import '../models/phase_tag.dart';
import '../models/task_log_entry.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mab_focus.db');
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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT NULL,
        count_short_breaks_as_work INTEGER NOT NULL DEFAULT 0,
        count_long_breaks_as_work INTEGER NOT NULL DEFAULT 0,
        color TEXT NOT NULL DEFAULT '#3B82F6',
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE phase_tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'phase',
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE task_logs (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT 'تسک بدون عنوان',
        is_untitled_draft INTEGER NOT NULL DEFAULT 1,
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
        calendar_event_id TEXT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _seedDefaultPhaseTags(db);
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
      where: includeArchived ? null : 'archived = 0',
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

  // ==================== مدیریت تگ‌های فاز (Phase Tags) ====================

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

  Future<List<TaskLogEntry>> getUntitledDraftLogs() async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      where: 'is_untitled_draft = 1',
      orderBy: 'start_time DESC',
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
