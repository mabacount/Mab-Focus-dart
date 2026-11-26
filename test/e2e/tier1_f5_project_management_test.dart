@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/session_note.dart';
import 'package:mab_focus/services/database_service.dart';
import 'e2e_harness.dart';

void main() {
  group('Tier 1 — F5: Project Management (Create, Edit, DnD Nest, Merge)', () {
    testWidgets(
      'T1-F5-01: creates root project and nested sub-project via ProjectStudioTab form with quota and inherited hourly rate',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 3);

        await tester.tap(find.text('ریشه جدید'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.enterText(
          find.widgetWithText(TextField, 'نام پروژه یا زیرپروژه'),
          'پروژه والد آلفا',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'سهمیه هفتگی (دقیقه)'),
          '300',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'نرخ ساعتی (۰ = ارث از مادر)'),
          '500000',
        );
        await tester.tap(find.text('ذخیره پروژه'));
        await harness.pumpUntil(
          tester,
          () => harness.provider.projects
              .any((p) => p.name == 'پروژه والد آلفا'),
        );

        expect(find.text('پروژه والد آلفا'), findsWidgets);
        final parent = harness.provider.projects
            .firstWhere((p) => p.name == 'پروژه والد آلفا');
        expect(parent.weeklyQuotaMinutes, 300);
        expect(parent.hourlyRate, 500000.0);

        await tester.tap(find.byTooltip('افزودن زیرپروژه به «پروژه والد آلفا»'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.enterText(
          find.widgetWithText(TextField, 'نام پروژه یا زیرپروژه'),
          'زیرپروژه بتا',
        );
        await tester.tap(find.text('ذخیره پروژه'));
        await harness.pumpUntil(
          tester,
          () => harness.provider.projects
              .any((p) => p.name == 'زیرپروژه بتا'),
        );

        final child = harness.provider.projects
            .firstWhere((p) => p.name == 'زیرپروژه بتا');
        expect(child.parentId, parent.id);
        expect(
          DatabaseService.getEffectiveHourlyRate(
            child.id,
            harness.provider.projects,
          ),
          500000.0,
        );
      },
    );

    testWidgets(
      'T1-F5-02: edits project name and toggles suspended status with persistence across restart',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        late String projId;
        await tester.runAsync(() async {
          final p = await harness.seedProject(name: 'پروژه قدیم');
          projId = p.id;
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 3);

        await tester.tap(find.text('پروژه قدیم').first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        await tester.tap(find.text('ویرایش'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.enterText(
          find.widgetWithText(TextField, 'نام پروژه یا زیرپروژه'),
          'پروژه ویرایش‌شده',
        );
        await tester.tap(find.text('ذخیره پروژه'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(find.text('پروژه ویرایش‌شده'), findsWidgets);

        await tester.tap(find.text('تعلیق'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.runAsync(() => harness.simulateRestart());
        final persisted = harness.provider.getProjectById(projId);
        expect(persisted?.name, 'پروژه ویرایش‌شده');
        expect(persisted?.isSuspended, isTrue);
      },
    );

    testWidgets(
      'T1-F5-03: drag-and-drop nests a root project under another root project in ProjectStudioTab',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        late String parentId;
        late String childId;
        await tester.runAsync(() async {
          final parent = await harness.seedProject(name: 'مادر الف');
          final child = await harness.seedProject(name: 'فرزند ب');
          parentId = parent.id;
          childId = child.id;
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 3);

        final sourceFinder = find.text('فرزند ب').first;
        final targetFinder = find.text('مادر الف').first;
        final dragDelta =
            tester.getCenter(targetFinder) - tester.getCenter(sourceFinder);

        await tester.timedDrag(
          sourceFinder,
          dragDelta,
          const Duration(milliseconds: 400),
        );
        await harness.pumpBounded(tester, const Duration(milliseconds: 300));

        final updatedChild = harness.provider.getProjectById(childId);
        expect(updatedChild?.parentId, parentId);
      },
    );

    testWidgets(
      'T1-F5-04: drag-and-drop un-nests a child project onto the root drop zone',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        late String childId;
        await tester.runAsync(() async {
          final parent = await harness.seedProject(name: 'مادر اصلی');
          final child = await harness.seedProject(
            name: 'زیرپروژه قابل ارتقا',
            parentId: parent.id,
          );
          childId = child.id;
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 3);

        final childFinder = find.text('زیرپروژه قابل ارتقا').first;
        expect(childFinder, findsOneWidget);

        final rootDropFinder = find.textContaining('ریشه').last;
        final dragDelta =
            tester.getCenter(rootDropFinder) - tester.getCenter(childFinder);

        await tester.timedDrag(
          childFinder,
          dragDelta,
          const Duration(milliseconds: 400),
        );
        await harness.pumpBounded(tester, const Duration(milliseconds: 300));

        final updatedChild = harness.provider.getProjectById(childId);
        expect(updatedChild?.parentId, isNull);
      },
    );

    testWidgets(
      'T1-F5-05: merges source project into target project, transferring all entities and deleting source atomically',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        late String sourceId;
        late String targetId;
        late String subChildId;
        late String outcomeId;
        late String recordId;
        late String noteId;
        late String blockId;

        await tester.runAsync(() async {
          final source = await harness.seedProject(name: 'پروژه مبدا');
          final target = await harness.seedProject(name: 'پروژه مقصد');
          final subChild = await harness.seedProject(
            name: 'زیرپروژه مبدا',
            parentId: source.id,
          );
          final outcome = await harness.seedOutcome(
            projectId: source.id,
            title: 'هدف منتقل‌شونده',
          );
          final now = DateTime.now();
          final rec = await harness.seedTimeRecord(
            projectId: source.id,
            outcomeId: outcome.id,
            titleSnapshot: outcome.title,
            startTime: now.subtract(const Duration(minutes: 40)),
            endTime: now.subtract(const Duration(minutes: 10)),
            durationSeconds: 1800,
          );
          final note = await harness.seedSessionNote(
            projectId: source.id,
            outcomeId: outcome.id,
            timeRecordId: rec.id,
            noteType: SessionNoteType.report,
            content: 'یادداشت قابل انتقال',
          );
          final blk = await harness.seedScheduledBlock(
            projectId: source.id,
            outcomeId: outcome.id,
            title: 'بلوک قابل انتقال',
            startTime: now.add(const Duration(hours: 1)),
            endTime: now.add(const Duration(hours: 2)),
          );

          sourceId = source.id;
          targetId = target.id;
          subChildId = subChild.id;
          outcomeId = outcome.id;
          recordId = rec.id;
          noteId = note.id;
          blockId = blk.id;
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 3);

        await tester.tap(find.text('پروژه مبدا').first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        final mergeButton = find.textContaining('ادغام');
        expect(mergeButton, findsWidgets);
        await tester.tap(mergeButton.first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.tap(find.text('پروژه مقصد').last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        final confirmMerge = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('ادغام'),
        );
        await tester.tap(confirmMerge.last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 300));

        expect(harness.provider.getProjectById(sourceId), isNull);
        expect(harness.provider.getProjectById(subChildId)?.parentId, targetId);
        expect(harness.provider.getOutcomeById(outcomeId)?.projectId, targetId);
        expect(
          harness.provider.timeRecords
              .firstWhere((r) => r.id == recordId)
              .projectId,
          targetId,
        );
        expect(
          harness.provider.sessionNotes
              .firstWhere((n) => n.id == noteId)
              .projectId,
          targetId,
        );
        expect(
          harness.provider.scheduledBlocks
              .firstWhere((b) => b.id == blockId)
              .projectId,
          targetId,
        );
      },
    );
  });
}
