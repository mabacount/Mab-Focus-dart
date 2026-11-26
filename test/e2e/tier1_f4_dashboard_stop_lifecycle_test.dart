@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/services/database_service.dart';
import 'e2e_harness.dart';

void main() {
  group('Tier 1 — F4: Dashboard Stop & Recording Lifecycle', () {
    testWidgets(
      'T1-F4-01: clicking Stop on DashboardScreen closes active Work record and sets TimerStatus.idle',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.provider.startInstantWork(title: 'کدنویسی ماژول');
        });

        await harness.pumpApp(tester);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);

        final stopButton = find.descendant(
          of: find.byType(AppBar),
          matching: find.textContaining('توقف'),
        );
        expect(stopButton, findsOneWidget);

        await tester.tap(stopButton);
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.status == TimerStatus.idle &&
              find.text('متوقف').evaluate().isNotEmpty,
        );

        expect(harness.provider.pomodoroState.status, TimerStatus.idle);
        expect(harness.provider.activeRecord, isNull);
        expect(find.text('متوقف'), findsOneWidget);
        expect(find.text('تایمر متوقف است'), findsOneWidget);

        await tester.runAsync(() async {
          final open = await DatabaseService.instance.getOpenTimeRecords();
          expect(open, isEmpty);
        });
      },
    );

    testWidgets(
      'T1-F4-02: after clicking Stop on Dashboard, closing and reopening later does NOT accumulate elapsed time',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        final startedAt = DateTime.now().subtract(const Duration(minutes: 10));
        await tester.runAsync(() async {
          await harness.seedTimeRecord(
            id: 'rec_stop_persist',
            realm: AppRealm.work,
            titleSnapshot: 'تحلیل نیازمندی‌ها',
            startTime: startedAt,
            endTime: null,
          );
          await harness.simulateRestart();
        });

        await harness.pumpApp(tester);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);

        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.textContaining('توقف'),
          ),
        );
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.status == TimerStatus.idle &&
              harness.provider.activeRecord == null &&
              find.text('متوقف').evaluate().isNotEmpty,
        );

        late int durationAtStop;
        late DateTime endAtStop;
        await tester.runAsync(() async {
          final rec =
              await DatabaseService.instance.getTimeRecordById('rec_stop_persist');
          expect(rec, isNotNull);
          expect(rec!.endTime, isNotNull);
          durationAtStop = rec.durationSeconds;
          endAtStop = rec.endTime!;

          await harness.simulateRestart();
        });

        await harness.pumpApp(tester);

        expect(harness.provider.pomodoroState.status, TimerStatus.idle);
        expect(harness.provider.activeRecord, isNull);
        expect(harness.provider.recoveredOpenRecord, isNull);
        expect(find.textContaining('بازیابی جلسه ناتمام'), findsNothing);
        expect(find.text('متوقف'), findsOneWidget);

        await tester.runAsync(() async {
          final recAfter =
              await DatabaseService.instance.getTimeRecordById('rec_stop_persist');
          expect(recAfter?.durationSeconds, durationAtStop);
          expect(recAfter?.endTime, endAtStop);
          expect(await DatabaseService.instance.getOpenTimeRecords(), isEmpty);
        });
      },
    );

    testWidgets(
      'T1-F4-03: closing and reopening WITHOUT clicking Stop preserves active recording and recovers elapsed time',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.seedTimeRecord(
            id: 'rec_unstopped',
            realm: AppRealm.work,
            titleSnapshot: 'تسک پیوسته بدون توقف',
            startTime: DateTime.now().subtract(const Duration(minutes: 20)),
            endTime: null,
          );
          await harness.simulateRestart();
        });

        await harness.pumpApp(tester);

        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(harness.provider.activeRecord?.id, 'rec_unstopped');
        expect(harness.provider.activeRecordElapsedSeconds, greaterThanOrEqualTo(1195));
        expect(find.textContaining('بازیابی جلسه ناتمام'), findsOneWidget);
      },
    );

    testWidgets(
      'T1-F4-04: clicking Stop during Life mode closes Life record and returns Dashboard to idle',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.provider.setLifeNatureSlideshowEnabled(false);
          await harness.provider.switchRealm(AppRealm.life, title: 'استراحت کوتاه');
        });

        await harness.pumpApp(tester);
        expect(harness.provider.pomodoroState.realm, AppRealm.life);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);

        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.textContaining('توقف'),
          ),
        );
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.status == TimerStatus.idle &&
              harness.provider.activeRecord == null &&
              find.text('متوقف').evaluate().isNotEmpty,
        );

        expect(harness.provider.pomodoroState.status, TimerStatus.idle);
        expect(harness.provider.activeRecord, isNull);
        expect(harness.provider.shouldShowNatureSlideshow, isFalse);

        await tester.runAsync(() async {
          expect(await DatabaseService.instance.getOpenTimeRecords(), isEmpty);
        });
      },
    );

    testWidgets(
      'T1-F4-05: Dashboard displays a prominent labeled Stop control when active, and starting after Stop creates a fresh record',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.provider.startInstantWork(title: 'جلسه اول');
        });

        await harness.pumpApp(tester);
        final firstId = harness.provider.activeRecord!.id;

        final labeledStop = find.descendant(
          of: find.byType(AppBar),
          matching: find.textContaining('توقف'),
        );
        expect(labeledStop, findsOneWidget);

        await tester.tap(labeledStop);
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.status == TimerStatus.idle &&
              find.byIcon(Icons.play_circle_fill_rounded).evaluate().isNotEmpty,
        );

        expect(harness.provider.pomodoroState.status, TimerStatus.idle);
        expect(harness.provider.activeRecord, isNull);

        await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.status == TimerStatus.running &&
              harness.provider.activeRecord != null,
        );

        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(harness.provider.activeRecord, isNotNull);
        expect(harness.provider.activeRecord!.id, isNot(firstId));
      },
    );
  });
}
