@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/core/constants.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:mab_focus/ui/dashboard_mode/dashboard_screen.dart';
import 'package:mab_focus/ui/shared/nature_slideshow_overlay.dart';
import 'package:mab_focus/ui/widget_mode/floating_widget_view.dart';
import 'e2e_harness.dart';

void main() {
  group('Tier 1 — F2: Startup Window & Posture Recovery', () {
    testWidgets(
      'T1-F2-01: startup with open Work TimeRecord displays recovery banner and Continue resumes seamlessly',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.seedTimeRecord(
            realm: AppRealm.work,
            titleSnapshot: 'توسعه ماژول بازیابی',
            startTime: DateTime.now().subtract(const Duration(minutes: 14)),
            endTime: null,
          );
          await harness.simulateRestart();
        });

        await harness.pumpApp(tester);

        expect(find.textContaining('بازیابی جلسه ناتمام'), findsOneWidget);
        expect(find.text('ادامه همین جلسه'), findsOneWidget);
        expect(find.text('بستن در ساعت دلخواه'), findsOneWidget);

        await tester.tap(find.text('ادامه همین جلسه'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        expect(find.textContaining('بازیابی جلسه ناتمام'), findsNothing);
        expect(harness.provider.recoveredOpenRecord, isNull);
        expect(harness.provider.activeRecord, isNotNull);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);
      },
    );

    testWidgets(
      'T1-F2-02: recovery dialog closes open Work record at custom time and starts continuous Life slice',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.provider.setLifeNatureSlideshowEnabled(false);
          await harness.seedTimeRecord(
            id: 'open_rec_custom',
            realm: AppRealm.work,
            titleSnapshot: 'کار نیمه‌تمام دیشب',
            startTime: DateTime.now().subtract(const Duration(minutes: 30)),
            endTime: null,
          );
          await harness.simulateRestart();
        });

        await harness.pumpApp(tester);

        await tester.tap(find.text('بستن در ساعت دلخواه'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        expect(find.text('اصلاح زمان پایان رکورد بازمانده'), findsOneWidget);
        await tester.tap(find.text('زندگی (سبز)'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        await tester.tap(find.text('تایید و ثبت پیوسته'));
        await harness.pumpUntil(
          tester,
          () =>
              harness.provider.recoveredOpenRecord == null &&
              harness.provider.pomodoroState.realm == AppRealm.life,
        );

        expect(find.textContaining('بازیابی جلسه ناتمام'), findsNothing);
        expect(harness.provider.pomodoroState.realm, AppRealm.life);
        expect(harness.provider.activeRecord, isNotNull);
        expect(harness.provider.activeRecord!.id, isNot('open_rec_custom'));

        await tester.runAsync(() async {
          final oldRec =
              await DatabaseService.instance.getTimeRecordById('open_rec_custom');
          expect(oldRec?.endTime, isNotNull);
          expect(oldRec?.isEdited, isTrue);
        });
      },
    );

    testWidgets(
      'T1-F2-03: posture transitions cleanly from Dashboard to FloatingWidgetView and back to Dashboard',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester);
        expect(find.byType(DashboardScreen), findsOneWidget);

        await tester.tap(find.text('ویجت شناور'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(find.byType(FloatingWidgetView), findsOneWidget);
        expect(
          harness.provider.pomodoroState.windowPosture,
          WindowPosture.floatingCircle,
        );

        await harness.hoverFloatingWidget(tester);
        await tester.tap(find.byTooltip('داشبورد کامل'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(
          harness.provider.pomodoroState.windowPosture,
          WindowPosture.dashboard,
        );
        expect(harness.mockResizable, isTrue);
        expect(harness.mockMovable, isTrue);
      },
    );

    testWidgets(
      'T1-F2-04: entering Life mode renders NatureSlideshowOverlay and dismissing restores movable Dashboard posture',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester);

        await tester.tap(find.byTooltip('ورود به قلمرو زندگی (استراحت)'));
        await harness.pumpUntil(
          tester,
          () => find.byType(NatureSlideshowOverlay).evaluate().isNotEmpty,
        );

        expect(find.byType(NatureSlideshowOverlay), findsOneWidget);
        expect(find.text('قلمرو زندگی و استراحت'), findsOneWidget);

        await tester.tap(find.byTooltip('بستن اسلایدشو (Esc)'));
        await harness.pumpUntil(
          tester,
          () => find.byType(DashboardScreen).evaluate().isNotEmpty,
        );

        expect(find.byType(NatureSlideshowOverlay), findsNothing);
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(
          harness.provider.pomodoroState.windowPosture,
          WindowPosture.dashboard,
        );
        expect(harness.mockFullScreen, isFalse);
        expect(harness.mockResizable, isTrue);
        expect(harness.mockMovable, isTrue);
      },
    );

    testWidgets(
      'T1-F2-05: startup with open Life TimeRecord and slideshow enabled recovers into movable, bounded posture on exit',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(
          tester,
          seedDb: (db) async {
            await DatabaseService.instance.setSetting(
              AppDefaults.settingKeyLifeNatureSlideshowEnabled,
              '1',
            );
          },
        );
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.seedTimeRecord(
            realm: AppRealm.life,
            titleSnapshot: 'استراحت بازمانده',
            startTime: DateTime.now().subtract(const Duration(minutes: 8)),
            endTime: null,
          );
          await harness.simulateRestart();
        });

        await harness.pumpApp(tester);

        if (find.byType(NatureSlideshowOverlay).evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('بستن اسلایدشو (Esc)'));
          await harness.pumpBounded(tester, const Duration(milliseconds: 250));
        }

        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(
          harness.provider.pomodoroState.windowPosture,
          WindowPosture.dashboard,
        );
        expect(harness.mockFullScreen, isFalse);
        expect(harness.mockResizable, isTrue);
        expect(harness.mockMovable, isTrue);
        expect(harness.mockWindowBounds.left, greaterThanOrEqualTo(0));
        expect(harness.mockWindowBounds.top, greaterThanOrEqualTo(0));
        expect(
          harness.mockWindowBounds.right,
          lessThanOrEqualTo(harness.primaryDisplaySize.width),
        );
        expect(
          harness.mockWindowBounds.bottom,
          lessThanOrEqualTo(harness.primaryDisplaySize.height),
        );
      },
    );
  });
}
