import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mab_focus/core/constants.dart';
import 'package:mab_focus/models/outcome_item.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/project_node.dart';
import 'package:mab_focus/models/time_record.dart';
import 'package:mab_focus/providers/app_state_provider.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:mab_focus/services/gcal_sync_service.dart';
import 'package:mab_focus/services/sound_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<Database> openInMemoryDb() {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 5,
        singleInstance: false,
        onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
      ),
    );
  }

  tearDown(() {
    GCalSyncService.instance.clientOverride = null;
    DatabaseService.instance.resetForTest();
  });

  group('Recording Stop & App Lifecycle (R3)', () {
    test(
        'stopTimer closes active and orphan open rows and clears active & previous work state',
        () async {
      final db = await openInMemoryDb();
      DatabaseService.instance.setTestDatabase(db);

      final project = ProjectNode(
        id: 'p_1',
        realm: AppRealm.work,
        name: 'پروژه اصلی',
      );
      final outcome = OutcomeItem(
        id: 'o_1',
        realm: AppRealm.work,
        projectId: 'p_1',
        title: 'تکمیل گزارش فنی',
      );
      await DatabaseService.instance.insertProject(project);
      await DatabaseService.instance.insertOutcome(outcome);

      // Seed an orphan open row that might exist alongside an active session
      await DatabaseService.instance.insertTimeRecord(
        TimeRecord(
          id: 'orphan_row',
          realm: AppRealm.work,
          clockMode: ClockType.pomodoro,
          titleSnapshot: 'رکورد جامانده',
          isUntitledDraft: false,
          startTime: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );

      final provider = AppStateProvider(isTestMode: true);
      await provider.initialize();

      // Switch to outcome in Work, then switch to Life so _previousWork* is cached
      await provider.startOrSwitchToOutcome(outcome);
      expect(provider.pomodoroState.activeOutcomeId, 'o_1');
      await provider.switchRealm(AppRealm.life);
      expect(provider.pomodoroState.realm, AppRealm.life);

      // Stop completely via stopTimer
      await provider.stopTimer();

      expect(provider.pomodoroState.status, TimerStatus.idle);
      expect(provider.pomodoroState.activeRecordId, isNull);
      expect(provider.pomodoroState.activeOutcomeId, isNull);
      expect(provider.pomodoroState.elapsedSeconds, 0);
      expect(provider.pomodoroState.overtimeSeconds, 0);
      expect(provider.activeRecord, isNull);
      expect(provider.recoveredOpenRecord, isNull);
      expect(provider.shouldShowNatureSlideshow, isFalse);

      final openAfterStop = await DatabaseService.instance.getOpenTimeRecords();
      expect(openAfterStop, isEmpty);

      // Starting fresh Work timer after Stop must NOT resume _previousWorkOutcomeId
      await provider.startTimer(targetRealm: AppRealm.work);
      expect(provider.activeRecord, isNotNull);
      expect(provider.activeRecord!.outcomeId, isNull);
      expect(provider.activeRecord!.isUntitledDraft, isTrue);

      provider.dispose();
      await db.close();
    });

    test(
        'post-Stop close & reopen stays idle and does not accumulate next-day time',
        () async {
      final db = await openInMemoryDb();
      DatabaseService.instance.setTestDatabase(db);

      final outcome = OutcomeItem(
        id: 'o_work',
        realm: AppRealm.work,
        title: 'کار متمرکز صبح',
      );
      await DatabaseService.instance.insertOutcome(outcome);

      final p1 = AppStateProvider(isTestMode: true);
      await p1.initialize();

      final startedAt = DateTime.now().subtract(const Duration(minutes: 20));
      await p1.startOrSwitchToOutcome(outcome, atTime: startedAt);
      await p1.stopTimer();
      await p1.flushPendingMutations();

      final recordsAfterStop =
          await DatabaseService.instance.getAllTimeRecords();
      expect(recordsAfterStop, hasLength(1));
      final closedDuration = recordsAfterStop.first.durationSeconds;
      expect(closedDuration, greaterThanOrEqualTo(1195));
      expect(recordsAfterStop.first.endTime, isNotNull);

      p1.dispose();

      // Reopen app later (new provider on same database)
      final p2 = AppStateProvider(isTestMode: true);
      await p2.initialize();

      expect(p2.pomodoroState.status, TimerStatus.idle);
      expect(p2.activeRecord, isNull);
      expect(p2.pomodoroState.elapsedSeconds, 0);
      final recordsOnReopen =
          await DatabaseService.instance.getAllTimeRecords();
      expect(recordsOnReopen, hasLength(1));
      expect(recordsOnReopen.first.durationSeconds, closedDuration);

      p2.dispose();
      await db.close();
    });

    test(
        'close without Stop preserves open record and recovers elapsed time on reopen',
        () async {
      final db = await openInMemoryDb();
      DatabaseService.instance.setTestDatabase(db);

      final start3HoursAgo = DateTime.now().subtract(const Duration(hours: 3));
      await DatabaseService.instance.insertTimeRecord(
        TimeRecord(
          id: 'open_3h',
          realm: AppRealm.work,
          clockMode: ClockType.pomodoro,
          titleSnapshot: 'جلسه ادامه‌دار',
          isUntitledDraft: false,
          startTime: start3HoursAgo,
        ),
      );

      final p1 = AppStateProvider(isTestMode: true);
      await p1.initialize();
      await p1.flushPendingMutations();
      p1.dispose();

      // Reopen without ever calling stopTimer()
      final p2 = AppStateProvider(isTestMode: true);
      await p2.initialize();

      expect(p2.pomodoroState.status, isNot(TimerStatus.idle));
      expect(p2.activeRecord?.id, 'open_3h');
      expect(p2.activeRecordElapsedSeconds, greaterThanOrEqualTo(10795));

      final openRows = await DatabaseService.instance.getOpenTimeRecords();
      expect(openRows, hasLength(1));
      expect(openRows.first.id, 'open_3h');

      p2.dispose();
      await db.close();
    });

    test('system sleep wall-clock delta accumulates onto active record on Stop',
        () async {
      final db = await openInMemoryDb();
      DatabaseService.instance.setTestDatabase(db);

      final start45mAgo = DateTime.now().subtract(const Duration(minutes: 45));
      await DatabaseService.instance.insertTimeRecord(
        TimeRecord(
          id: 'sleep_rec',
          realm: AppRealm.work,
          clockMode: ClockType.stopwatch,
          titleSnapshot: 'تحلیل معماری',
          isUntitledDraft: false,
          startTime: start45mAgo,
        ),
      );

      final provider = AppStateProvider(isTestMode: true);
      await provider.initialize();
      await provider.stopTimer();

      final saved = await DatabaseService.instance.getTimeRecordById('sleep_rec');
      expect(saved, isNotNull);
      expect(saved!.endTime, isNotNull);
      expect(saved.durationSeconds, greaterThanOrEqualTo(2695));

      provider.dispose();
      await db.close();
    });

    test(
        'flushPendingMutations drains concurrent unawaited mutations before close',
        () async {
      final db = await openInMemoryDb();
      DatabaseService.instance.setTestDatabase(db);

      final provider = AppStateProvider(isTestMode: true);
      await provider.initialize();

      final proj = ProjectNode(
        id: 'p_flush',
        realm: AppRealm.work,
        name: 'پروژه صف',
      );
      final outcome = OutcomeItem(
        id: 'o_flush',
        realm: AppRealm.work,
        projectId: 'p_flush',
        title: 'کار همزمان',
      );

      unawaited(provider.saveProject(proj));
      unawaited(provider.saveOutcome(outcome));
      unawaited(provider.startOrSwitchToOutcome(outcome));
      unawaited(provider.stopTimer());

      await provider.flushPendingMutations();

      expect(provider.pomodoroState.status, TimerStatus.idle);
      expect(await DatabaseService.instance.getOpenTimeRecords(), isEmpty);
      expect(await DatabaseService.instance.getProjectById('p_flush'), isNotNull);
      expect(await DatabaseService.instance.getOutcomeById('o_flush'), isNotNull);

      provider.dispose();
      await db.close();
    });

    test('deleteProject clears cached _previousWorkProjectId cleanly',
        () async {
      final db = await openInMemoryDb();
      DatabaseService.instance.setTestDatabase(db);

      final parent = ProjectNode(
        id: 'p_parent',
        realm: AppRealm.work,
        name: 'پروژه والد',
      );
      final child = ProjectNode(
        id: 'p_child',
        parentId: 'p_parent',
        realm: AppRealm.work,
        name: 'زیرپروژه',
      );
      await DatabaseService.instance.insertProject(parent);
      await DatabaseService.instance.insertProject(child);

      final provider = AppStateProvider(isTestMode: true);
      await provider.initialize();

      await provider.startInstantWork(title: 'کار زیرپروژه', projectId: 'p_child');
      await provider.switchRealm(AppRealm.life);
      await provider.deleteProject('p_parent');

      await provider.switchRealm(AppRealm.work);
      expect(provider.activeRecord?.projectId, isNull);

      provider.dispose();
      await db.close();
    });
  });

  group('Services Reliability (GCal & SoundService)', () {
    test('GCalSyncService marks syncStatus failed on HTTP error or exception',
        () async {
      final db = await openInMemoryDb();
      DatabaseService.instance.setTestDatabase(db);
      await DatabaseService.instance
          .setSetting(AppDefaults.settingKeyGCalToken, 'fake-token');

      final record = TimeRecord(
        id: 'rec_gcal_fail',
        realm: AppRealm.work,
        clockMode: ClockType.pomodoro,
        titleSnapshot: 'همگام‌سازی ناموفق',
        isUntitledDraft: false,
        startTime: DateTime.now().subtract(const Duration(minutes: 10)),
        endTime: DateTime.now(),
        durationSeconds: 600,
      );
      await DatabaseService.instance.insertTimeRecord(record);

      GCalSyncService.instance.clientOverride = MockClient(
        (_) async => http.Response('{"error":"unauthorized"}', 401),
      );
      final ok = await GCalSyncService.instance.syncTimeRecord(
        record,
        projects: const [],
      );
      expect(ok, isFalse);

      final afterHttpFail =
          await DatabaseService.instance.getTimeRecordById('rec_gcal_fail');
      expect(afterHttpFail?.syncStatus, 'failed');

      await DatabaseService.instance.updateTimeRecord(
        record.copyWith(syncStatus: 'pending'),
      );
      GCalSyncService.instance.clientOverride = MockClient(
        (_) async => throw TimeoutException('Simulated timeout'),
      );
      final okTimeout = await GCalSyncService.instance.syncTimeRecord(
        record,
        projects: const [],
      );
      expect(okTimeout, isFalse);

      final afterTimeout =
          await DatabaseService.instance.getTimeRecordById('rec_gcal_fail');
      expect(afterTimeout?.syncStatus, 'failed');

      await db.close();
    });

    test('SoundService safely no-ops in test mode and disposes cleanly',
        () async {
      SoundService.instance.isTestMode = true;
      await SoundService.instance.playCompletionChime();
      await SoundService.instance.playOvertimeNudge();
      await SoundService.instance.dispose();
    });
  });
}
