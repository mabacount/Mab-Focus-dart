import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/core/date_time_utils.dart';
import 'package:mab_focus/models/outcome_item.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/project_node.dart';
import 'package:mab_focus/models/session_note.dart';
import 'package:mab_focus/models/time_record.dart';
import 'package:mab_focus/providers/app_state_provider.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<(Database, AppStateProvider)> createTestProvider() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 5,
        singleInstance: false,
        onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
      ),
    );
    DatabaseService.instance.setTestDatabase(db);
    final provider = AppStateProvider(isTestMode: true);
    await provider.initialize();
    return (db, provider);
  }

  tearDown(() {
    DatabaseService.instance.resetForTest();
  });

  group('Flowmodoro Engine & Break Bank Tests', () {
    test('calculates spec §3.2 50m->30m->50m->40m long break debt accurately',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 9, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      // ۱. ۵۰ دقیقه کار (۳۰۰۰ ثانیه) -> استراحت ذخیره: ۶۰۰ ثانیه (۱۰ دقیقه)
      await provider.switchRealm(AppRealm.work, title: 'کار اول', atTime: t0);
      final t1 = t0.add(const Duration(minutes: 50));
      await provider.switchRealm(AppRealm.life, atTime: t1);

      expect(provider.cycleWorkSeconds, 3000);
      expect(provider.earnedShortBreakSeconds, 600);
      expect(provider.breakDebtSeconds, 0);
      expect(provider.isInLongBreak, isFalse);
      expect(provider.pomodoroState.targetSeconds, 600);

      // ۲. ۳۰ دقیقه زندگی (۱۸۰۰ ثانیه) -> مصرف ۶۰۰ ثانیه ذخیره + ثبت ۱۲۰۰ ثانیه بدهی (۲۰ دقیقه)
      final t2 = t1.add(const Duration(minutes: 30));
      await provider.switchRealm(AppRealm.work, title: 'کار دوم', atTime: t2);

      expect(provider.cycleWorkSeconds, 3000);
      expect(provider.earnedShortBreakSeconds, 0);
      expect(provider.breakDebtSeconds, 1200);

      // ۳. ۵۰ دقیقه کار دوم (۳۰۰۰ ثانیه دیگر) -> کل کار چرخه ۶۰۰۰ ثانیه (رسیدن به سقف ۱۰۰ دقیقه)
      final t3 = t2.add(const Duration(minutes: 50));
      await provider.switchRealm(AppRealm.life, atTime: t3);

      expect(provider.cycleWorkSeconds, 6000);
      expect(provider.isInLongBreak, isTrue);
      // هدف استراحت طولانی = max(300, 3600 - 1200 + 0) = 2400 ثانیه (۴۰ دقیقه)
      expect(provider.currentBreakTargetSeconds, 2400);
      expect(provider.pomodoroState.targetSeconds, 2400);

      // ۴. پس از اتمام استراحت طولانی و ورود به کار بعدی، چرخه صفر می‌شود
      final t4 = t3.add(const Duration(minutes: 40));
      await provider.switchRealm(AppRealm.work, title: 'چرخه جدید', atTime: t4);
      expect(provider.cycleWorkSeconds, 0);
      expect(provider.earnedShortBreakSeconds, 0);
      expect(provider.breakDebtSeconds, 0);
      expect(provider.isInLongBreak, isFalse);

      await db.close();
    });

    test('enforces 5m short break floor and carries over unused break credit',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 10, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      // ۱۵ دقیقه کار -> ۱۸۰ ثانیه (۳ دقیقه) ذخیره؛ کف ورود باید ۵ دقیقه (۳۰۰ ثانیه) باشد
      await provider.switchRealm(AppRealm.work, title: 'کار کوتاه', atTime: t0);
      final t1 = t0.add(const Duration(minutes: 15));
      await provider.switchRealm(AppRealm.life, atTime: t1);

      expect(provider.earnedShortBreakSeconds, 180);
      expect(provider.pomodoroState.targetSeconds, 300);

      // کاربر فقط ۲ دقیقه (۱۲۰ ثانیه) استراحت می‌کند و برمی‌گردد -> ۶۰ ثانیه در بانک باقی می‌ماند
      final t2 = t1.add(const Duration(minutes: 2));
      await provider.switchRealm(AppRealm.work, title: 'ادامه کار', atTime: t2);

      expect(provider.earnedShortBreakSeconds, 60);
      expect(provider.breakDebtSeconds, 0);

      await db.close();
    });

    test('stopwatch work slices credit W_cycle and B_earned identically & overshoot adds bonus',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 11, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      // ۱۱۰ دقیقه کار با کرنومتر آزاد (۶۶۰۰ ثانیه -> ۱۰ دقیقه سرریز بالای ۱۰۰ دقیقه)
      await provider.switchRealm(
        AppRealm.work,
        title: 'تمرکز عمیق با کرنومتر',
        clockType: ClockType.stopwatch,
        atTime: t0,
      );
      final t1 = t0.add(const Duration(minutes: 110));
      await provider.switchRealm(
        AppRealm.life,
        clockType: ClockType.pomodoro,
        atTime: t1,
      );

      expect(provider.cycleWorkSeconds, 6600);
      expect(provider.isInLongBreak, isTrue);
      // 3600 + ((6600 - 6000) ~/ 5) = 3600 + 120 = 3720 (62 دقیقه)
      expect(provider.currentBreakTargetSeconds, 3720);

      await db.close();
    });
  });

  group('7 Engineering Challenges Verification Tests', () {
    test('Ch1: auto-resets cycle on >=90m Life slice and Sleep project hierarchy',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 14, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      // ۱. ریست خودکار با برش زندگی >= ۹۰ دقیقه
      await provider.switchRealm(AppRealm.work, title: 'کار قبل ناهار', atTime: t0);
      final t1 = t0.add(const Duration(minutes: 50));
      await provider.switchRealm(AppRealm.life, atTime: t1);
      expect(provider.cycleWorkSeconds, 3000);

      final t2 = t1.add(const Duration(minutes: 95));
      await provider.switchRealm(AppRealm.work, title: 'کار عصر', atTime: t2);
      expect(provider.cycleWorkSeconds, 0);
      expect(provider.earnedShortBreakSeconds, 0);
      expect(provider.breakDebtSeconds, 0);

      // ۲. ریست خودکار با زیرپروژه زیر چتر پروژه خواب (حتی اگر کوتاه باشد)
      final sleepRoot = ProjectNode(
        id: 'p_sleep_root',
        realm: AppRealm.life,
        name: 'خواب شبانه',
      );
      final sleepNapChild = ProjectNode(
        id: 'p_nap_child',
        realm: AppRealm.life,
        name: 'چرت بعدازظهر',
        parentId: 'p_sleep_root',
      );
      await provider.saveProject(sleepRoot);
      await provider.saveProject(sleepNapChild);

      final t3 = t2.add(const Duration(minutes: 50));
      await provider.switchRealm(
        AppRealm.life,
        projectId: 'p_nap_child',
        title: 'چرت کوتاه',
        atTime: t3,
      );
      expect(provider.cycleWorkSeconds, 3000);

      final t4 = t3.add(const Duration(minutes: 20));
      await provider.switchRealm(AppRealm.work, title: 'بعد چرت', atTime: t4);
      expect(provider.cycleWorkSeconds, 0);
      expect(provider.breakDebtSeconds, 0);

      await db.close();
    });

    test('Ch2: live swapCurrentSliceRealm and historical swapSavedRecordRealm cascade notes & bank',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 16, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      final workProj = ProjectNode(
        id: 'p_work',
        realm: AppRealm.work,
        name: 'کدنویسی',
      );
      await provider.saveProject(workProj);

      // شروع برش اشتباهی با عنوان کار در حالی که کاربر در واقع استراحت می‌کرده
      await provider.switchRealm(
        AppRealm.work,
        title: 'گپ با همکار',
        projectId: 'p_work',
        atTime: t0,
      );
      final liveRecId = provider.activeRecord!.id;

      await provider.saveSessionNote(SessionNote(
        id: 'n_live',
        realm: AppRealm.work,
        noteType: SessionNoteType.general,
        timeRecordId: liveRecId,
        projectId: 'p_work',
        content: 'موضوع گپ',
      ));

      // سوییچ درجا (Swap Live) پس از ۱۰ دقیقه: نباید رکورد بسته و دوباره باز شود!
      await provider.swapCurrentSliceRealm(
        atTime: t0.add(const Duration(minutes: 10)),
      );

      expect(provider.activeRecord!.id, liveRecId);
      expect(provider.activeRecord!.startTime, t0);
      expect(provider.activeRecord!.realm, AppRealm.life);
      expect(provider.activeRecord!.projectId, isNull); // پروژه کار با زندگی پاک می‌شود
      expect(provider.pomodoroState.elapsedSeconds, 600);
      expect(provider.timeRecords.length, 1);

      final cascadedNotes =
          await DatabaseService.instance.getSessionNotesForRecord(liveRecId);
      expect(cascadedNotes.first.realm, AppRealm.life);
      expect(cascadedNotes.first.projectId, isNull);

      // پایان برش زندگی و تبدیل یک رکورد ذخیره‌شده کار <-> زندگی
      final t1 = t0.add(const Duration(minutes: 15));
      await provider.switchRealm(AppRealm.work, title: 'کار واقعی', atTime: t1);
      final t2 = t1.add(const Duration(minutes: 25)); // ۱۵۰۰ ثانیه کار
      await provider.switchRealm(AppRealm.life, atTime: t2);

      final realWorkRec = provider.timeRecords
          .firstWhere((r) => r.titleSnapshot == 'کار واقعی');
      expect(provider.cycleWorkSeconds, 1500);

      await provider.swapSavedRecordRealm(realWorkRec.id);
      expect(provider.cycleWorkSeconds, 0);

      await db.close();
    });

    test('Ch3: crash recovery auto-resumes open TimeRecord and supports closing at chosen time',
        () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 5,
          singleInstance: false,
          onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
        ),
      );
      DatabaseService.instance.setTestDatabase(db);

      final startedAt = DateTime.now().subtract(const Duration(minutes: 15));
      final openRec = TimeRecord(
        id: 'crashed_rec_1',
        realm: AppRealm.work,
        clockMode: ClockType.pomodoro,
        titleSnapshot: 'توسعه ماژول قبل از قطعی برق',
        isUntitledDraft: false,
        startTime: startedAt,
        endTime: null,
      );
      await DatabaseService.instance.insertTimeRecord(openRec);

      final provider = AppStateProvider(isTestMode: true);
      await provider.initialize();

      expect(provider.recoveredOpenRecord, isNotNull);
      expect(provider.recoveredOpenRecord!.id, 'crashed_rec_1');
      expect(provider.activeRecord?.id, 'crashed_rec_1');
      expect(provider.activeRecordElapsedSeconds, greaterThanOrEqualTo(895));

      // کاربر انتخاب می‌کند که جلسه را ۱۰ دقیقه بعد از شروع ببندد و به زندگی برود
      final chosenEnd = startedAt.add(const Duration(minutes: 10));
      await provider.closeRecoveredRecordAtTimeAndStartNew(
        closedAt: chosenEnd,
        nextRealm: AppRealm.life,
      );

      final closed =
          await DatabaseService.instance.getTimeRecordById('crashed_rec_1');
      expect(closed!.endTime, chosenEnd);
      expect(closed.durationSeconds, 600);
      expect(closed.isEdited, isTrue);
      expect(provider.recoveredOpenRecord, isNull);
      expect(provider.activeRecord?.realm, AppRealm.life);
      expect(provider.activeRecord?.startTime, chosenEnd);

      await db.close();
    });

    test('Ch6: DateTimeUtils.startOfJalaliWeek resolves every weekday to Saturday 00:00',
        () {
      // شنبه ۱۴ نوامبر ۲۰۲۶
      final sat = DateTime(2026, 11, 14, 23, 59, 59);
      final sun = DateTime(2026, 11, 15, 12, 30);
      final mon = DateTime(2026, 11, 16, 8, 15);
      final wed = DateTime(2026, 11, 18, 18, 45);
      final fri = DateTime(2026, 11, 20, 23, 59);

      final expectedSat = DateTime(2026, 11, 14, 0, 0, 0);
      expect(DateTimeUtils.startOfJalaliWeek(sat), expectedSat);
      expect(DateTimeUtils.startOfJalaliWeek(sun), expectedSat);
      expect(DateTimeUtils.startOfJalaliWeek(mon), expectedSat);
      expect(DateTimeUtils.startOfJalaliWeek(wed), expectedSat);
      expect(DateTimeUtils.startOfJalaliWeek(fri), expectedSat);
    });
  });

  group('Break Calculation Bug Regression Tests', () {
    test('35 minutes of clean work grants exact 7m (420s) break, never 12m',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 8, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      // ۲۵ دقیقه -> ۵ دقیقه
      await provider.switchRealm(AppRealm.work, title: 'ست ۲۵', atTime: t0);
      final t25 = t0.add(const Duration(minutes: 25));
      await provider.switchRealm(AppRealm.life, atTime: t25);
      expect(provider.earnedShortBreakSeconds, 300);
      expect(provider.pomodoroState.targetSeconds, 300);
      expect(provider.isInLongBreak, isFalse);

      // ریست و تست دقیق ۳۵ دقیقه کار -> ۷ دقیقه (۴۲۰ ثانیه)
      final tStart35 = t25.add(const Duration(minutes: 10));
      await provider.resetFlowmodoroCycle(atTime: tStart35);
      await provider.switchRealm(AppRealm.work,
          title: 'ست ۳۵ دقیقه‌ای', atTime: tStart35);
      final tEnd35 = tStart35.add(const Duration(minutes: 35));
      await provider.switchRealm(AppRealm.life, atTime: tEnd35);

      expect(provider.cycleWorkSeconds, 2100);
      expect(provider.earnedShortBreakSeconds, 420);
      expect(provider.breakDebtSeconds, 0);
      expect(provider.isInLongBreak, isFalse);
      expect(provider.currentBreakTargetSeconds, 420);
      expect(provider.pomodoroState.targetSeconds, 420);
      expect(provider.breakTargetExplanationFa, contains('07:00'));

      await db.close();
    });

    test(
        'mid-session cycle reset excludes pre-reset work from bank and matches history recalculation',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 20, 0);

      // کاربر کار را از ۲۰:۰۰ شروع می‌کند
      await provider.switchRealm(AppRealm.work,
          title: 'کار طولانی قبل و بعد ریست', atTime: t0);

      // در ۲۰:۳۰ (وسط رکورد فعال) کاربر چرخه را ریست می‌کند
      final tReset = t0.add(const Duration(minutes: 30));
      await provider.resetFlowmodoroCycle(atTime: tReset);

      // پس از ریست ۳۵ دقیقه دیگر ادامه می‌دهد و در ۲۱:۰۵ وارد استراحت می‌شود
      final tSwitchLife = tReset.add(const Duration(minutes: 35));
      await provider.switchRealm(AppRealm.life, atTime: tSwitchLife);

      // تایم‌شیت باید ۶۵ دقیقه کامل را ثبت کند، ولی بانک چرخه فقط ۳۵ دقیقه بعد از ریست را حساب کند
      final closedWork = provider.timeRecords
          .firstWhere((r) => r.titleSnapshot == 'کار طولانی قبل و بعد ریست');
      expect(closedWork.durationSeconds, 65 * 60);
      expect(provider.cycleWorkSeconds, 35 * 60);
      expect(provider.earnedShortBreakSeconds, 7 * 60);
      expect(provider.pomodoroState.targetSeconds, 7 * 60);

      // اضافه کردن یک رکورد کار کوچک قبلی (پیش از ریست) برای تحریک _recalculateCurrentCycleBankFromHistory
      await provider.createManualTimeRecord(
        realm: AppRealm.work,
        clockMode: ClockType.pomodoro,
        title: 'رکورد قدیمی قبل از ریست',
        startTime: t0.subtract(const Duration(minutes: 40)),
        endTime: t0.subtract(const Duration(minutes: 10)),
      );
      // اکنون باید هنوز دقیقاً ۷ دقیقه (۴۲۰ ثانیه) باقی بماند، بدون نشت ۳۰ دقیقه قبل از ریست!
      expect(provider.cycleWorkSeconds, 35 * 60);
      expect(provider.earnedShortBreakSeconds, 7 * 60);
      expect(provider.breakDebtSeconds, 0);
      expect(provider.pomodoroState.targetSeconds, 7 * 60);

      await db.close();
    });

    test(
        'pre-work Life activity (or <breakRatio accidental toggle) accrues zero break debt',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 20, 38);
      await provider.resetFlowmodoroCycle(atTime: t0);

      // ۴ ثانیه سوییچ اشتباهی کار (کمتر از ۵ ثانیه => earned = 0)
      await provider.switchRealm(AppRealm.work, title: 'تاگل لحظه‌ای', atTime: t0);
      final t1 = t0.add(const Duration(seconds: 4));
      await provider.switchRealm(AppRealm.life, title: 'تماشای سریال', atTime: t1);

      // ۴۸.۵ دقیقه زندگی پیش از شروع کار جدی
      final t2 = t1.add(const Duration(minutes: 48, seconds: 30));
      await provider.switchRealm(AppRealm.work, title: 'کار واقعی شبانه', atTime: t2);

      // بدهی باید دقیقاً ۰ باشد تا استراحت طولانی ۱۰۰د خراب نشود
      expect(provider.breakDebtSeconds, 0);
      expect(provider.cycleWorkSeconds, 0);

      // ۱۰۰ دقیقه کار متوالی -> باید استراحت طولانی کامل ۶۰ دقیقه بدهد، نه ۱۲ دقیقه!
      final t3 = t2.add(const Duration(minutes: 100));
      await provider.switchRealm(AppRealm.life, atTime: t3);
      expect(provider.isInLongBreak, isTrue);
      expect(provider.currentBreakTargetSeconds, 3600);
      expect(provider.pomodoroState.targetSeconds, 3600);
      expect(provider.breakTargetExplanationFa, contains('01:00:00'));

      await db.close();
    });

    test(
        'switching sub-activities inside Life preserves Long Break state including after history recalculation',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 10, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      await provider.switchRealm(AppRealm.work, title: 'توسعه عمیق', atTime: t0);
      final t1 = t0.add(const Duration(minutes: 100));
      await provider.switchRealm(AppRealm.life, atTime: t1);

      expect(provider.isInLongBreak, isTrue);
      expect(provider.currentBreakTargetSeconds, 3600);

      // سوییچ به یک هدف زندگی دیگر پس از ۱۰ دقیقه حین همان استراحت طولانی (کمتر از آستانه ۹۰د)
      await provider.saveOutcome(OutcomeItem(
        id: 'life_lunch',
        realm: AppRealm.life,
        title: 'ناهار و استراحت',
      ));
      final lunch = provider.getOutcomeById('life_lunch')!;
      final tSwitchInLife = t1.add(const Duration(minutes: 10));
      await provider.startOrSwitchToOutcome(lunch, atTime: tSwitchInLife);

      // هنوز در استراحت طولانی هستیم و نباید چرخه ریست شده یا بدهی کاذب بسازد
      expect(provider.isInLongBreak, isTrue);
      expect(provider.cycleWorkSeconds, 6000);
      expect(provider.breakDebtSeconds, 0);
      expect(provider.pomodoroState.targetSeconds, 3600);

      // تحریک بازمحاسبه تاریخچه با ثبت یک کار ۵ دقیقه‌ای اضافی درون چرخه جاری (در حین برش دوم زندگی)
      await provider.createManualTimeRecord(
        realm: AppRealm.work,
        clockMode: ClockType.pomodoro,
        title: 'مرور کد درون چرخه',
        startTime: t0.add(const Duration(minutes: 1)),
        endTime: t0.add(const Duration(minutes: 6)),
      );
      expect(provider.isInLongBreak, isTrue);
      expect(provider.pomodoroState.targetSeconds, 3660); // 60m + (300 ~/ 5 = 60s سرریز)

      // فقط با بازگشت به کار است که چرخه استراحت طولانی بسته و ریست می‌شود
      await provider.switchRealm(
        AppRealm.work,
        title: 'شروع چرخه تازه',
        atTime: tSwitchInLife.add(const Duration(minutes: 50)),
      );
      expect(provider.isInLongBreak, isFalse);
      expect(provider.cycleWorkSeconds, 0);
      expect(provider.breakDebtSeconds, 0);

      await db.close();
    });

    test('transparent break formula explains long-break debt deduction accurately',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 9, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      // ۷۰ دقیقه کار (۴۲۰۰ ثانیه -> ذخیره ۸۴۰ث = ۱۴د)
      await provider.switchRealm(AppRealm.work, title: 'بخش ۱', atTime: t0);
      final t1 = t0.add(const Duration(minutes: 70));
      await provider.switchRealm(AppRealm.life, atTime: t1);

      // ۶۴د و ۱۴ث در زندگی -> زیاده‌برداشت دقیق ۵۰ دقیقه و ۱۴ ثانیه (۳۰۱۴ ثانیه)
      final t2 = t1.add(const Duration(seconds: 840 + 3014));
      await provider.switchRealm(AppRealm.work, title: 'بخش ۲', atTime: t2);
      expect(provider.breakDebtSeconds, 3014);

      // ۳۵ دقیقه کار دوم -> کل چرخه = ۱۰۵د = ۶۳۰۰ث (سرریز ۳۰۰ث -> ۶۰ث اضافه) -> هدف = 3600 - 3014 + 60 = 646s
      final t3 = t2.add(const Duration(minutes: 35));
      await provider.switchRealm(AppRealm.life, atTime: t3);

      expect(provider.isInLongBreak, isTrue);
      expect(provider.earnedShortBreakSeconds, 420); // ۷ دقیقه باقی در ذخیره کوتاه
      expect(provider.currentBreakTargetSeconds, 646); // ۱۰:۴۶ استراحت طولانی با کسر بدهی
      expect(provider.breakTargetExplanationFa, contains('استراحت طولانی پایان چرخه'));
      expect(provider.breakTargetExplanationFa, contains('بدهی'));
      expect(provider.breakTargetExplanationFa, contains('سرریز'));

      await db.close();
    });

    test('concurrent switchRealm calls serialize without leaving duplicate open records',
        () async {
      final (db, provider) = await createTestProvider();
      final t0 = DateTime(2026, 11, 10, 12, 0);
      await provider.resetFlowmodoroCycle(atTime: t0);

      await Future.wait([
        provider.switchRealm(AppRealm.work, title: 'کار هم‌زمان ۱', atTime: t0),
        provider.switchRealm(AppRealm.life,
            atTime: t0.add(const Duration(seconds: 10))),
        provider.switchRealm(AppRealm.work,
            title: 'کار هم‌زمان ۲',
            atTime: t0.add(const Duration(seconds: 20))),
      ]);

      final openRecords =
          provider.timeRecords.where((r) => r.endTime == null).toList();
      expect(openRecords.length, 1);
      expect(openRecords.first.titleSnapshot, 'کار هم‌زمان ۲');
      expect(provider.activeRecord?.id, openRecords.first.id);

      await db.close();
    });
  });
}
