import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/project_node.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  tearDown(() {
    DatabaseService.instance.resetForTest();
  });

  group('SQLite Schema v4 -> v5 Migration & Hierarchy Tests', () {
    test('losslessly migrates v4 task_logs and work_notes into 4 core v5 entities',
        () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );

      // ساخت جداول نسخه v4 قدیمی (مطابق v3.0)
      await db.execute('''
        CREATE TABLE projects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          parent_id TEXT NULL,
          status TEXT NOT NULL DEFAULT 'active',
          color TEXT NOT NULL DEFAULT '#3B82F6',
          daily_quota_minutes INTEGER NOT NULL DEFAULT 0,
          weekly_quota_minutes INTEGER NOT NULL DEFAULT 0,
          monthly_quota_minutes INTEGER NOT NULL DEFAULT 0,
          hourly_rate REAL NOT NULL DEFAULT 0.0,
          count_short_breaks_as_work INTEGER NOT NULL DEFAULT 0,
          count_long_breaks_as_work INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE task_logs (
          id TEXT PRIMARY KEY,
          group_id TEXT NULL,
          title TEXT NOT NULL,
          macro_project_id TEXT NULL,
          sub_project_id TEXT NULL,
          tag_ids_json TEXT NOT NULL DEFAULT '[]',
          start_time TEXT NOT NULL,
          end_time TEXT NULL,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          overtime_seconds INTEGER NOT NULL DEFAULT 0,
          entry_type TEXT NOT NULL DEFAULT 'work',
          is_completed INTEGER NOT NULL DEFAULT 0,
          is_untitled_draft INTEGER NOT NULL DEFAULT 0,
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
        CREATE TABLE work_notes (
          id TEXT PRIMARY KEY,
          task_log_id TEXT NULL,
          task_title TEXT NOT NULL,
          project_id TEXT NULL,
          content TEXT NOT NULL,
          image_paths_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE scheduled_blocks (
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
        CREATE TABLE phase_tags (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'phase',
          archived INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE music_playlists (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          folder_path TEXT NOT NULL,
          is_default INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      // داده‌های نمونه v4: پروژه‌ها
      await db.insert('projects', {
        'id': 'p_macro',
        'name': 'پروژه اصلی وب',
        'parent_id': null,
        'hourly_rate': 500000.0,
      });
      await db.insert('projects', {
        'id': 'p_sub',
        'name': 'بک‌اند',
        'parent_id': 'p_macro',
        'hourly_rate': 0.0,
      });

      // لاگ‌های کاری: دو برش با group_id مشترک (باید یک Outcome واحد بسازد)
      await db.insert('task_logs', {
        'id': 'log_1',
        'group_id': 'grp_auth',
        'title': 'پیاده‌سازی احراز هویت',
        'macro_project_id': 'p_macro',
        'sub_project_id': 'p_sub',
        'start_time': '2026-10-01T09:00:00',
        'end_time': '2026-10-01T09:25:00',
        'duration_seconds': 1500,
        'entry_type': 'work',
        'is_completed': 0,
        'is_untitled_draft': 0,
      });
      await db.insert('task_logs', {
        'id': 'log_2',
        'group_id': 'grp_auth',
        'title': 'پیاده‌سازی احراز هویت',
        'macro_project_id': 'p_macro',
        'sub_project_id': 'p_sub',
        'start_time': '2026-10-01T09:30:00',
        'end_time': '2026-10-01T09:55:00',
        'duration_seconds': 1500,
        'entry_type': 'work',
        'is_completed': 1,
        'is_untitled_draft': 0,
      });

      // استراحت عمومی کوتاه (نباید وارد جدول outcomes شود، ولی در time_records می‌ماند)
      await db.insert('task_logs', {
        'id': 'log_break',
        'group_id': null,
        'title': 'استراحت ۵ دقیقه‌ای',
        'start_time': '2026-10-01T09:25:00',
        'end_time': '2026-10-01T09:30:00',
        'duration_seconds': 300,
        'entry_type': 'short_break',
        'is_completed': 0,
        'is_untitled_draft': 0,
      });

      // لاگ بدون عنوان (نباید Outcome بسازد)
      await db.insert('task_logs', {
        'id': 'log_draft',
        'group_id': null,
        'title': 'تسک بدون عنوان',
        'start_time': '2026-10-01T10:00:00',
        'end_time': '2026-10-01T10:20:00',
        'duration_seconds': 1200,
        'entry_type': 'stopwatch',
        'is_completed': 0,
        'is_untitled_draft': 1,
      });

      // یادداشت متصل به log_1
      await db.insert('work_notes', {
        'id': 'note_1',
        'task_log_id': 'log_1',
        'task_title': 'پیاده‌سازی احراز هویت',
        'project_id': 'p_sub',
        'content': 'توکن JWT تست شد.',
        'image_paths_json': '[]',
        'created_at': '2026-10-01T09:20:00',
      });

      // اجرای مهاجرت به v5
      DatabaseService.instance.setTestDatabase(db);
      await DatabaseService.instance.migrateV4ToV5(db);

      final outcomes = await DatabaseService.instance.getOutcomes();
      final records = await DatabaseService.instance.getAllTimeRecords();
      final notes = await DatabaseService.instance.getAllSessionNotes();

      // باید دقیقاً یک Outcome از grp_auth ساخته شده باشد و تکمیل‌شده باشد
      expect(outcomes.length, 1);
      expect(outcomes.first.id, 'grp_auth');
      expect(outcomes.first.title, 'پیاده‌سازی احراز هویت');
      expect(outcomes.first.isCompleted, isTrue);
      expect(outcomes.first.projectId, 'p_sub');
      expect(outcomes.first.realm, AppRealm.work);

      // باید هر ۴ رکورد زمانی حفظ شده باشند
      expect(records.length, 4);
      final rec1 = await DatabaseService.instance.getTimeRecordById('log_1');
      final recBreak =
          await DatabaseService.instance.getTimeRecordById('log_break');
      final recDraft =
          await DatabaseService.instance.getTimeRecordById('log_draft');

      expect(rec1, isNotNull);
      expect(rec1!.outcomeId, 'grp_auth');
      expect(rec1.realm, AppRealm.work);
      expect(rec1.clockMode, ClockType.pomodoro);
      expect(rec1.earnedBreakSeconds, 300); // 1500 ~/ 5

      expect(recBreak, isNotNull);
      expect(recBreak!.realm, AppRealm.life);
      expect(recBreak.outcomeId, isNull);
      expect(recBreak.earnedBreakSeconds, 0);

      expect(recDraft, isNotNull);
      expect(recDraft!.isUntitledDraft, isTrue);
      expect(recDraft.clockMode, ClockType.stopwatch);
      expect(recDraft.realm, AppRealm.work);

      // اتصال سه‌گانه یادداشت حفظ شده باشد
      expect(notes.length, 1);
      expect(notes.first.timeRecordId, 'log_1');
      expect(notes.first.outcomeId, 'grp_auth');
      expect(notes.first.projectId, 'p_sub');
      expect(notes.first.realm, AppRealm.work);

      // تست CASCADE UPDATE: تغییر قلمرو و پروژه رکورد باید روی session_notes اعمال شود
      await DatabaseService.instance.updateTimeRecordWithAudit(
        id: 'log_1',
        newTitle: 'تغییر به فعالیت زندگی',
        newRealm: AppRealm.life,
        clearOutcomeId: true,
        clearProjectId: true,
        newTagIds: const [],
        newStartTime: DateTime(2026, 10, 1, 9, 0),
        newEndTime: DateTime(2026, 10, 1, 9, 25),
        newDurationSeconds: 1500,
      );

      final updatedNotes =
          await DatabaseService.instance.getSessionNotesForRecord('log_1');
      expect(updatedNotes.first.realm, AppRealm.life);
      expect(updatedNotes.first.outcomeId, isNull);
      expect(updatedNotes.first.projectId, isNull);

      await db.close();
    });

    test('recursive tree helpers handle multi-level inheritance accurately', () {
      final projects = [
        ProjectNode(
          id: 'root',
          name: 'شرکت الفا',
          hourlyRate: 800000,
          googleCalendarId: 'cal_alpha@group.calendar.google.com',
        ),
        ProjectNode(
          id: 'child',
          name: 'اپ موبایل',
          parentId: 'root',
          hourlyRate: 0,
        ),
        ProjectNode(
          id: 'grandchild',
          name: 'طراحی UI',
          parentId: 'child',
          hourlyRate: 0,
        ),
        ProjectNode(
          id: 'priced_child',
          name: 'مشاوره ویژه',
          parentId: 'root',
          hourlyRate: 1200000,
          googleCalendarId: 'cal_vip@group.calendar.google.com',
        ),
      ];

      final descendants =
          DatabaseService.getDescendantProjectIds('root', projects);
      expect(descendants, {'child', 'grandchild', 'priced_child'});

      expect(DatabaseService.getEffectiveHourlyRate('grandchild', projects),
          800000);
      expect(DatabaseService.getEffectiveHourlyRate('priced_child', projects),
          1200000);

      expect(
        DatabaseService.getEffectiveGoogleCalendarId('grandchild', projects),
        'cal_alpha@group.calendar.google.com',
      );
      expect(
        DatabaseService.getEffectiveGoogleCalendarId('priced_child', projects),
        'cal_vip@group.calendar.google.com',
      );

      final breadcrumb =
          DatabaseService.getProjectBreadcrumb('grandchild', projects);
      expect(breadcrumb.map((p) => p.name).toList(),
          ['شرکت الفا', 'اپ موبایل', 'طراحی UI']);
    });
  });
}
