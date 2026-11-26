@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/models/session_note.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:mab_focus/ui/dashboard_mode/activity_log_tab.dart';
import 'package:mab_focus/ui/shared/searchable_task_input.dart';
import 'e2e_harness.dart';

void main() {
  group('Tier 1 — F7: Calendar, Inbox, Notes, Settings & Versioning', () {
    testWidgets(
      'T1-F7-01: CalendarGridTab creates manual TimeRecord with isEdited audit and supports Undo',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 0);

        await tester.tap(find.text('ثبت دستی +'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.enterText(
          find.widgetWithText(TextField, 'عنوان فعالیت انجام‌شده'),
          'جلسه دیزاین معماری',
        );
        await tester.tap(find.text('ثبت گزارش دستی'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(
          harness.provider.timeRecords.any(
            (r) => r.titleSnapshot == 'جلسه دیزاین معماری' && r.isEdited,
          ),
          isTrue,
        );

        await tester.tap(find.byIcon(Icons.undo_rounded));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(
          harness.provider.timeRecords
              .any((r) => r.titleSnapshot == 'جلسه دیزاین معماری'),
          isFalse,
        );
      },
    );

    testWidgets(
      'T1-F7-02: CalendarGridTab creates scheduled block, toggles 1D/3D/7D and timesheet view, and quick-starts block',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 0);

        await tester.tap(find.text('برنامه جدید'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'عنوان برنامه (مثلاً: کدنویسی یا ورزش)',
          ),
          'برنامه تست یکپارچه',
        );
        await tester.tap(find.text('ثبت در تقویم'));
        await harness.pumpUntil(
          tester,
          () => harness.provider.scheduledBlocks
              .any((b) => b.title == 'برنامه تست یکپارچه'),
        );

        expect(
          harness.provider.scheduledBlocks
              .any((b) => b.title == 'برنامه تست یکپارچه'),
          isTrue,
        );

        await tester.tap(find.text('1D'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));
        await tester.tap(find.text('3D'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));
        await tester.tap(find.text('7D'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        await tester.tap(find.text('جدول تایم‌شیت'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));
        expect(find.byType(ActivityLogTab), findsOneWidget);

        await tester.tap(find.text('نمای تقویم'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'T1-F7-03: UntitledInboxTab resolves untitled draft without setting isEdited and clears inbox',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        late String draftId;
        await tester.runAsync(() async {
          final now = DateTime.now();
          final rec = await harness.seedTimeRecord(
            titleSnapshot: 'تسک بدون عنوان',
            isUntitledDraft: true,
            startTime: now.subtract(const Duration(minutes: 10)),
            endTime: now.subtract(const Duration(minutes: 5)),
            durationSeconds: 300,
          );
          draftId = rec.id;
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 5);

        expect(find.textContaining('5.0 دقیقه'), findsOneWidget);

        final inboxInput = find.descendant(
          of: find.byType(SearchableTaskInput),
          matching: find.byType(TextField),
        );
        await tester.enterText(inboxInput.first, 'بازبینی مستندات فنی');
        await harness.pumpBounded(tester, const Duration(milliseconds: 150));

        await tester.tap(find.text('تکمیل و اتصال'));
        await harness.pumpUntil(
          tester,
          () => find
              .text('عالی! هیچ رکورد بدون عنوانی در کارتابل وجود ندارد.')
              .evaluate()
              .isNotEmpty,
        );

        expect(
          find.text('عالی! هیچ رکورد بدون عنوانی در کارتابل وجود ندارد.'),
          findsOneWidget,
        );

        await tester.runAsync(() async {
          final updated = await DatabaseService.instance.getTimeRecordById(draftId);
          expect(updated?.titleSnapshot, 'بازبینی مستندات فنی');
          expect(updated?.isUntitledDraft, isFalse);
          expect(updated?.isEdited, isFalse);
        });
      },
    );

    testWidgets(
      'T1-F7-04: WorkNoteDialog creates a triple-linked SessionNote and EditSessionNoteDialog edits it in ActivityLogTab',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await tester.runAsync(() async {
          await harness.provider.startInstantWork(title: 'توسعه ویژگی جدید');
        });

        await harness.pumpApp(tester);
        await harness.navigateToTab(tester, 2);

        await tester.tap(find.text('ثبت یادداشت +'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(find.textContaining('ثبت یادداشت حین فعالیت'), findsOneWidget);

        await tester.ensureVisible(find.text(SessionNoteType.idea.labelFa));
        await tester.tap(find.text(SessionNoteType.idea.labelFa));
        await harness.pumpBounded(tester, const Duration(milliseconds: 100));

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'برنامه، چالش، گزارش پیشرفت یا ایده لحظه‌ای را بنویسید...',
          ),
          'ایده بهینه‌سازی کش SQLite',
        );
        await tester.ensureVisible(find.text('ثبت یادداشت'));
        await tester.tap(find.text('ثبت یادداشت'));
        await harness.pumpUntil(
          tester,
          () => harness.provider.sessionNotes
              .any((n) => n.content == 'ایده بهینه‌سازی کش SQLite'),
        );

        await tester.tap(find.text('دفترچه یادداشت‌های جلسات'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(find.text('ایده بهینه‌سازی کش SQLite'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.drive_file_move_outlined).first);
        await harness.pumpBounded(tester, const Duration(milliseconds: 200));

        expect(find.text('ویرایش و انتقال یادداشت'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'متن یادداشت را اینجا بنویسید...'),
          'ایده نهایی بهینه‌سازی کش',
        );
        await tester.tap(find.text('ذخیره و انتقال'));
        await harness.pumpUntil(
          tester,
          () => find.text('ایده نهایی بهینه‌سازی کش').evaluate().isNotEmpty,
        );

        expect(find.text('ایده نهایی بهینه‌سازی کش'), findsOneWidget);
      },
    );

    testWidgets(
      'T1-F7-05: SettingsTab persists Flowmodoro settings and Dashboard + Settings About card display v4.1.0+2 metadata',
      (tester) async {
        final harness = await E2eTestHarness.createForTest(tester);
        addTearDown(() => harness.dispose(tester));

        await harness.pumpApp(tester);

        expect(find.textContaining('4.1.0'), findsOneWidget);

        await harness.navigateToTab(tester, 6);

        await tester.enterText(
          find.widgetWithText(TextField, 'هدف تمرکز (دقیقه)'),
          '30',
        );
        await tester.tap(find.text('ذخیره تنظیمات ریتم'));
        await harness.pumpBounded(tester, const Duration(milliseconds: 250));

        expect(harness.provider.focusDurationMinutes, 30);

        expect(find.textContaining('4.1.0+2'), findsOneWidget);
      },
    );
  });
}
