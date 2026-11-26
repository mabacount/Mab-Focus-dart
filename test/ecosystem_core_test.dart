import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/outcome_item.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/project_node.dart';
import 'package:mab_focus/models/session_note.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:mab_focus/services/ecosystem_core_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  tearDown(() {
    DatabaseService.instance.resetForTest();
    EcosystemCoreService.instance.resetForTest();
  });

  test('unifies project tree, edits, and merges bidirectionally via mab_core',
      () async {
    final localDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final coreDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );

    await DatabaseService.instance.createSchemaV5(localDb, 5);
    await EcosystemCoreService.instance.initCoreSchema(coreDb);
    DatabaseService.instance.setTestDatabase(localDb);
    EcosystemCoreService.instance.setTestCoreDatabase(coreDb);

    // ۱. ساخت پروژه و زیرپروژه در Mab-Focus -> انتشار خودکار به هسته مرکزی
    final rootProj = ProjectNode(
      id: 'focus-root-1',
      name: 'پلتفرم اصلی',
      realm: AppRealm.work,
      colorHex: '#8B5CF6',
      hourlyRate: 500000,
    );
    final childProj = ProjectNode(
      id: 'focus-child-1',
      name: 'ماژول پرداخت',
      parentId: 'focus-root-1',
      realm: AppRealm.work,
    );
    await DatabaseService.instance.insertProject(rootProj);
    await DatabaseService.instance.insertProject(childProj);

    final coreRows1 = await coreDb.query('core_projects');
    expect(coreRows1.length, 2);
    expect(
      coreRows1.firstWhere((r) => r['id'] == 'focus-child-1')['parent_id'],
      'focus-root-1',
    );

    // ۲. شبیه‌سازی ساخت پروژه از Mab-Compass در هسته مرکزی -> همگام‌سازی به Mab-Focus
    final futureIso =
        DateTime.now().toUtc().add(const Duration(seconds: 5)).toIso8601String();
    await coreDb.insert('core_projects', {
      'id': 'compass-proj-1',
      'code': 'ZIGHOOSH',
      'name': 'زیگهوش',
      'parent_id': null,
      'realm': 'work',
      'status': 'active',
      'color': '#06B6D4',
      'daily_quota_minutes': 60,
      'weekly_quota_minutes': 300,
      'monthly_quota_minutes': 0,
      'hourly_rate': 0.0,
      'domain_code': 'WEALTH_FINANCE',
      'scope_mode': 'STANDARD',
      'priority_weight': 5,
      'pause_resume_note': '',
      'workspace_path': '',
      'created_at': futureIso,
      'updated_at': futureIso,
      'deleted_at': null,
      'updated_by_app': 'mab_compass',
    });

    final changed = await DatabaseService.instance.reconcileWithEcosystemCore();
    expect(changed, isTrue);

    final imported =
        await DatabaseService.instance.getProjectById('compass-proj-1');
    expect(imported, isNotNull);
    expect(imported!.name, 'زیگهوش');
    expect(imported.dailyQuotaMinutes, 60);

    // ۳. ثبت داده برای focus-child-1 و ادغام آن با compass-proj-1 از سمت هسته مرکزی
    await DatabaseService.instance.insertOutcome(OutcomeItem(
      id: 'out-1',
      projectId: 'focus-child-1',
      title: 'درگاه بانکی',
    ));
    await DatabaseService.instance.insertSessionNote(SessionNote(
      id: 'note-1',
      projectId: 'focus-child-1',
      content: 'نکته تست درگاه',
    ));

    await coreDb.insert('core_project_merges', {
      'id': 'merge-test-1',
      'source_project_id': 'focus-child-1',
      'target_project_id': 'compass-proj-1',
      'source_code': '',
      'source_name': 'ماژول پرداخت',
      'merged_by_app': 'mab_compass',
      'merged_at': futureIso,
    });
    await coreDb.update(
      'core_projects',
      {
        'status': 'merged',
        'merged_into_id': 'compass-proj-1',
        'deleted_at': futureIso,
        'updated_at': futureIso,
      },
      where: 'id = ?',
      whereArgs: ['focus-child-1'],
    );

    final mergedChanged =
        await DatabaseService.instance.reconcileWithEcosystemCore();
    expect(mergedChanged, isTrue);

    expect(
        await DatabaseService.instance.getProjectById('focus-child-1'), isNull);
    final migratedOutcome =
        await DatabaseService.instance.getOutcomeById('out-1');
    expect(migratedOutcome!.projectId, 'compass-proj-1');
    final allNotes = await DatabaseService.instance.getAllSessionNotes();
    expect(allNotes.first.projectId, 'compass-proj-1');

    // ۴. ادغام از سمت Mab-Focus -> ثبت در core_project_merges
    await DatabaseService.instance
        .mergeProject('compass-proj-1', 'focus-root-1');
    final merges = await coreDb.query('core_project_merges');
    expect(merges.length, 2);
    expect(merges.last['source_project_id'], 'compass-proj-1');
    expect(merges.last['target_project_id'], 'focus-root-1');

    await localDb.close();
    await coreDb.close();
  });
}
