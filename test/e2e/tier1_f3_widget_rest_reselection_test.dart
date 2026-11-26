@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/ui/shared/nature_slideshow_overlay.dart';
import 'package:mab_focus/ui/shared/searchable_task_input.dart';
import 'package:mab_focus/ui/widget_mode/floating_widget_view.dart';
import 'package:mab_focus/ui/widget_mode/quick_task_sheet.dart';
import 'e2e_harness.dart';

void main() {
  group('Tier 1 — F3: Widget & Rest-Mode Task Re-Selection', () {
    testWidgets(
      'T1-F3-01: FloatingWidgetView expands QuickTaskSheet, searches and selects an open Work outcome',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.seedOutcome(
            realm: AppRealm.work,
            title: 'مستندسازی API سرویس',
          );
          await harness.provider.setWindowPosture(WindowPosture.floatingCircle);
        });

        await harness.pumpApp(tester, surfaceSize: const Size(480, 720));
        expect(find.byType(FloatingWidgetView), findsOneWidget);

        await harness.hoverFloatingWidget(tester);
        await tester.tap(find.byTooltip('پنل سریع کارهای باز و بانک استراحت'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(find.byType(QuickTaskSheet), findsOneWidget);

        final inputField = find.descendant(
          of: find.byType(SearchableTaskInput),
          matching: find.byType(TextField),
        );
        await tester.tap(inputField.first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));
        await tester.enterText(inputField.first, 'API');
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        await tester.tap(find.text('مستندسازی API سرویس').last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(harness.provider.activeOutcome?.title, 'مستندسازی API سرویس');
        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(harness.provider.isQuickMenuExpanded, isFalse);
      },
    );

    testWidgets(
      'T1-F3-02: QuickTaskSheet creates a new task inline and switches mid-session via From Now On',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.provider.startInstantWork(title: 'تسک اول جلسه');
          await harness.provider.setWindowPosture(WindowPosture.floatingCircle);
          await harness.provider.toggleQuickMenuExpanded(true);
        });

        await harness.pumpApp(tester, surfaceSize: const Size(480, 720));
        expect(find.byType(QuickTaskSheet), findsOneWidget);

        final inputField = find.descendant(
          of: find.byType(SearchableTaskInput),
          matching: find.byType(TextField),
        );
        await tester.tap(inputField.first);
        await tester.enterText(inputField.first, 'تسک دوم جدید');
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        await tester.tap(find.text('از حالا به بعد'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(harness.provider.activeRecord?.titleSnapshot, 'تسک دوم جدید');
        expect(
          harness.provider.timeRecords
              .where((r) => r.titleSnapshot == 'تسک اول جلسه' && r.endTime != null)
              .length,
          1,
        );
      },
    );

    testWidgets(
      'T1-F3-03: QuickTaskSheet allows re-selecting a previously completed task and auto-reopens it',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        late String completedId;
        await tester.runAsync(() async {
          final completed = await harness.seedOutcome(
            realm: AppRealm.work,
            title: 'بازبینی امنیتی کد',
            isCompleted: true,
          );
          completedId = completed.id;
          await harness.provider.setWindowPosture(WindowPosture.floatingCircle);
          await harness.provider.toggleQuickMenuExpanded(true);
        });

        await harness.pumpApp(tester, surfaceSize: const Size(480, 720));
        expect(find.byType(QuickTaskSheet), findsOneWidget);

        final inputField = find.descendant(
          of: find.byType(SearchableTaskInput),
          matching: find.byType(TextField),
        );
        await tester.tap(inputField.first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));
        await tester.enterText(inputField.first, 'بازبینی امنیتی');
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        final suggestion = find.text('بازبینی امنیتی کد');
        expect(suggestion, findsWidgets);
        await tester.tap(suggestion.last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(harness.provider.activeRecord?.titleSnapshot, 'بازبینی امنیتی کد');
        expect(harness.provider.activeRecord?.outcomeId, completedId);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        final reopened = harness.provider.getOutcomeById(completedId);
        expect(reopened?.isCompleted, isFalse);
      },
    );

    testWidgets(
      'T1-F3-04: QuickTaskSheet allows re-selecting a historical TimeRecord-only task without OutcomeItem',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          final now = DateTime.now();
          await harness.seedTimeRecord(
            realm: AppRealm.work,
            outcomeId: null,
            titleSnapshot: 'جلسه معماری هفته پیش',
            startTime: now.subtract(const Duration(days: 3, hours: 1)),
            endTime: now.subtract(const Duration(days: 3)),
            durationSeconds: 3600,
          );
          await harness.provider.setWindowPosture(WindowPosture.floatingCircle);
          await harness.provider.toggleQuickMenuExpanded(true);
        });

        await harness.pumpApp(tester, surfaceSize: const Size(480, 720));

        final inputField = find.descendant(
          of: find.byType(SearchableTaskInput),
          matching: find.byType(TextField),
        );
        await tester.tap(inputField.first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));
        await tester.enterText(inputField.first, 'معماری');
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        final historicalSuggestion = find.text('جلسه معماری هفته پیش');
        expect(historicalSuggestion, findsWidgets);
        await tester.tap(historicalSuggestion.last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(
          harness.provider.activeRecord?.titleSnapshot,
          'جلسه معماری هفته پیش',
        );
        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(harness.provider.timeRecords.length, greaterThanOrEqualTo(2));
      },
    );

    testWidgets(
      'T1-F3-05: from Life/Rest mode (NatureSlideshowOverlay), user can re-select a Work task to switch back to Work and start recording',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.seedOutcome(
            realm: AppRealm.work,
            title: 'توسعه بک‌اند هسته',
          );
          await harness.provider.startInstantWork(title: 'کار قبلی');
          await harness.provider.switchRealm(AppRealm.life);
        });

        await harness.pumpApp(tester);
        expect(find.byType(NatureSlideshowOverlay), findsOneWidget);

        final restTaskInput = find.descendant(
          of: find.byType(NatureSlideshowOverlay),
          matching: find.byType(SearchableTaskInput),
        );
        expect(restTaskInput, findsOneWidget);

        final textField = find.descendant(
          of: restTaskInput,
          matching: find.byType(TextField),
        );
        await tester.tap(textField.first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));
        await tester.enterText(textField.first, 'بک‌اند');
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        await tester.tap(find.text('توسعه بک‌اند هسته').last);
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(harness.provider.pomodoroState.realm, AppRealm.work);
        expect(harness.provider.pomodoroState.status, TimerStatus.running);
        expect(harness.provider.activeRecord?.titleSnapshot, 'توسعه بک‌اند هسته');
        expect(find.byType(NatureSlideshowOverlay), findsNothing);
      },
    );
  });
}
