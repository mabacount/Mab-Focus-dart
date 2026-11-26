import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/outcome_item.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/session_note.dart';
import '../models/time_record.dart';
import 'ecosystem_bridge_service.dart';

/// سرویس پایگاه داده مرکزی اکوسیستم Mab (`mab_core.db`)
/// منبع واحد حقیقت برای پروژه‌ها، ساختار درختی، ادغام‌ها، دستاوردها، لاگ زمان و یادداشت‌ها بین Mab-Focus، Mab-Compass و اپ‌های آینده.
class EcosystemCoreService {
  static final EcosystemCoreService instance = EcosystemCoreService._init();
  EcosystemCoreService._init();

  static const _uuid = Uuid();

  Database? _coreDb;
  String? _testCoreDbPath;
  bool _isTestDisabled = false;
  Future<void> _serialLock = Future.value();

  bool get hasTestCoreOverride => _coreDb != null || _testCoreDbPath != null;

  Future<T> _runSerialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serialLock = _serialLock.then((_) async {
      try {
        final res = await action();
        completer.complete(res);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  @visibleForTesting
  void setTestCoreDatabase(Database db, {String? path}) {
    _coreDb = db;
    _testCoreDbPath = path;
    _isTestDisabled = false;
  }

  @visibleForTesting
  void setCoreDbPathForTest(String path) {
    _coreDb = null;
    _testCoreDbPath = path;
    _isTestDisabled = false;
  }

  @visibleForTesting
  void disableForTest() {
    _isTestDisabled = true;
  }

  @visibleForTesting
  void resetForTest() {
    _coreDb = null;
    _testCoreDbPath = null;
    _isTestDisabled = false;
  }

  /// مسیر پوشه دیتابیس مرکزی `%APPDATA%/MabEcosystem`
  Future<String> getCoreDirectoryPath() async {
    if (_testCoreDbPath != null) {
      return p.dirname(_testCoreDbPath!);
    }
    final envPath = Platform.environment['MAB_ECOSYSTEM_DB_PATH']?.trim();
    if (envPath != null && envPath.isNotEmpty) {
      return p.dirname(envPath);
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        final dir = Directory(p.join(appData.trim(), 'MabEcosystem'));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir.path;
      }
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.parent.parent.path, 'MabEcosystem'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<String> getCoreDatabaseFilePath() async {
    if (_testCoreDbPath != null) return _testCoreDbPath!;
    final envPath = Platform.environment['MAB_ECOSYSTEM_DB_PATH']?.trim();
    if (envPath != null && envPath.isNotEmpty) return envPath;
    final dir = await getCoreDirectoryPath();
    return p.join(dir, 'mab_core.db');
  }

  Future<Database?> _getCoreDatabase() async {
    if (_isTestDisabled) return null;
    if (_coreDb != null) return _coreDb!;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }

    sqfliteFfiInit();
    final dbPath = await getCoreDatabaseFilePath();
    final parentDir = Directory(p.dirname(dbPath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    _coreDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA busy_timeout = 5000;');
          try {
            await db.execute('PRAGMA journal_mode = WAL;');
            await db.execute('PRAGMA synchronous = NORMAL;');
          } catch (_) {}
        },
        onOpen: (db) async {
          await db.execute('PRAGMA busy_timeout = 5000;');
          await initCoreSchema(db);
        },
        onCreate: (db, _) async {
          await initCoreSchema(db);
        },
      ),
    );
    return _coreDb;
  }

  @visibleForTesting
  Future<void> initCoreSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_projects (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        parent_id TEXT NULL,
        realm TEXT NOT NULL DEFAULT 'work',
        status TEXT NOT NULL DEFAULT 'active',
        merged_into_id TEXT NULL,
        color TEXT NOT NULL DEFAULT '#3B82F6',
        daily_quota_minutes INTEGER NOT NULL DEFAULT 0,
        weekly_quota_minutes INTEGER NOT NULL DEFAULT 0,
        monthly_quota_minutes INTEGER NOT NULL DEFAULT 0,
        hourly_rate REAL NOT NULL DEFAULT 0.0,
        google_calendar_id TEXT NULL,
        domain_code TEXT NOT NULL DEFAULT 'WEALTH_FINANCE',
        primary_outcome_id TEXT NULL,
        scope_mode TEXT NOT NULL DEFAULT 'STANDARD',
        priority_weight INTEGER NOT NULL DEFAULT 5,
        pause_resume_note TEXT NOT NULL DEFAULT '',
        workspace_path TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        updated_by_app TEXT NOT NULL DEFAULT 'system'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_project_merges (
        id TEXT PRIMARY KEY,
        source_project_id TEXT NOT NULL,
        target_project_id TEXT NOT NULL,
        source_code TEXT NOT NULL DEFAULT '',
        source_name TEXT NOT NULL DEFAULT '',
        merged_by_app TEXT NOT NULL,
        merged_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_project_aliases (
        app_name TEXT NOT NULL,
        local_project_id TEXT NOT NULL,
        core_project_id TEXT NOT NULL,
        PRIMARY KEY (app_name, local_project_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_outcomes (
        id TEXT PRIMARY KEY,
        core_project_id TEXT NULL,
        realm TEXT NOT NULL DEFAULT 'work',
        domain_code TEXT NOT NULL DEFAULT 'WEALTH_FINANCE',
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        is_completed INTEGER NOT NULL DEFAULT 0,
        source_app TEXT NOT NULL DEFAULT 'mab_focus',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_time_logs (
        id TEXT PRIMARY KEY,
        core_project_id TEXT NULL,
        outcome_id TEXT NULL,
        realm TEXT NOT NULL DEFAULT 'work',
        clock_mode TEXT NOT NULL DEFAULT 'pomodoro',
        title TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        edit_note TEXT NULL,
        source_app TEXT NOT NULL DEFAULT 'mab_focus',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_notes (
        id TEXT PRIMARY KEY,
        core_project_id TEXT NULL,
        outcome_id TEXT NULL,
        time_record_id TEXT NULL,
        realm TEXT NOT NULL DEFAULT 'work',
        note_type TEXT NOT NULL DEFAULT 'general',
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL,
        tags_json TEXT NOT NULL DEFAULT '[]',
        source_app TEXT NOT NULL DEFAULT 'mab_focus',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_work_items (
        id TEXT PRIMARY KEY,
        core_project_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'GENERAL',
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'OPEN',
        definition_of_done TEXT NOT NULL DEFAULT '',
        first_physical_action TEXT NOT NULL DEFAULT '',
        source_app TEXT NOT NULL DEFAULT 'mab_compass',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_activity_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_app TEXT NOT NULL,
        event_type TEXT NOT NULL,
        core_project_id TEXT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS core_app_registry (
        app_id TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        db_path TEXT NOT NULL DEFAULT '',
        last_seen_at TEXT NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.insert(
      'core_sync_meta',
      {'key': 'revision', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'core_sync_meta',
      {'key': 'schema_version', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _bumpRevision(DatabaseExecutor db) async {
    final rows = await db.query(
      'core_sync_meta',
      where: 'key = ?',
      whereArgs: ['revision'],
      limit: 1,
    );
    final current = rows.isNotEmpty
        ? (int.tryParse(rows.first['value']?.toString() ?? '1') ?? 1)
        : 1;
    await db.insert(
      'core_sync_meta',
      {'key': 'revision', 'value': (current + 1).toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _nowUtcIso() => DateTime.now().toUtc().toIso8601String();

  DateTime _parseIsoSafe(String? raw, DateTime fallback) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    return DateTime.tryParse(raw.trim())?.toUtc() ?? fallback;
  }

  /// ثبت یا بروزرسانی پروژه در دیتابیس مرکزی
  Future<void> pushProjectUpsert(ProjectNode project) async {
    if (_isTestDisabled) return;
    await _runSerialized(() async {
      try {
        final core = await _getCoreDatabase();
        if (core == null) return;
        EcosystemBridgeService.instance.notifyInternalCoreWrite();

        final now = _nowUtcIso();
        final updatedIso = project.updatedAt.toUtc().toIso8601String();
        await core.transaction((txn) async {
          final existing = await txn.query(
            'core_projects',
            where: 'id = ?',
            whereArgs: [project.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            await txn.insert('core_projects', {
              'id': project.id,
              'code': '',
              'name': project.name,
              'parent_id': project.parentId,
              'realm': project.realm.dbValue,
              'status': project.status,
              'merged_into_id': null,
              'color': project.colorHex,
              'daily_quota_minutes': project.dailyQuotaMinutes,
              'weekly_quota_minutes': project.weeklyQuotaMinutes,
              'monthly_quota_minutes': project.monthlyQuotaMinutes,
              'hourly_rate': project.hourlyRate,
              'google_calendar_id': project.googleCalendarId,
              'domain_code': project.realm == AppRealm.life
                  ? 'MIND_LEARNING'
                  : 'WEALTH_FINANCE',
              'created_at': project.createdAt.toUtc().toIso8601String(),
              'updated_at': updatedIso,
              'deleted_at': null,
              'updated_by_app': 'mab_focus',
            });
          } else {
            await txn.update(
              'core_projects',
              {
                'name': project.name,
                'parent_id': project.parentId,
                'realm': project.realm.dbValue,
                'status': project.status,
                'color': project.colorHex,
                'daily_quota_minutes': project.dailyQuotaMinutes,
                'weekly_quota_minutes': project.weeklyQuotaMinutes,
                'monthly_quota_minutes': project.monthlyQuotaMinutes,
                'hourly_rate': project.hourlyRate,
                'google_calendar_id': project.googleCalendarId,
                'updated_at': updatedIso,
                'deleted_at': null,
                'updated_by_app': 'mab_focus',
              },
              where: 'id = ?',
              whereArgs: [project.id],
            );
          }

          await txn.insert(
            'core_project_aliases',
            {
              'app_name': 'mab_focus',
              'local_project_id': project.id,
              'core_project_id': project.id,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          await txn.insert('core_activity_events', {
            'source_app': 'mab_focus',
            'event_type': 'PROJECT_UPSERT',
            'core_project_id': project.id,
            'payload_json': jsonEncode({
              'name': project.name,
              'parent_id': project.parentId,
              'status': project.status,
              'realm': project.realm.dbValue,
            }),
            'created_at': now,
          });
          await _bumpRevision(txn);
        });
      } catch (e) {
        debugPrint('[EcosystemCore] pushProjectUpsert warning: $e');
      }
    });
  }

  /// ثبت حذف پروژه (با Tombstone تا اپ دیگر دوباره آن را نسازد)
  Future<void> pushProjectDelete(List<String> projectIds) async {
    if (_isTestDisabled || projectIds.isEmpty) return;
    await _runSerialized(() async {
      try {
        final core = await _getCoreDatabase();
        if (core == null) return;
        EcosystemBridgeService.instance.notifyInternalCoreWrite();

        final now = _nowUtcIso();
        await core.transaction((txn) async {
          for (final pid in projectIds) {
            await txn.update(
              'core_projects',
              {
                'status': 'deleted',
                'deleted_at': now,
                'updated_at': now,
                'updated_by_app': 'mab_focus',
              },
              where: 'id = ?',
              whereArgs: [pid],
            );
            await txn.insert('core_activity_events', {
              'source_app': 'mab_focus',
              'event_type': 'PROJECT_DELETE',
              'core_project_id': pid,
              'payload_json': jsonEncode({'deleted_id': pid}),
              'created_at': now,
            });
          }
          await _bumpRevision(txn);
        });
      } catch (e) {
        debugPrint('[EcosystemCore] pushProjectDelete warning: $e');
      }
    });
  }

  /// ثبت ادغام پروژه در هسته مرکزی تا در Mab-Compass و سایر اپ‌ها هم دقیقاً اعمال شود
  Future<void> pushProjectMerge(
    String sourceId,
    String targetId, {
    String sourceName = '',
    Database? localDbToRecordApplied,
  }) async {
    if (_isTestDisabled) return;
    await _runSerialized(() async {
      try {
        final core = await _getCoreDatabase();
        if (core == null) return;
        EcosystemBridgeService.instance.notifyInternalCoreWrite();

        final now = _nowUtcIso();
        final mergeId = _uuid.v4();
        await core.transaction((txn) async {
          final srcRow = await txn.query(
            'core_projects',
            where: 'id = ?',
            whereArgs: [sourceId],
            limit: 1,
          );
          final resolvedName = sourceName.isNotEmpty
              ? sourceName
              : (srcRow.isNotEmpty ? srcRow.first['name'].toString() : '');
          final resolvedCode =
              srcRow.isNotEmpty ? (srcRow.first['code']?.toString() ?? '') : '';

          await txn.insert('core_project_merges', {
            'id': mergeId,
            'source_project_id': sourceId,
            'target_project_id': targetId,
            'source_code': resolvedCode,
            'source_name': resolvedName,
            'merged_by_app': 'mab_focus',
            'merged_at': now,
          });

          await txn.update(
            'core_projects',
            {'parent_id': targetId, 'updated_at': now, 'updated_by_app': 'mab_focus'},
            where: 'parent_id = ?',
            whereArgs: [sourceId],
          );

          await txn.update(
            'core_projects',
            {
              'status': 'merged',
              'merged_into_id': targetId,
              'deleted_at': now,
              'updated_at': now,
              'updated_by_app': 'mab_focus',
            },
            where: 'id = ?',
            whereArgs: [sourceId],
          );

          for (final table in ['core_outcomes', 'core_time_logs', 'core_notes', 'core_work_items']) {
            await txn.update(
              table,
              {'core_project_id': targetId},
              where: 'core_project_id = ?',
              whereArgs: [sourceId],
            );
          }

          await txn.update(
            'core_project_aliases',
            {'core_project_id': targetId},
            where: 'core_project_id = ?',
            whereArgs: [sourceId],
          );

          await txn.insert('core_activity_events', {
            'source_app': 'mab_focus',
            'event_type': 'PROJECT_MERGE',
            'core_project_id': targetId,
            'payload_json': jsonEncode({
              'merge_id': mergeId,
              'source_id': sourceId,
              'target_id': targetId,
              'source_name': resolvedName,
            }),
            'created_at': now,
          });
          await _bumpRevision(txn);
        });

        if (localDbToRecordApplied != null) {
          await localDbToRecordApplied.insert(
            'applied_core_merges',
            {'merge_id': mergeId, 'applied_at': now},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      } catch (e) {
        debugPrint('[EcosystemCore] pushProjectMerge warning: $e');
      }
    });
  }

  /// آینه‌سازی دستاورد (Outcome) در هسته مرکزی
  Future<void> pushOutcome(OutcomeItem outcome) async {
    if (_isTestDisabled) return;
    await _runSerialized(() async {
      try {
        final core = await _getCoreDatabase();
        if (core == null) return;
        EcosystemBridgeService.instance.notifyInternalCoreWrite();
        final now = _nowUtcIso();
        await core.insert(
          'core_outcomes',
          {
            'id': outcome.id,
            'core_project_id': outcome.projectId,
            'realm': outcome.realm.dbValue,
            'domain_code': outcome.realm == AppRealm.life
                ? 'MIND_LEARNING'
                : 'WEALTH_FINANCE',
            'title': outcome.title,
            'description': outcome.description,
            'status': outcome.isCompleted ? 'COMPLETED' : 'ACTIVE',
            'is_completed': outcome.isCompleted ? 1 : 0,
            'source_app': 'mab_focus',
            'created_at': outcome.createdAt.toUtc().toIso8601String(),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint('[EcosystemCore] pushOutcome warning: $e');
      }
    });
  }

  /// آینه‌سازی رکورد زمانی (TimeRecord) در هسته مرکزی
  Future<void> pushTimeRecord(TimeRecord record) async {
    if (_isTestDisabled) return;
    await _runSerialized(() async {
      try {
        final core = await _getCoreDatabase();
        if (core == null) return;
        EcosystemBridgeService.instance.notifyInternalCoreWrite();
        await core.insert(
          'core_time_logs',
          {
            'id': record.id,
            'core_project_id': record.projectId,
            'outcome_id': record.outcomeId,
            'realm': record.realm.dbValue,
            'clock_mode': record.clockMode.dbValue,
            'title': record.titleSnapshot,
            'start_time': record.startTime.toUtc().toIso8601String(),
            'end_time': record.endTime?.toUtc().toIso8601String(),
            'duration_seconds': record.durationSeconds,
            'edit_note': record.editNote,
            'source_app': 'mab_focus',
            'updated_at': _nowUtcIso(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint('[EcosystemCore] pushTimeRecord warning: $e');
      }
    });
  }

  /// آینه‌سازی یادداشت نشست (SessionNote) در هسته مرکزی
  Future<void> pushSessionNote(SessionNote note) async {
    if (_isTestDisabled) return;
    await _runSerialized(() async {
      try {
        final core = await _getCoreDatabase();
        if (core == null) return;
        EcosystemBridgeService.instance.notifyInternalCoreWrite();
        final now = _nowUtcIso();
        await core.insert(
          'core_notes',
          {
            'id': note.id,
            'core_project_id': note.projectId,
            'outcome_id': note.outcomeId,
            'time_record_id': note.timeRecordId,
            'realm': note.realm.dbValue,
            'note_type': note.noteType.dbValue,
            'title': '',
            'content': note.content,
            'tags_json': '[]',
            'source_app': 'mab_focus',
            'created_at': note.createdAt.toUtc().toIso8601String(),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint('[EcosystemCore] pushSessionNote warning: $e');
      }
    });
  }

  /// همگام‌سازی کامل و دوطرفه پروژه‌ها و ادغام‌ها بین دیتابیس محلی Mab-Focus و دیتابیس مرکزی `mab_core.db`
  Future<bool> reconcileWithCore(Database localDb, {String localDbPath = ''}) async {
    if (_isTestDisabled) return false;
    return _runSerialized(() async {
      try {
        final core = await _getCoreDatabase();
        if (core == null) return false;

        bool localChanged = false;
        bool coreChanged = false;
        final now = _nowUtcIso();

        await localDb.execute('''
          CREATE TABLE IF NOT EXISTS applied_core_merges (
            merge_id TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
          )
        ''');

        // ثبت حضور Mab-Focus در رجیستری مرکزی
        await core.insert(
          'core_app_registry',
          {
            'app_id': 'mab_focus',
            'app_name': 'Mab-Focus',
            'db_path': localDbPath,
            'last_seen_at': now,
            'schema_version': 5,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // ۱. اعمال ادغام‌های ثبت‌شده در مرکز که هنوز در Mab-Focus اعمال نشده‌اند
        final allMerges = await core.query('core_project_merges', orderBy: 'merged_at ASC');
        final appliedRows = await localDb.query('applied_core_merges');
        final appliedIds =
            appliedRows.map((r) => r['merge_id'].toString()).toSet();

        for (final m in allMerges) {
          final mergeId = m['id'].toString();
          if (appliedIds.contains(mergeId)) continue;
          final sourceId = m['source_project_id'].toString();
          final targetId = m['target_project_id'].toString();

          final srcExists = (await localDb.query(
            'projects',
            where: 'id = ?',
            whereArgs: [sourceId],
            limit: 1,
          ))
              .isNotEmpty;

          if (srcExists && sourceId != targetId) {
            EcosystemBridgeService.instance.notifyInternalWrite();
            await localDb.transaction((txn) async {
              for (final table in [
                'outcomes',
                'time_records',
                'session_notes',
                'scheduled_blocks'
              ]) {
                await txn.update(
                  table,
                  {'project_id': targetId},
                  where: 'project_id = ?',
                  whereArgs: [sourceId],
                );
              }
              await txn.update(
                'projects',
                {'parent_id': targetId, 'updated_at': now},
                where: 'parent_id = ?',
                whereArgs: [sourceId],
              );
              await txn.delete('projects', where: 'id = ?', whereArgs: [sourceId]);
            });
            localChanged = true;
          }

          await localDb.insert(
            'applied_core_merges',
            {'merge_id': mergeId, 'applied_at': now},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }

        // ۲. بارگذاری پروژه‌های محلی و مرکزی
        final localMaps = await localDb.query('projects');
        final localById = <String, Map<String, Object?>>{
          for (final r in localMaps) r['id'].toString(): r,
        };

        final coreMaps = await core.query('core_projects');
        final coreById = <String, Map<String, Object?>>{
          for (final r in coreMaps) r['id'].toString(): r,
        };

        // ۳. ارسال پروژه‌های جدید محلی (که در مرکز نیستند و مرج نشده‌اند) به مرکز
        final mergedSourceIds =
            allMerges.map((m) => m['source_project_id'].toString()).toSet();
        for (final entry in localById.entries) {
          final pid = entry.key;
          if (coreById.containsKey(pid) || mergedSourceIds.contains(pid)) {
            continue;
          }
          final proj = ProjectNode.fromMap(entry.value);
          EcosystemBridgeService.instance.notifyInternalCoreWrite();
          await core.insert('core_projects', {
            'id': proj.id,
            'code': '',
            'name': proj.name,
            'parent_id': proj.parentId,
            'realm': proj.realm.dbValue,
            'status': proj.status,
            'merged_into_id': null,
            'color': proj.colorHex,
            'daily_quota_minutes': proj.dailyQuotaMinutes,
            'weekly_quota_minutes': proj.weeklyQuotaMinutes,
            'monthly_quota_minutes': proj.monthlyQuotaMinutes,
            'hourly_rate': proj.hourlyRate,
            'google_calendar_id': proj.googleCalendarId,
            'domain_code': proj.realm == AppRealm.life
                ? 'MIND_LEARNING'
                : 'WEALTH_FINANCE',
            'created_at': proj.createdAt.toUtc().toIso8601String(),
            'updated_at': proj.updatedAt.toUtc().toIso8601String(),
            'deleted_at': null,
            'updated_by_app': 'mab_focus',
          });
          await core.insert(
            'core_project_aliases',
            {
              'app_name': 'mab_focus',
              'local_project_id': proj.id,
              'core_project_id': proj.id,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          coreChanged = true;
        }

        // ۴. همگام‌سازی پروژه‌های مرکزی به محلی (یا بالعکس بر اساس زمان آخرین ویرایش)
        final refreshedCore = await core.query('core_projects');
        for (final cr in refreshedCore) {
          final cid = cr['id'].toString();
          final status = cr['status']?.toString() ?? 'active';
          final deletedAt = cr['deleted_at']?.toString();
          final isDeletedOrMerged =
              status == 'deleted' || status == 'merged' || (deletedAt != null && deletedAt.isNotEmpty);

          final localRow = localById[cid];
          if (isDeletedOrMerged) {
            if (localRow != null) {
              EcosystemBridgeService.instance.notifyInternalWrite();
              await localDb.transaction((txn) async {
                for (final table in [
                  'outcomes',
                  'time_records',
                  'session_notes',
                  'scheduled_blocks'
                ]) {
                  await txn.update(
                    table,
                    {'project_id': null},
                    where: 'project_id = ?',
                    whereArgs: [cid],
                  );
                }
                await txn.delete('projects', where: 'id = ?', whereArgs: [cid]);
              });
              localChanged = true;
            }
            continue;
          }

          if (localRow == null) {
            // پروژه جدید ایجادشده در Mab-Compass یا اپ دیگر -> ایجاد در Mab-Focus
            EcosystemBridgeService.instance.notifyInternalWrite();
            await localDb.insert(
              'projects',
              {
                'id': cid,
                'realm': cr['realm']?.toString() ?? 'work',
                'name': cr['name'].toString(),
                'parent_id': cr['parent_id'],
                'status': status,
                'color': cr['color']?.toString() ?? '#3B82F6',
                'daily_quota_minutes': (cr['daily_quota_minutes'] as num?)?.toInt() ?? 0,
                'weekly_quota_minutes': (cr['weekly_quota_minutes'] as num?)?.toInt() ?? 0,
                'monthly_quota_minutes': (cr['monthly_quota_minutes'] as num?)?.toInt() ?? 0,
                'hourly_rate': (cr['hourly_rate'] as num?)?.toDouble() ?? 0.0,
                'google_calendar_id': cr['google_calendar_id'],
                'created_at': cr['created_at']?.toString() ?? now,
                'updated_at': cr['updated_at']?.toString() ?? now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            localChanged = true;
          } else {
            final localProj = ProjectNode.fromMap(localRow);
            final coreUpdated = _parseIsoSafe(
              cr['updated_at']?.toString(),
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            );
            final localUpdated = localProj.updatedAt.toUtc();

            if (coreUpdated.isAfter(localUpdated.add(const Duration(milliseconds: 500)))) {
              EcosystemBridgeService.instance.notifyInternalWrite();
              await localDb.update(
                'projects',
                {
                  'realm': cr['realm']?.toString() ?? localProj.realm.dbValue,
                  'name': cr['name'].toString(),
                  'parent_id': cr['parent_id'],
                  'status': status,
                  'color': cr['color']?.toString() ?? localProj.colorHex,
                  'daily_quota_minutes':
                      (cr['daily_quota_minutes'] as num?)?.toInt() ?? localProj.dailyQuotaMinutes,
                  'weekly_quota_minutes':
                      (cr['weekly_quota_minutes'] as num?)?.toInt() ?? localProj.weeklyQuotaMinutes,
                  'monthly_quota_minutes':
                      (cr['monthly_quota_minutes'] as num?)?.toInt() ?? localProj.monthlyQuotaMinutes,
                  'hourly_rate':
                      (cr['hourly_rate'] as num?)?.toDouble() ?? localProj.hourlyRate,
                  'google_calendar_id': cr['google_calendar_id'],
                  'updated_at': cr['updated_at']?.toString() ?? now,
                },
                where: 'id = ?',
                whereArgs: [cid],
              );
              localChanged = true;
            } else if (localUpdated.isAfter(coreUpdated.add(const Duration(milliseconds: 500)))) {
              EcosystemBridgeService.instance.notifyInternalCoreWrite();
              await core.update(
                'core_projects',
                {
                  'name': localProj.name,
                  'parent_id': localProj.parentId,
                  'realm': localProj.realm.dbValue,
                  'status': localProj.status,
                  'color': localProj.colorHex,
                  'daily_quota_minutes': localProj.dailyQuotaMinutes,
                  'weekly_quota_minutes': localProj.weeklyQuotaMinutes,
                  'monthly_quota_minutes': localProj.monthlyQuotaMinutes,
                  'hourly_rate': localProj.hourlyRate,
                  'google_calendar_id': localProj.googleCalendarId,
                  'updated_at': localUpdated.toIso8601String(),
                  'updated_by_app': 'mab_focus',
                },
                where: 'id = ?',
                whereArgs: [cid],
              );
              coreChanged = true;
            }
          }
        }

        // ۵. همگام‌سازی اولیه داده‌های عملیاتی اگر هسته مرکزی خالی باشد
        final coreLogsCnt = _firstIntValue(
          await core.rawQuery('SELECT COUNT(*) FROM core_time_logs'),
        );
        if (coreLogsCnt == 0) {
          final trMaps = await localDb.query('time_records');
          for (final r in trMaps) {
            final tr = TimeRecord.fromMap(r);
            await core.insert(
              'core_time_logs',
              {
                'id': tr.id,
                'core_project_id': tr.projectId,
                'outcome_id': tr.outcomeId,
                'realm': tr.realm.dbValue,
                'clock_mode': tr.clockMode.dbValue,
                'title': tr.titleSnapshot,
                'start_time': tr.startTime.toUtc().toIso8601String(),
                'end_time': tr.endTime?.toUtc().toIso8601String(),
                'duration_seconds': tr.durationSeconds,
                'edit_note': tr.editNote,
                'source_app': 'mab_focus',
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }

        final coreNotesCnt = _firstIntValue(
          await core.rawQuery("SELECT COUNT(*) FROM core_notes WHERE source_app = 'mab_focus'"),
        );
        if (coreNotesCnt == 0) {
          final snMaps = await localDb.query('session_notes');
          for (final r in snMaps) {
            final sn = SessionNote.fromMap(r);
            await core.insert(
              'core_notes',
              {
                'id': sn.id,
                'core_project_id': sn.projectId,
                'outcome_id': sn.outcomeId,
                'time_record_id': sn.timeRecordId,
                'realm': sn.realm.dbValue,
                'note_type': sn.noteType.dbValue,
                'title': '',
                'content': sn.content,
                'tags_json': '[]',
                'source_app': 'mab_focus',
                'created_at': sn.createdAt.toUtc().toIso8601String(),
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }

        if (coreChanged) {
          EcosystemBridgeService.instance.notifyInternalCoreWrite();
          await _bumpRevision(core);
        }

        return localChanged;
      } catch (e) {
        debugPrint('[EcosystemCore] reconcileWithCore warning: $e');
        return false;
      }
    });
  }
}

int _firstIntValue(List<Map<String, Object?>> result) {
  if (result.isEmpty) return 0;
  final firstVal = result.first.values.first;
  if (firstVal is int) return firstVal;
  return int.tryParse(firstVal?.toString() ?? '0') ?? 0;
}
