@Tags(['e2e'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/services/database_service.dart';
import 'e2e_harness.dart';

void main() {
  group('E2E Harness Smoke Tests', () {
    testWidgets(
      'boots MabFocusApp at 1280x800 with isolated DB, zero MissingPluginException, and clean teardown',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester, surfaceSize: const Size(1280, 800));

        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.text('متوقف'), findsOneWidget);
        expect(harness.tempDir.existsSync(), isTrue);
        expect(File(harness.dbPath).existsSync(), isTrue);
      },
    );

    testWidgets(
      'seeding and simulateRestart persist projects, outcomes, and open record recovery across restart',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          final proj = await harness.seedProject(
            name: 'پروژه تست اسموک',
            weeklyQuotaMinutes: 300,
          );
          final outcome = await harness.seedOutcome(
            projectId: proj.id,
            title: 'تسک اسموک بازیابی',
          );
          await harness.seedTimeRecord(
            realm: AppRealm.work,
            outcomeId: outcome.id,
            projectId: proj.id,
            titleSnapshot: outcome.title,
            startTime: DateTime.now().subtract(const Duration(minutes: 15)),
            endTime: null,
          );
          await harness.simulateRestart();
        });

        await harness.pumpApp(tester, surfaceSize: const Size(1280, 800));

        expect(tester.takeException(), isNull);
        expect(
          harness.provider.projects.any((p) => p.name == 'پروژه تست اسموک'),
          isTrue,
        );
        expect(harness.provider.recoveredOpenRecord, isNotNull);
        expect(find.textContaining('بازیابی جلسه ناتمام'), findsOneWidget);

        await tester.runAsync(() async {
          final openRows = await DatabaseService.instance.getOpenTimeRecords();
          expect(openRows.length, 1);
          expect(openRows.first.titleSnapshot, 'تسک اسموک بازیابی');
        });
      },
    );
  });
}
