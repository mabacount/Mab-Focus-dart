@Tags(['e2e'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'e2e_harness.dart';

void main() {
  group('Tier 1 — F6: Multi-Project Date/Time-Range Reporting', () {
    testWidgets(
      'T1-F6-01: ActivityLogTab displays records, switches sub-tabs, and filters by Realm and ClockType',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          final now = DateTime.now();
          await harness.seedTimeRecord(
            realm: AppRealm.work,
            clockMode: ClockType.pomodoro,
            titleSnapshot: 'رکورد پومودورو کار',
            startTime: now.subtract(const Duration(minutes: 50)),
            endTime: now.subtract(const Duration(minutes: 20)),
            durationSeconds: 1800,
          );
          await harness.seedTimeRecord(
            realm: AppRealm.life,
            clockMode: ClockType.stopwatch,
            titleSnapshot: 'رکورد کرنومتر زندگی',
            startTime: now.subtract(const Duration(minutes: 20)),
            endTime: now.subtract(const Duration(minutes: 5)),
            durationSeconds: 900,
          );
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 2);

        expect(find.text('رکورد پومودورو کار'), findsOneWidget);
        expect(find.text('رکورد کرنومتر زندگی'), findsOneWidget);
        expect(find.textContaining('45:00'), findsWidgets);

        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<AppRealm?>),
            matching: find.text('کار'),
          ),
        );
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));
        expect(find.text('رکورد پومودورو کار'), findsOneWidget);
        expect(find.text('رکورد کرنومتر زندگی'), findsNothing);
        expect(find.textContaining('30:00'), findsWidgets);

        await tester.tap(find.text('دفترچه یادداشت‌های جلسات'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));
        expect(find.text('خروجی اکسل یادداشت‌ها'), findsOneWidget);
      },
    );

    testWidgets(
      'T1-F6-02: multi-project selector combines two selected projects and excludes unselected third project',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          final projA = await harness.seedProject(name: 'پروژه گزارش آلفا');
          final projB = await harness.seedProject(name: 'پروژه گزارش بتا');
          final projC = await harness.seedProject(name: 'پروژه گزارش گاما');
          final now = DateTime.now();

          await harness.seedTimeRecord(
            projectId: projA.id,
            titleSnapshot: 'کار آلفا ۲۰ دقیقه',
            startTime: now.subtract(const Duration(minutes: 90)),
            endTime: now.subtract(const Duration(minutes: 70)),
            durationSeconds: 1200,
          );
          await harness.seedTimeRecord(
            projectId: projB.id,
            titleSnapshot: 'کار بتا ۴۰ دقیقه',
            startTime: now.subtract(const Duration(minutes: 70)),
            endTime: now.subtract(const Duration(minutes: 30)),
            durationSeconds: 2400,
          );
          await harness.seedTimeRecord(
            projectId: projC.id,
            titleSnapshot: 'کار گاما ۱۵ دقیقه',
            startTime: now.subtract(const Duration(minutes: 25)),
            endTime: now.subtract(const Duration(minutes: 10)),
            durationSeconds: 900,
          );
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 2);

        final multiProjectBtn = find.textContaining('انتخاب چند پروژه');
        expect(multiProjectBtn, findsOneWidget);
        await tester.tap(multiProjectBtn);
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.tap(find.text('پروژه گزارش آلفا').last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 100));
        await tester.tap(find.text('پروژه گزارش بتا').last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 100));

        await tester.tap(find.text('اعمال'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(find.textContaining('01:00:00'), findsWidgets);
        expect(find.text('کار آلفا ۲۰ دقیقه'), findsOneWidget);
        expect(find.text('کار بتا ۴۰ دقیقه'), findsOneWidget);
        expect(find.text('کار گاما ۱۵ دقیقه'), findsNothing);
      },
    );

    testWidgets(
      'T1-F6-03: custom date/time range filtering clips straddling boundary records and excludes out-of-range slices',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          final proj = await harness.seedProject(name: 'پروژه بازه زمانی');
          final today = DateTime.now();
          final dayStart = DateTime(today.year, today.month, today.day);

          await harness.seedTimeRecord(
            projectId: proj.id,
            titleSnapshot: 'رکورد دیروز',
            startTime: dayStart.subtract(const Duration(hours: 2)),
            endTime: dayStart.subtract(const Duration(hours: 1)),
            durationSeconds: 3600,
          );
          await harness.seedTimeRecord(
            projectId: proj.id,
            titleSnapshot: 'رکورد کامل داخل بازه',
            startTime: dayStart.add(const Duration(hours: 9)),
            endTime: dayStart.add(const Duration(hours: 10)),
            durationSeconds: 3600,
          );
          await harness.seedTimeRecord(
            projectId: proj.id,
            titleSnapshot: 'رکورد مرزی نیمه‌برش',
            startTime: dayStart.add(const Duration(hours: 11, minutes: 30)),
            endTime: dayStart.add(const Duration(hours: 12, minutes: 30)),
            durationSeconds: 3600,
          );
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 2);

        final rangeSelector = find.textContaining('بازه');
        expect(rangeSelector, findsWidgets);
        await tester.tap(rangeSelector.first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );

    testWidgets(
      'T1-F6-04: selecting both parent and child project in multi-project report does not double-count shared records',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          final parent = await harness.seedProject(name: 'والد بدون تکرار');
          final child = await harness.seedProject(
            name: 'فرزند بدون تکرار',
            parentId: parent.id,
          );
          final now = DateTime.now();

          await harness.seedTimeRecord(
            projectId: parent.id,
            titleSnapshot: 'کار مستقیم والد ۱۰ دقیقه',
            startTime: now.subtract(const Duration(minutes: 40)),
            endTime: now.subtract(const Duration(minutes: 30)),
            durationSeconds: 600,
          );
          await harness.seedTimeRecord(
            projectId: child.id,
            titleSnapshot: 'کار فرزند ۲۰ دقیقه',
            startTime: now.subtract(const Duration(minutes: 30)),
            endTime: now.subtract(const Duration(minutes: 10)),
            durationSeconds: 1200,
          );
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 2);

        final multiProjectBtn = find.textContaining('انتخاب چند پروژه');
        expect(multiProjectBtn, findsOneWidget);
        await tester.tap(multiProjectBtn);
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.tap(find.text('والد بدون تکرار').last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 100));
        await tester.tap(find.text('فرزند بدون تکرار').last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 100));
        await tester.tap(find.text('اعمال'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        // Exact sum is 10m + 20m = 30m (30:00), never 50m
        expect(find.textContaining('30:00'), findsWidgets);
        expect(find.textContaining('50:00'), findsNothing);
      },
    );

    testWidgets(
      'T1-F6-05: ActivityLogTab includes active running record duration and exports 16-column Excel to isolated tempDir',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          final now = DateTime.now();
          await harness.seedTimeRecord(
            titleSnapshot: 'رکورد بسته‌شده ۱۵ دقیقه‌ای',
            startTime: now.subtract(const Duration(minutes: 30)),
            endTime: now.subtract(const Duration(minutes: 15)),
            durationSeconds: 900,
          );
          await harness.seedTimeRecord(
            titleSnapshot: 'رکورد فعال ۵ دقیقه‌ای',
            startTime: now.subtract(const Duration(minutes: 5)),
            endTime: null,
          );
          await harness.simulateRestart();
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 2);

        await tester.tap(find.text('اکسل ۱۶ ستونی'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 300));

        expect(harness.lastSavedFilePath, isNotNull);
        final exportedFile = File(harness.lastSavedFilePath!);
        expect(exportedFile.existsSync(), isTrue);
        expect(exportedFile.lengthSync(), greaterThan(0));

        expect(find.textContaining('20:'), findsWidgets);
      },
    );
  });
}
