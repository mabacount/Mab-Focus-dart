import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/constants.dart';
import '../models/music_track.dart';
import '../models/outcome_item.dart';
import '../models/phase_tag.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/scheduled_block.dart';
import '../models/session_note.dart';
import '../models/time_record.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  static bool _isTestDb = false;

  DatabaseService._init();

  /// تزریق دیتابیس تستی (مانند SQLite درون‌حافظه‌ای) برای تست‌های خودکار
  @visibleForTesting
  void setTestDatabase(Database db) {
    _database = db;
    _isTestDb = true;
  }

  @visibleForTesting
  void resetForTest() {
    _database = null;
    _isTestDb = false;
  }

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
      version: 5,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA busy_timeout = 5000');
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL');
        } catch (_) {}
      },
      onCreate: createSchemaV5,
      onUpgrade: _upgradeDB,
    );
  }

  @visibleForTesting
  Future<void> createSchemaV5(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        realm TEXT NOT NULL DEFAULT 'work',
        name TEXT NOT NULL,
        parent_id TEXT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        color TEXT NOT NULL DEFAULT '#3B82F6',
        daily_quota_minutes INTEGER NOT NULL DEFAULT 0,
        weekly_quota_minutes INTEGER NOT NULL DEFAULT 0,
        monthly_quota_minutes INTEGER NOT NULL DEFAULT 0,
        hourly_rate REAL NOT NULL DEFAULT 0.0,
        google_calendar_id TEXT NULL,
        created_at TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS outcomes (
        id TEXT PRIMARY KEY,
        realm TEXT NOT NULL DEFAULT 'work',
        project_id TEXT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        completed_at TEXT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS time_records (
        id TEXT PRIMARY KEY,
        realm TEXT NOT NULL DEFAULT 'work',
        clock_mode TEXT NOT NULL DEFAULT 'pomodoro',
        outcome_id TEXT NULL,
        project_id TEXT NULL,
        title_snapshot TEXT NOT NULL DEFAULT 'تسک بدون عنوان',
        is_untitled_draft INTEGER NOT NULL DEFAULT 1,
        tag_ids_json TEXT NOT NULL DEFAULT '[]',
        start_time TEXT NOT NULL,
        end_time TEXT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        overtime_seconds INTEGER NOT NULL DEFAULT 0,
        earned_break_seconds INTEGER NOT NULL DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS session_notes (
        id TEXT PRIMARY KEY,
        realm TEXT NOT NULL DEFAULT 'work',
        note_type TEXT NOT NULL DEFAULT 'general',
        time_record_id TEXT NULL,
        outcome_id TEXT NULL,
        project_id TEXT NULL,
        content TEXT NOT NULL,
        image_paths_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_blocks (
        id TEXT PRIMARY KEY,
        realm TEXT NOT NULL DEFAULT 'work',
        title TEXT NOT NULL,
        project_id TEXT NULL,
        outcome_id TEXT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        is_recurring_weekly INTEGER NOT NULL DEFAULT 0,
        weekday INTEGER NULL,
        source TEXT NOT NULL DEFAULT 'local',
        external_event_id TEXT NULL
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

    await _createV5Indexes(db);
    await _seedDefaultPhaseTags(db);
  }

  Future<void> _createV5Indexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_realm_parent ON projects(realm, parent_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_outcomes_realm_completed ON outcomes(realm, is_completed)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_outcomes_project ON outcomes(project_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_records_realm_start ON time_records(realm, start_time)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_records_outcome ON time_records(outcome_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_records_project ON time_records(project_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_record ON session_notes(time_record_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_outcome ON session_notes(outcome_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_project ON session_notes(project_id)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await migrateV4ToV5(db);
    }
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [tableName],
    );
    return res.isNotEmpty;
  }

  Future<Set<String>> _getTableColumns(Database db, String tableName) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows.map((r) => r['name'].toString()).toSet();
  }

  /// مهاجرت ایمن و کامل داده‌های نسخه ۴ (v3.0) به ساختار نسخه ۵ (v4.0)
  @visibleForTesting
  Future<void> migrateV4ToV5(Database db) async {
    final nowIso = DateTime.now().toIso8601String();

    // ۱. ارتقای جدول projects
    if (await _tableExists(db, 'projects')) {
      final cols = await _getTableColumns(db, 'projects');
      if (!cols.contains('realm')) {
        await db.execute(
            "ALTER TABLE projects ADD COLUMN realm TEXT NOT NULL DEFAULT 'work'");
      }
      if (!cols.contains('status')) {
        await db.execute(
            "ALTER TABLE projects ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
        if (cols.contains('archived')) {
          await db.execute(
              "UPDATE projects SET status = 'archived' WHERE archived = 1");
        }
      }
      if (!cols.contains('daily_quota_minutes')) {
        await db.execute(
            'ALTER TABLE projects ADD COLUMN daily_quota_minutes INTEGER NOT NULL DEFAULT 0');
      }
      if (!cols.contains('weekly_quota_minutes')) {
        await db.execute(
            'ALTER TABLE projects ADD COLUMN weekly_quota_minutes INTEGER NOT NULL DEFAULT 0');
      }
      if (!cols.contains('monthly_quota_minutes')) {
        await db.execute(
            'ALTER TABLE projects ADD COLUMN monthly_quota_minutes INTEGER NOT NULL DEFAULT 0');
      }
      if (!cols.contains('hourly_rate')) {
        await db.execute(
            'ALTER TABLE projects ADD COLUMN hourly_rate REAL NOT NULL DEFAULT 0.0');
      }
      if (!cols.contains('google_calendar_id')) {
        await db.execute(
            'ALTER TABLE projects ADD COLUMN google_calendar_id TEXT NULL');
      }
      if (!cols.contains('created_at')) {
        await db.execute(
            "ALTER TABLE projects ADD COLUMN created_at TEXT NOT NULL DEFAULT ''");
        await db.execute(
            "UPDATE projects SET created_at = ? WHERE created_at = ''",
            [nowIso]);
      }
    }

    // ۲. ارتقای جدول scheduled_blocks
    if (await _tableExists(db, 'scheduled_blocks')) {
      final cols = await _getTableColumns(db, 'scheduled_blocks');
      if (!cols.contains('realm')) {
        await db.execute(
            "ALTER TABLE scheduled_blocks ADD COLUMN realm TEXT NOT NULL DEFAULT 'work'");
      }
      if (!cols.contains('outcome_id')) {
        await db.execute(
            'ALTER TABLE scheduled_blocks ADD COLUMN outcome_id TEXT NULL');
      }
    }

    // ۳. ساخت جداول جدید در صورت نبودن
    await createSchemaV5(db, 5);

    // ۴. مهاجرت task_logs به outcomes و time_records
    final Map<String, Map<String, dynamic>> migratedRecordsById = {};
    if (await _tableExists(db, 'task_logs')) {
      final oldLogs = await db.query('task_logs', orderBy: 'start_time ASC');

      const genericBreakTitles = {
        'استراحت ۵ دقیقه‌ای',
        'استراحت طولانی (زندگی)',
        'استراحت کوتاه‌مدت',
        'کرنومتر زندگی و استراحت آزاد',
        'زندگی و استراحت آزاد',
      };

      // گروه‌بندی کارهای واقعی بر اساس group_id برای تبدیل به یک OutcomeItem یکتا
      final Map<String, List<Map<String, dynamic>>> outcomeGroups = {};
      final Map<String, String> logIdToOutcomeId = {};

      String resolveRealm(Map<String, dynamic> row) {
        final entryType = row['entry_type'] as String? ?? 'work';
        final title = (row['title'] as String? ?? '').trim();
        if (entryType == 'short_break' || entryType == 'long_break') {
          return 'life';
        }
        if (entryType == 'stopwatch' &&
            (title.contains('زندگی') ||
                title.contains('استراحت') ||
                title.contains('خواب'))) {
          return 'life';
        }
        return 'work';
      }

      for (final row in oldLogs) {
        final id = row['id'] as String;
        final isUntitled = (row['is_untitled_draft'] as int? ?? 0) == 1;
        final title = (row['title'] as String? ?? '').trim();
        final realm = resolveRealm(row);
        final isGenericBreak =
            realm == 'life' && genericBreakTitles.contains(title);

        if (!isUntitled && !isGenericBreak && title.isNotEmpty) {
          final rawGroupId = row['group_id'] as String?;
          final groupKey =
              (rawGroupId != null && rawGroupId.isNotEmpty) ? rawGroupId : id;
          outcomeGroups.putIfAbsent(groupKey, () => []).add(row);
          logIdToOutcomeId[id] = groupKey;
        }
      }

      // درج کارها/اهداف (outcomes)
      for (final entry in outcomeGroups.entries) {
        final groupId = entry.key;
        final groupRows = entry.value;
        final latest = groupRows.last;
        final earliest = groupRows.first;

        final hasWork = groupRows.any((r) => resolveRealm(r) == 'work');
        final realm = hasWork ? 'work' : 'life';
        final bool isCompleted =
            groupRows.any((r) => (r['is_completed'] as int? ?? 0) == 1);
        final projectId = (latest['sub_project_id'] as String?) ??
            (latest['macro_project_id'] as String?);
        final title = (latest['title'] as String? ?? AppDefaults.untitledTaskTitle)
            .trim();
        final createdAt = earliest['start_time'] as String? ?? nowIso;
        final completedAt = isCompleted
            ? ((latest['end_time'] as String?) ??
                (latest['start_time'] as String?) ??
                nowIso)
            : null;

        await db.insert(
          'outcomes',
          {
            'id': groupId,
            'realm': realm,
            'project_id': projectId,
            'title': title,
            'description': '',
            'is_completed': isCompleted ? 1 : 0,
            'created_at': createdAt,
            'completed_at': completedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // درج برش‌های زمانی در time_records
      for (final row in oldLogs) {
        final id = row['id'] as String;
        final realm = resolveRealm(row);
        final entryType = row['entry_type'] as String? ?? 'work';
        final clockMode =
            entryType == 'stopwatch' ? 'stopwatch' : 'pomodoro';
        final outcomeId = logIdToOutcomeId[id];
        final projectId = (row['sub_project_id'] as String?) ??
            (row['macro_project_id'] as String?);
        final durationSec = row['duration_seconds'] as int? ?? 0;
        final earnedBreakSec = realm == 'work' ? (durationSec ~/ 5) : 0;

        final recordMap = {
          'id': id,
          'realm': realm,
          'clock_mode': clockMode,
          'outcome_id': outcomeId,
          'project_id': projectId,
          'title_snapshot':
              row['title'] as String? ?? AppDefaults.untitledTaskTitle,
          'is_untitled_draft': row['is_untitled_draft'] as int? ?? 0,
          'tag_ids_json': row['tag_ids_json'] as String? ?? '[]',
          'start_time': row['start_time'] as String,
          'end_time': row['end_time'] as String?,
          'duration_seconds': durationSec,
          'overtime_seconds': row['overtime_seconds'] as int? ?? 0,
          'earned_break_seconds': earnedBreakSec,
          'is_edited': row['is_edited'] as int? ?? 0,
          'original_start_time': row['original_start_time'] as String?,
          'original_end_time': row['original_end_time'] as String?,
          'original_duration_seconds':
              row['original_duration_seconds'] as int?,
          'edited_at': row['edited_at'] as String?,
          'edit_note': row['edit_note'] as String?,
          'sync_status': row['sync_status'] as String? ?? 'pending',
          'calendar_event_id': row['calendar_event_id'] as String?,
          'target_calendar_id': row['target_calendar_id'] as String?,
        };

        migratedRecordsById[id] = recordMap;
        await db.insert(
          'time_records',
          recordMap,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // ۵. مهاجرت work_notes به session_notes با حفظ اتصال سه‌گانه
    if (await _tableExists(db, 'work_notes')) {
      final oldNotes = await db.query('work_notes', orderBy: 'created_at ASC');
      for (final row in oldNotes) {
        final taskLogId = row['task_log_id'] as String?;
        final linkedRecord =
            taskLogId != null ? migratedRecordsById[taskLogId] : null;

        final realm = (linkedRecord?['realm'] as String?) ?? 'work';
        final outcomeId = linkedRecord?['outcome_id'] as String?;
        final projectId = (row['project_id'] as String?) ??
            (linkedRecord?['project_id'] as String?);
        final legacyTitle = (row['task_title'] as String? ?? '').trim();
        String content = row['content'] as String? ?? '';
        if (taskLogId == null &&
            legacyTitle.isNotEmpty &&
            legacyTitle != AppDefaults.untitledTaskTitle &&
            !content.contains(legacyTitle)) {
          content = content.isEmpty ? legacyTitle : '[$legacyTitle]\n$content';
        }

        await db.insert(
          'session_notes',
          {
            'id': row['id'] as String,
            'realm': realm,
            'note_type': 'report',
            'time_record_id': taskLogId,
            'outcome_id': outcomeId,
            'project_id': projectId,
            'content': content,
            'image_paths_json': row['image_paths_json'] as String? ?? '[]',
            'created_at': row['created_at'] as String? ?? nowIso,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
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

  // ==================== توابع بازگشتی درخت پروژه‌ها ====================

  /// گرفتن تمام شناسه‌های فرزندان و نوادگان یک پروژه در درخت بی‌نهایت سطحی
  static Set<String> getDescendantProjectIds(
    String rootProjectId,
    List<ProjectNode> allProjects,
  ) {
    final Set<String> result = {};
    final List<String> queue = [rootProjectId];
    final Set<String> visited = {rootProjectId};

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      for (final p in allProjects) {
        if (p.parentId == currentId && !visited.contains(p.id)) {
          visited.add(p.id);
          result.add(p.id);
          queue.add(p.id);
        }
      }
    }
    return result;
  }

  /// گرفتن شناسه خود پروژه به همراه تمام زیرپروژه‌های تودرتوی آن
  static Set<String> getProjectAndDescendantIds(
    String rootProjectId,
    List<ProjectNode> allProjects,
  ) {
    final ids = getDescendantProjectIds(rootProjectId, allProjects);
    ids.add(rootProjectId);
    return ids;
  }

  /// محاسبه نرخ ساعتی مؤثر با ارث‌بری بازگشتی از اولین پروژه مادر دارای نرخ (چالش ۶)
  static double getEffectiveHourlyRate(
    String? projectId,
    List<ProjectNode> allProjects,
  ) {
    if (projectId == null) return 0.0;
    final Map<String, ProjectNode> byId = {
      for (final p in allProjects) p.id: p
    };
    String? currentId = projectId;
    final Set<String> visited = {};

    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);
      final node = byId[currentId];
      if (node == null) break;
      if (node.hourlyRate > 0) return node.hourlyRate;
      currentId = node.parentId;
    }
    return 0.0;
  }

  /// گرفتن تقویم گوگل مؤثر با ارث‌بری بازگشتی از پروژه مادر در صورت نبود تقویم اختصاصی
  static String? getEffectiveGoogleCalendarId(
    String? projectId,
    List<ProjectNode> allProjects,
  ) {
    if (projectId == null) return null;
    final Map<String, ProjectNode> byId = {
      for (final p in allProjects) p.id: p
    };
    String? currentId = projectId;
    final Set<String> visited = {};

    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);
      final node = byId[currentId];
      if (node == null) break;
      if (node.googleCalendarId != null &&
          node.googleCalendarId!.trim().isNotEmpty) {
        return node.googleCalendarId!.trim();
      }
      currentId = node.parentId;
    }
    return null;
  }

  /// مسیر کامل سلسله‌مراتب یک پروژه از ریشه تا خود پروژه
  static List<ProjectNode> getProjectBreadcrumb(
    String? projectId,
    List<ProjectNode> allProjects,
  ) {
    if (projectId == null) return [];
    final Map<String, ProjectNode> byId = {
      for (final p in allProjects) p.id: p
    };
    final List<ProjectNode> chain = [];
    String? currentId = projectId;
    final Set<String> visited = {};

    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);
      final node = byId[currentId];
      if (node == null) break;
      chain.insert(0, node);
      currentId = node.parentId;
    }
    return chain;
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
    final allProjects = await getProjects(includeArchived: true);
    final toDelete = getProjectAndDescendantIds(id, allProjects);

    await db.transaction((txn) async {
      for (final pid in toDelete) {
        await txn.update(
          'outcomes',
          {'project_id': null},
          where: 'project_id = ?',
          whereArgs: [pid],
        );
        await txn.update(
          'time_records',
          {'project_id': null},
          where: 'project_id = ?',
          whereArgs: [pid],
        );
        await txn.update(
          'session_notes',
          {'project_id': null},
          where: 'project_id = ?',
          whereArgs: [pid],
        );
        await txn.update(
          'scheduled_blocks',
          {'project_id': null},
          where: 'project_id = ?',
          whereArgs: [pid],
        );
        await txn.delete('projects', where: 'id = ?', whereArgs: [pid]);
      }
    });
  }

  Future<List<ProjectNode>> getProjects({
    bool includeArchived = false,
    AppRealm? realm,
  }) async {
    final db = await database;
    final List<String> conditions = [];
    final List<Object?> args = [];
    if (!includeArchived) {
      conditions.add("status != 'archived'");
    }
    if (realm != null) {
      conditions.add('realm = ?');
      args.add(realm.dbValue);
    }

    final maps = await db.query(
      'projects',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at ASC, name ASC',
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

  // ==================== مدیریت کارها / اهداف (Outcomes) ====================

  Future<void> insertOutcome(OutcomeItem outcome) async {
    final db = await database;
    await db.insert('outcomes', outcome.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateOutcome(OutcomeItem outcome) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('outcomes', outcome.toMap(),
          where: 'id = ?', whereArgs: [outcome.id]);
      // اعمال قانون یکپارچگی پروژه بر رکوردها و یادداشت‌های متصل به این کار
      await txn.update(
        'time_records',
        {
          'project_id': outcome.projectId,
          'title_snapshot': outcome.title,
        },
        where: 'outcome_id = ?',
        whereArgs: [outcome.id],
      );
      await txn.update(
        'session_notes',
        {'project_id': outcome.projectId},
        where: 'outcome_id = ?',
        whereArgs: [outcome.id],
      );
    });
  }

  Future<void> markOutcomeCompleted(String id) async {
    final db = await database;
    await db.update(
      'outcomes',
      {
        'is_completed': 1,
        'completed_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reopenOutcome(String id) async {
    final db = await database;
    await db.update(
      'outcomes',
      {
        'is_completed': 0,
        'completed_at': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteOutcome(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'time_records',
        {'outcome_id': null},
        where: 'outcome_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'session_notes',
        {'outcome_id': null},
        where: 'outcome_id = ?',
        whereArgs: [id],
      );
      await txn.delete('outcomes', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<OutcomeItem?> getOutcomeById(String id) async {
    final db = await database;
    final maps =
        await db.query('outcomes', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isNotEmpty) {
      return OutcomeItem.fromMap(maps.first);
    }
    return null;
  }

  Future<List<OutcomeItem>> getOutcomes({
    AppRealm? realm,
    bool? onlyOpen,
  }) async {
    final db = await database;
    final List<String> conditions = [];
    final List<Object?> args = [];
    if (realm != null) {
      conditions.add('realm = ?');
      args.add(realm.dbValue);
    }
    if (onlyOpen == true) {
      conditions.add('is_completed = 0');
    } else if (onlyOpen == false) {
      conditions.add('is_completed = 1');
    }

    final maps = await db.query(
      'outcomes',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return maps.map((e) => OutcomeItem.fromMap(e)).toList();
  }

  // ==================== مدیریت رکوردهای زمانی (Time Records) ====================

  Future<void> insertTimeRecord(TimeRecord record) async {
    final db = await database;
    await db.insert('time_records', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateTimeRecord(TimeRecord record,
      {bool cascadeNotes = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('time_records', record.toMap(),
          where: 'id = ?', whereArgs: [record.id]);
      if (cascadeNotes) {
        await txn.update(
          'session_notes',
          {
            'realm': record.realm.dbValue,
            'outcome_id': record.outcomeId,
            'project_id': record.projectId,
          },
          where: 'time_record_id = ?',
          whereArgs: [record.id],
        );
      }
    });
  }

  Future<void> deleteTimeRecord(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'session_notes',
        {'time_record_id': null},
        where: 'time_record_id = ?',
        whereArgs: [id],
      );
      await txn.delete('time_records', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<TimeRecord?> getTimeRecordById(String id) async {
    final db = await database;
    final maps = await db.query('time_records',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isNotEmpty) {
      return TimeRecord.fromMap(maps.first);
    }
    return null;
  }

  Future<List<TimeRecord>> getAllTimeRecords({AppRealm? realm}) async {
    final db = await database;
    final maps = await db.query(
      'time_records',
      where: realm != null ? 'realm = ?' : null,
      whereArgs: realm != null ? [realm.dbValue] : null,
      orderBy: 'start_time DESC',
    );
    return maps.map((e) => TimeRecord.fromMap(e)).toList();
  }

  /// دریافت رکوردهای باز (end_time IS NULL) جهت بازیابی پس از کرش یا بستن اپ (چالش ۳)
  Future<List<TimeRecord>> getOpenTimeRecords() async {
    final db = await database;
    final maps = await db.query(
      'time_records',
      where: 'end_time IS NULL',
      orderBy: 'start_time DESC',
    );
    return maps.map((e) => TimeRecord.fromMap(e)).toList();
  }

  Future<List<TimeRecord>> getUntitledDraftRecords({AppRealm? realm}) async {
    final db = await database;
    final maps = await db.query(
      'time_records',
      where: realm != null
          ? 'is_untitled_draft = 1 AND realm = ?'
          : 'is_untitled_draft = 1',
      whereArgs: realm != null ? [realm.dbValue] : null,
      orderBy: 'start_time DESC',
    );
    return maps.map((e) => TimeRecord.fromMap(e)).toList();
  }

  Future<List<TimeRecord>> getRecordsByDateRange(
    DateTime start,
    DateTime end, {
    AppRealm? realm,
  }) async {
    final db = await database;
    final whereStr = realm != null
        ? 'start_time >= ? AND start_time <= ? AND realm = ?'
        : 'start_time >= ? AND start_time <= ?';
    final args = realm != null
        ? [start.toIso8601String(), end.toIso8601String(), realm.dbValue]
        : [start.toIso8601String(), end.toIso8601String()];

    final maps = await db.query(
      'time_records',
      where: whereStr,
      whereArgs: args,
      orderBy: 'start_time ASC',
    );
    return maps.map((e) => TimeRecord.fromMap(e)).toList();
  }

  /// ویرایش رکورد با ثبت ممیزی [Edited] و اعمال CASCADE UPDATE روی session_notes
  Future<TimeRecord> updateTimeRecordWithAudit({
    required String id,
    required String newTitle,
    AppRealm? newRealm,
    String? newOutcomeId,
    bool clearOutcomeId = false,
    String? newProjectId,
    bool clearProjectId = false,
    required List<String> newTagIds,
    required DateTime newStartTime,
    required DateTime newEndTime,
    required int newDurationSeconds,
    String? editNote,
  }) async {
    final oldRecord = await getTimeRecordById(id);
    if (oldRecord == null) {
      throw Exception('TimeRecord not found with id: $id');
    }

    // اعمال قانون وراثت پروژه: اگر کار/هدف دارای پروژه باشد، پروژه از کار به ارث برده می‌شود
    String? effectiveOutcomeId =
        clearOutcomeId ? null : (newOutcomeId ?? oldRecord.outcomeId);
    String? effectiveProjectId =
        clearProjectId ? null : (newProjectId ?? oldRecord.projectId);
    if (effectiveOutcomeId != null) {
      final outcome = await getOutcomeById(effectiveOutcomeId);
      if (outcome != null && outcome.projectId != null) {
        effectiveProjectId = outcome.projectId;
      }
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

    final String cleanTitle = newTitle.trim().isEmpty
        ? AppDefaults.untitledTaskTitle
        : newTitle.trim();
    final bool isStillUntitled = cleanTitle == AppDefaults.untitledTaskTitle;
    final AppRealm finalRealm = newRealm ?? oldRecord.realm;
    final int newEarnedBreak = finalRealm == AppRealm.work
        ? (newDurationSeconds ~/ AppDurations.defaultBreakRatio)
        : 0;

    final updated = oldRecord.copyWith(
      realm: finalRealm,
      outcomeId: effectiveOutcomeId,
      clearOutcomeId: effectiveOutcomeId == null,
      projectId: effectiveProjectId,
      clearProjectId: effectiveProjectId == null,
      titleSnapshot: cleanTitle,
      isUntitledDraft: isStillUntitled,
      tagIds: newTagIds,
      startTime: newStartTime,
      endTime: newEndTime,
      durationSeconds: newDurationSeconds,
      earnedBreakSeconds: newEarnedBreak,
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
    await db.transaction((txn) async {
      await txn.update('time_records', updated.toMap(),
          where: 'id = ?', whereArgs: [id]);
      // CASCADE UPDATE روی یادداشت‌های متصل به این رکورد
      await txn.update(
        'session_notes',
        {
          'realm': updated.realm.dbValue,
          'outcome_id': updated.outcomeId,
          'project_id': updated.projectId,
        },
        where: 'time_record_id = ?',
        whereArgs: [id],
      );
    });

    return updated;
  }

  // ==================== مدیریت یادداشت‌های حین کار (Session Notes) ====================

  Future<void> insertSessionNote(SessionNote note) async {
    final db = await database;
    await db.insert('session_notes', note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSessionNote(SessionNote note) async {
    final db = await database;
    await db.update('session_notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
  }

  Future<void> deleteSessionNote(String id) async {
    final db = await database;
    await db.delete('session_notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SessionNote>> getAllSessionNotes({AppRealm? realm}) async {
    final db = await database;
    final maps = await db.query(
      'session_notes',
      where: realm != null ? 'realm = ?' : null,
      whereArgs: realm != null ? [realm.dbValue] : null,
      orderBy: 'created_at DESC',
    );
    return maps.map((e) => SessionNote.fromMap(e)).toList();
  }

  Future<List<SessionNote>> getSessionNotesForRecord(
      String timeRecordId) async {
    final db = await database;
    final maps = await db.query(
      'session_notes',
      where: 'time_record_id = ?',
      whereArgs: [timeRecordId],
      orderBy: 'created_at DESC',
    );
    return maps.map((e) => SessionNote.fromMap(e)).toList();
  }

  Future<List<SessionNote>> getSessionNotesForOutcome(String outcomeId) async {
    final db = await database;
    final maps = await db.query(
      'session_notes',
      where: 'outcome_id = ?',
      whereArgs: [outcomeId],
      orderBy: 'created_at DESC',
    );
    return maps.map((e) => SessionNote.fromMap(e)).toList();
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
    DateTime start,
    DateTime end, {
    AppRealm? realm,
  }) async {
    final db = await database;
    final whereStr = realm != null
        ? 'start_time >= ? AND start_time <= ? AND realm = ?'
        : 'start_time >= ? AND start_time <= ?';
    final args = realm != null
        ? [start.toIso8601String(), end.toIso8601String(), realm.dbValue]
        : [start.toIso8601String(), end.toIso8601String()];

    final maps = await db.query(
      'scheduled_blocks',
      where: whereStr,
      whereArgs: args,
      orderBy: 'start_time ASC',
    );
    return maps.map((e) => ScheduledBlock.fromMap(e)).toList();
  }

  // ==================== مدیریت پلی‌لیست‌های موسیقی ====================

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

  // ==================== تنظیمات برنامه و وضعیت موتور ====================

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
    if (_isTestDb) return;
    final db = await database;
    await db.close();
  }
}
