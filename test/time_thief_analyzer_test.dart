import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/core/date_time_utils.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/project_node.dart';
import 'package:mab_focus/models/scheduled_block.dart';
import 'package:mab_focus/models/time_record.dart';
import 'package:mab_focus/services/time_thief_analyzer.dart';

void main() {
  group('TimeThiefAnalyzer Hierarchy & Dual-Realm Tests', () {
    test('weekly capacity rolls up multi-level descendants without double counting',
        () {
      final root = ProjectNode(
        id: 'p_root',
        realm: AppRealm.work,
        name: 'فروشگاه آنلاین',
        weeklyQuotaMinutes: 600,
      );
      final child = ProjectNode(
        id: 'p_child',
        realm: AppRealm.work,
        name: 'فلاتر موبایل',
        parentId: 'p_root',
        weeklyQuotaMinutes: 300,
      );
      final grandchild = ProjectNode(
        id: 'p_grandchild',
        realm: AppRealm.work,
        name: 'صفحه سبد خرید',
        parentId: 'p_child',
        weeklyQuotaMinutes: 0,
      );

      final refDate = DateTime(2026, 11, 16, 10, 0); // دوشنبه
      final weekStart = DateTimeUtils.startOfJalaliWeek(refDate);

      final records = [
        // رکورد هفته جاری روی ریشه (۶۰ دقیقه)
        TimeRecord(
          id: 'r1',
          realm: AppRealm.work,
          projectId: 'p_root',
          titleSnapshot: 'جلسه معماری',
          isUntitledDraft: false,
          startTime: weekStart.add(const Duration(hours: 9)),
          endTime: weekStart.add(const Duration(hours: 10)),
          durationSeconds: 3600,
        ),
        // رکورد هفته جاری روی فرزند (۱۲۰ دقیقه)
        TimeRecord(
          id: 'r2',
          realm: AppRealm.work,
          projectId: 'p_child',
          titleSnapshot: 'ساخت سرویس',
          isUntitledDraft: false,
          startTime: weekStart.add(const Duration(days: 1, hours: 9)),
          endTime: weekStart.add(const Duration(days: 1, hours: 11)),
          durationSeconds: 7200,
        ),
        // رکورد هفته جاری روی نوه (۱۸۰ دقیقه)
        TimeRecord(
          id: 'r3',
          realm: AppRealm.work,
          projectId: 'p_grandchild',
          titleSnapshot: 'ویجت کارت',
          isUntitledDraft: false,
          startTime: weekStart.add(const Duration(days: 2, hours: 9)),
          endTime: weekStart.add(const Duration(days: 2, hours: 12)),
          durationSeconds: 10800,
        ),
        // رکورد هفته گذشته (نباید در سهمیه این هفته حساب شود)
        TimeRecord(
          id: 'r_old',
          realm: AppRealm.work,
          projectId: 'p_grandchild',
          titleSnapshot: 'کار هفته قبل',
          isUntitledDraft: false,
          startTime: weekStart.subtract(const Duration(days: 2)),
          endTime: weekStart.subtract(const Duration(days: 2))
              .add(const Duration(hours: 4)),
          durationSeconds: 14400,
        ),
      ];

      final reports = TimeThiefAnalyzer.calculateWeeklyCapacityReport(
        projects: [root, child, grandchild],
        records: records,
        realmFilter: AppRealm.work,
        referenceDate: refDate,
      );

      final rootRep = reports.firstWhere((r) => r.project.id == 'p_root');
      final childRep = reports.firstWhere((r) => r.project.id == 'p_child');
      final grandRep =
          reports.firstWhere((r) => r.project.id == 'p_grandchild');

      // ریشه = 60 + 120 + 180 = 360 دقیقه (بدون شمارش تکراری و بدون هفته قبل)
      expect(rootRep.usedMinutes, 360);
      expect(rootRep.varianceMinutes, -240);

      // فرزند = 120 + 180 = 300 دقیقه
      expect(childRep.usedMinutes, 300);
      expect(childRep.varianceMinutes, 0);

      // نوه = 180 دقیقه
      expect(grandRep.usedMinutes, 180);
    });

    test('matches descendant work records and detects cross-realm time thieves',
        () {
      final root = ProjectNode(
        id: 'p_root',
        realm: AppRealm.work,
        name: 'پروژه اصلی',
      );
      final child = ProjectNode(
        id: 'p_child',
        realm: AppRealm.work,
        name: 'بک‌اند',
        parentId: 'p_root',
      );
      final grandchild = ProjectNode(
        id: 'p_grandchild',
        realm: AppRealm.work,
        name: 'تست API',
        parentId: 'p_child',
      );
      final otherWorkProj = ProjectNode(
        id: 'p_other',
        realm: AppRealm.work,
        name: 'پروژه متفرقه',
      );
      final gymProj = ProjectNode(
        id: 'p_gym',
        realm: AppRealm.life,
        name: 'ورزش',
      );

      final day = DateTime(2026, 11, 16);
      final workBlock = ScheduledBlock(
        id: 'b_work',
        realm: AppRealm.work,
        title: 'توسعه پروژه اصلی',
        projectId: 'p_root',
        startTime: day.add(const Duration(hours: 9)),
        endTime: day.add(const Duration(hours: 11)),
      );
      final lifeBlock = ScheduledBlock(
        id: 'b_life',
        realm: AppRealm.life,
        title: 'باشگاه عصر',
        projectId: 'p_gym',
        startTime: day.add(const Duration(hours: 18)),
        endTime: day.add(const Duration(hours: 19)),
      );

      final records = [
        // ۱. کار روی نوه پروژه اصلی -> کاملاً منطبق است و سارق زمان نیست!
        TimeRecord(
          id: 'r_match_descendant',
          realm: AppRealm.work,
          projectId: 'p_grandchild',
          titleSnapshot: 'تست اندپوینت',
          isUntitledDraft: false,
          startTime: day.add(const Duration(hours: 9)),
          endTime: day.add(const Duration(hours: 10)),
          durationSeconds: 3600,
        ),
        // ۲. پروژه کاری دیگر در ساعت بلوک اصلی -> سارق زمان (۳۰ دقیقه)
        TimeRecord(
          id: 'r_wrong_proj',
          realm: AppRealm.work,
          projectId: 'p_other',
          titleSnapshot: 'تیکت متفرقه',
          isUntitledDraft: false,
          startTime: day.add(const Duration(hours: 10)),
          endTime: day.add(const Duration(hours: 10, minutes: 30)),
          durationSeconds: 1800,
        ),
        // ۳. زمان زندگی در ساعت بلوک کاری -> سارق زمان (۳۰ دقیقه)
        TimeRecord(
          id: 'r_life_in_work',
          realm: AppRealm.life,
          titleSnapshot: 'استراحت طولانی میان کار',
          isUntitledDraft: false,
          startTime: day.add(const Duration(hours: 10, minutes: 30)),
          endTime: day.add(const Duration(hours: 11)),
          durationSeconds: 1800,
        ),
        // ۴. کار کردن در زمان برنامه‌ریزی‌شده باشگاه زندگی -> سارق زمان (۲۰ دقیقه)
        TimeRecord(
          id: 'r_work_in_life',
          realm: AppRealm.work,
          projectId: 'p_root',
          titleSnapshot: 'پاسخ ایمیل در وقت باشگاه',
          isUntitledDraft: false,
          startTime: day.add(const Duration(hours: 18)),
          endTime: day.add(const Duration(hours: 18, minutes: 20)),
          durationSeconds: 1200,
        ),
      ];

      final thieves = TimeThiefAnalyzer.analyzeTimeThieves(
        plannedBlocks: [workBlock, lifeBlock],
        actualRecords: records,
        projects: [root, child, grandchild, otherWorkProj, gymProj],
      );

      expect(
        thieves.any((t) => t.actualRecord.id == 'r_match_descendant'),
        isFalse,
      );
      expect(thieves.length, 3);
      expect(
        thieves.firstWhere((t) => t.actualRecord.id == 'r_wrong_proj').stolenSeconds,
        1800,
      );
      expect(
        thieves.firstWhere((t) => t.actualRecord.id == 'r_life_in_work').stolenSeconds,
        1800,
      );
      expect(
        thieves.firstWhere((t) => t.actualRecord.id == 'r_work_in_life').stolenSeconds,
        1200,
      );
    });
  });
}
