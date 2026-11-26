@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/core/constants.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/services/database_service.dart';
import 'e2e_harness.dart';

void main() {
  group('Tier 1 — F1: Dual-Realm & Flowmodoro', () {
    testWidgets(
      'T1-F1-01: dashboard realm toggle switches Work/Life palette and scopes Open Outcomes without stopping active timer',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.seedOutcome(
            realm: AppRealm.work,
            title: 'تسک آلفا کار',
          );
          await harness.seedOutcome(
            realm: AppRealm.life,
            title: 'تسک بتا زندگی',
          );
          await harness.provider.startInstantWork(title: 'جلسه فعال کار');
        });

        await harness.pumpApp(tester);

        expect(harness.provider.dashboardRealm, AppRealm.work);
        expect(harness.provider.activePalette.accent, RealmPalette.work.accent);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);

        await harness.navigateToTab(tester, 1);
        expect(find.text('تسک آلفا کار'), findsOneWidget);
        expect(find.text('تسک بتا زندگی'), findsNothing);

        // Toggle dashboard view realm to Life (UI filter only)
        await tester.tap(find.text('زندگی').first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        expect(harness.provider.dashboardRealm, AppRealm.life);
        expect(harness.provider.activePalette.accent, RealmPalette.life.accent);
        expect(harness.provider.pomodoroState.realm, AppRealm.work);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(find.text('تسک بتا زندگی'), findsOneWidget);
        expect(find.text('تسک آلفا کار'), findsNothing);
      },
    );

    testWidgets(
      'T1-F1-02: header Play and Work/Life toggle start Work session and enter Life break with Flowmodoro target',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.provider.setLifeNatureSlideshowEnabled(false);
        });

        await harness.pumpApp(tester);
        expect(find.text('متوقف'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.status == TimerStatus.running &&
              harness.provider.activeRecord != null,
        );

        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(harness.provider.pomodoroState.realm, AppRealm.work);
        expect(harness.provider.activeRecord, isNotNull);

        await tester.tap(find.byTooltip('ورود به قلمرو زندگی (استراحت)'));
        await harness.pumpUntil(
          tester,
          () => harness.provider.pomodoroState.realm == AppRealm.life,
        );

        expect(harness.provider.pomodoroState.realm, AppRealm.life);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(
          harness.provider.pomodoroState.targetSeconds,
          greaterThanOrEqualTo(AppDurations.defaultShortBreakSeconds),
        );
      },
    );

    testWidgets(
      'T1-F1-03: header ClockType toggle switches Pomodoro and Stopwatch and records mode in SQLite',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester);

        await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.status == TimerStatus.running &&
              harness.provider.activeRecord != null,
        );
        expect(harness.provider.pomodoroState.isPomodoro, isTrue);

        await tester.tap(find.byTooltip('تغییر ساعت به کرنومتر آزاد'));
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.pomodoroState.isStopwatch &&
              harness.provider.activeRecord?.clockMode == ClockType.stopwatch,
        );

        expect(harness.provider.pomodoroState.isStopwatch, isTrue);
        expect(harness.provider.pomodoroState.targetSeconds, 0);
        expect(find.byIcon(Icons.timelapse_rounded), findsOneWidget);

        await tester.runAsync(() async {
          final records = await DatabaseService.instance.getAllTimeRecords();
          expect(
            records.any((r) => r.clockMode == ClockType.stopwatch),
            isTrue,
          );
        });

        await tester.tap(find.byTooltip('تغییر ساعت به پومودورو'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));
        expect(harness.provider.pomodoroState.isPomodoro, isTrue);
      },
    );

    testWidgets(
      'T1-F1-04: Flowmodoro break bank accumulates from Work slice and renders earned break on SettingsTab',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        final t0 = DateTime(2026, 11, 20, 9, 0);
        await tester.runAsync(() async {
          await harness.provider.setLifeNatureSlideshowEnabled(false);
          await harness.provider.resetFlowmodoroCycle(atTime: t0);
          await harness.provider.switchRealm(
            AppRealm.work,
            title: 'کدنویسی ۵۰ دقیقه‌ای',
            atTime: t0,
          );
          await harness.provider.switchRealm(
            AppRealm.life,
            atTime: t0.add(const Duration(minutes: 50)),
          );
        });

        expect(harness.provider.cycleWorkSeconds, 3000);
        expect(harness.provider.earnedShortBreakSeconds, 600);
        expect(harness.provider.pomodoroState.targetSeconds, 600);

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 6);

        expect(find.text('وضعیت لحظه‌ای بانک استراحت و چرخه Flowmodoro'), findsOneWidget);
        expect(find.textContaining('50:00'), findsWidgets);
        expect(find.textContaining('10:00'), findsWidgets);
      },
    );

    testWidgets(
      'T1-F1-05: SettingsTab manual Flowmodoro cycle reset zeroes W_cycle, B_earned, and D_break and persists',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        final t0 = DateTime(2026, 11, 20, 10, 0);
        await tester.runAsync(() async {
          await harness.provider.setLifeNatureSlideshowEnabled(false);
          await harness.provider.resetFlowmodoroCycle(atTime: t0);
          await harness.provider.switchRealm(
            AppRealm.work,
            title: 'جلسه پرحجم',
            atTime: t0,
          );
          await harness.provider.switchRealm(
            AppRealm.life,
            atTime: t0.add(const Duration(minutes: 25)),
          );
        });

        expect(harness.provider.cycleWorkSeconds, greaterThan(0));
        expect(harness.provider.earnedShortBreakSeconds, greaterThan(0));

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 6);

        await tester.tap(find.text('ریست دستی چرخه Flowmodoro'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(harness.provider.cycleWorkSeconds, 0);
        expect(harness.provider.earnedShortBreakSeconds, 0);
        expect(harness.provider.breakDebtSeconds, 0);

        await tester.runAsync(() => harness.simulateRestart());
        expect(harness.provider.cycleWorkSeconds, 0);
        expect(harness.provider.earnedShortBreakSeconds, 0);
        expect(harness.provider.breakDebtSeconds, 0);
      },
    );
  });
}
